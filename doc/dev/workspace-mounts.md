Workspace Mounts
================

A workspace **mount** attaches an external source tree to a user-facing
context. The mount sources are built alongside the workspace's own sources
but live at an external filesystem path. Each mount becomes an additional
*internal* build context, sharing the parent user-facing context's
toolchain configuration. Libraries, executables, packages, and module
artifacts declared in a mount are visible from the workspace (and from
other mounts) through per-resource sibling-fallback lookups in the rules
layer.

The user-facing syntax lives in `dune-workspace`:

```
(context
 (default
  (mount /home/ali/some-project)))
```


Motivation
----------

Three eventual features motivated this work, all of which need the
ability for a build context to read source from somewhere other than the
workspace filesystem:

1. **`dune build -r <sha>`** — building at a git revision; the context's
   source tree comes from a git object.
2. **`dune pkg`-fetched source mounts** — fetched packages whose sources
   land as build artifacts to be read by the rest of the build.
3. **Multi-project on filesystem with selective promotability** — multiple
   projects on disk built together under one `dune` invocation, each
   tracked separately for promotion.

The mount feature implements (3) and provides the substrate for (1) and
(2). All three reduce to "a context reads its source from somewhere
other than the workspace filesystem".


User Model
----------

From the user's perspective:

- A user-facing context (`(context (default ...))` or `(context (opam
  ...))`) declares any number of `(mount <abs-path>)` fields.
- Each mount points at an absolute filesystem path containing a dune
  project to build.
- Workspace sources and mount sources are NOT isolated: cross-mount
  library deps, binary references (`%{bin:...}`), package references
  (`(deps (package ...))`), etc. all work bidirectionally.
- Each mount is built into a distinct sub-directory of the build dir,
  named after the mount's basename: `_build/<context>.<mount>/`.
- Promotion writes back to the right filesystem path because each
  mount's `Source_tree.t` carries its own resolver.


Architecture
------------

The dune layering is preserved: the engine (`src/dune_engine`) is
unaware of mounts; the rules layer (`src/dune_rules`) is where mount
relationships are known and consulted.

### Engine view (dune_engine)

- One source tree per internal context (engine-opaque).
- `Build_config.set ~source_trees:(module Source_tree) Context_name.Map.t`
  registers per-context source-tree backings.
- The engine never asks "is this context a mount?". It just looks up
  the source tree by context name.

### Rules view (dune_rules)

- A `Workspace.Context.t` (one per `(context ...)` stanza) is the
  *user-facing* context.
- A `Workspace.Context.t` spawns multiple *internal* contexts via
  `Group.t = { native; targets; mounts }` in `context.ml`:
    - `native` — the workspace base.
    - `targets` — cross-compile siblings of native (one per
      `(targets ...)` entry).
    - `mounts` — one internal context per mount, with the same
      toolchain config as the parent's native but a different name and
      build_dir.
- `Per_context.siblings : Context_name.t -> Context_name.t list Memo.t`
  exposes the "siblings of this internal context within its
  user-facing context" relation. The rules layer's cross-mount
  fallbacks all consult this.

This is the same pattern dune already uses for cross-compilation:
internal contexts are siblings within a Group, and the rules layer
knows which siblings are related.


Source-Tree Backings
--------------------

`Source_tree.t` carries the bytes-fetching strategy:

- `Source_tree.default` — the workspace filesystem, identity resolver.
- `Source_tree.of_external_root ?read_only path` — an
  externally-rooted tree backed by `Source_resolver`, which translates
  workspace-relative `Path.Source.t` to `Path.Outside_build_dir.t`.

A `Source_resolver.t` wraps a `Path.Source.t → Path.Outside_build_dir.t`
function with a unique `Id.t`. The engine's
`Build_config.Source_tree.Dir.file_path` returns the resolved physical
location so the engine never interprets `Path.Source.t` itself — the
source-to-build-dir copy rule (`Load_rules.copy_source_action`) uses
the resolved external path directly.

Future backings (`of_git_tree`, `of_fetched_archive`) plug in at the
same point.


Pipeline
--------

```
dune-workspace
    │
    ▼
Workspace.workspace ()                          Phase 0
    │   parses (mount …) into Workspace.Context.Mount.t
    ▼
Workspace.build_contexts                        Phase 1
    │   user-facing context × mounts × targets
    │   → (Build_context.t × Build_context_source.t) list
    │      where source = Workspace | Mount of Path.External.t
    ▼
main.ml: source_tree_of_context map             Phase 2
    │   Workspace → Source_tree.default
    │   Mount path → Source_tree.of_external_root path
    │   (deduplicated per unique mount path)
    ▼
Build_config.set ~source_trees                  Phase 3
    │
    ▼
Group.create (context.ml)                       Phase 4
    │   builds Context.t per (mount × {native, cross-target})
    │   sharing the parent's toolchain configuration
    ▼
Context.DB.all flattens to Context.t list       Phase 5
    │   (native :: targets) @ mounts per user-facing context
    ▼
Per_context.all keys all internal contexts      Phase 6
    │   by name; carries parent Workspace.Context.t
    │
    ▼
Per_context.siblings ctx                        Phase 7
    │   the cross-mount-aware lookup helper
    │
    ▼
rules-layer cross-mount fallbacks               Phase 8
    │
    ├── Scope.DB / Lib.DB sibling layer
    ├── Artifacts.t binary sibling layer
    ├── Expander.expand_artifact Lib mode fallback
    ├── Expander.expand_artifact Mod kind translation
    └── Package_db.find_package sibling fallback
```


Cross-Mount Lookup Mechanisms
-----------------------------

Each cross-mount lookup is in the rules layer and uses
`Per_context.siblings` to discover sibling contexts. The mechanisms
are independent — each lookup type gets its own fallback shape.

### 1. Library resolution (`(libraries bar)`)

**File:** `src/dune_rules/scope.ml` (`Scope.DB.create`).

A *sibling Lib.DB* is inserted as the parent of each context's
`public_libs` DB, replacing what was previously
`~parent:installed_libs`:

```
local lib DB (per-project)
  → public_libs (this context, parent: sibling_db)
  → sibling_db (NEW; parent: installed_libs)
  → installed_libs
```

The sibling DB precomputes (via `Memo.Lazy`) each sibling context's
public-library *names* by walking its dune files. At resolve time, if
the requested name is in any sibling's set, the DB emits
`Redirect_by_name` to that sibling's `public_libs`. The sibling's DB
has its own `Fdecl` backref to *its* scope, so the redirect resolves
locally — no cross-context redirect recursion.

The sibling DB is deferred so that constructing context A's scope
doesn't force context B's scope (avoiding Memo cycles); the lookup
happens after each context's scope DB is fully constructed.

`%{lib:bar:archives}`, `%{lib-exec:...}`, and Merlin all consult
`Scope.DB.public_libs ctx` and inherit this fallback transparently.
The install-context for the resulting path is derived from the
returned `Lib.info.src_dir` (extracting the build-context prefix), so
the path correctly points at the owning context's install dir.

### 2. Binary resolution (`%{bin:helper}`)

**File:** `src/dune_rules/artifacts.ml`, `artifacts_db.ml`.

`Artifacts.t` gains a `siblings : t list Memo.Lazy.t` field, populated
by `Artifacts_db.all` via `Per_context.siblings` and a forward `Fdecl`
to break the construction-time cycle.

`Artifacts.analyze_binary` falls through to siblings (only for
`In_path` mode — `Relative_to_current_dir` is anchored to the
caller's directory and not meaningful cross-mount) when the local
`local_bins` map and PATH miss. A local-only helper
`analyze_binary_local` is used for sibling queries to avoid recursion
through the sibling layer.

### 3. Library archive pforms (`%{cma:bar}`, `%{cmxa:bar}`)

**File:** `src/dune_rules/expander.ml` (`expand_artifact`, `Lib` arm).

The per-dir `Artifacts_obj.lookup_library` only sees libraries
declared in the local context. When that misses, fall through to the
scope's `public_libs` Lib.DB (which has the cross-mount fallback from
§1). The returned `Lib.t`'s archive paths point at the owning
context's build dir.

### 4. Module artifact pforms (`%{cmo:Mod}`, `%{cmi:Mod}`, etc.)

**File:** `src/dune_rules/expander.ml` (`expand_artifact`, `Mod` arm).

`Artifacts_obj.lookup_module` is keyed by `Path.Build.t` (the build
path of the source file with extension stripped). The path embeds the
context prefix, so a workspace rule's lookup never matches a sibling's
modules.

Fallback: extract the rule's build-context name + source suffix from
the lookup path, re-prepend each sibling's build-dir, and query that
sibling's per-dir `Artifacts_obj.t`. A single match emits the
artifact; multiple matches across siblings raise an ambiguity error.

### 5. Package resolution (`(deps (package mountpkg))`, `%{pkg:...}`)

**File:** `src/dune_rules/package_db.ml`.

`Package_db.find_package` consults `Dune_load.packages` locally; on
miss, iterates `Per_context.siblings` and checks each sibling's
package map before falling through to `Pkg_rules` (lock-file
packages, unchanged) or findlib.

### 6. Install rules

Already correct without further plumbing. Each internal context
(including each mount) emits its own install rules at
`_build/install/<ctx>/...`, picked up by `dune build @install` via
`Context.DB.all`.


Path Conventions
----------------

| Path | Meaning | Example |
|---|---|---|
| User-supplied `(mount /abs/path)` | absolute external filesystem path | `/home/ali/my-mount` |
| Internal context name | `<parent>.<mount-basename>` | `default.my-mount` |
| Mount's build dir | `_build/<internal-ctx>/...` | `_build/default.my-mount/lib/bar.cma` |
| Mount's install dir | `_build/install/<internal-ctx>/lib/<package>/...` | `_build/install/default.my-mount/lib/bar/META` |
| `Path.Source.t` in mount tree | mount-relative; same identity space as the mount tree's resolver expects | `lib/bar.ml` |

`Path.Source.t` is per-tree — workspace paths and mount paths are NOT
disambiguated by their values. Disambiguation is by which
`Source_tree.t` the path is interpreted in. Engine-level path
resolution goes through `Source_tree.Dir.file_path`, never
`Path.source` directly.


Key Files
---------

| File | Role |
|---|---|
| `src/source/workspace.ml` | `(mount …)` parsing; `Context.Mount.t`; `Build_context_source.t`; `Group`-aware `build_contexts` |
| `src/source/source_tree.ml` | `Source_tree.t`; `default`; `of_external_root`; `Dir.file_path` |
| `src/source/source_resolver.ml` | `Path.Source.t → Path.Outside_build_dir.t` with stable `Id.t` |
| `src/dune_engine/build_config.ml(i)` | per-context source-tree registration; `Source_tree.Dir.file_path` in module type |
| `src/dune_engine/load_rules.ml` | source-to-build copy rules consume `Path.Outside_build_dir.t` directly |
| `src/dune_engine/action_builder.ml` | `record_dep_on_source_file_exn` takes `Path.Outside_build_dir.t` |
| `src/dune_rules/context.ml` | `Group.t` with `mounts` dimension; `Context.DB.all` flattens; `Per_context.all` maps all internal contexts |
| `src/dune_rules/per_context.ml(i)` | `Per_context.siblings` helper |
| `src/dune_rules/scope.ml` | Lib.DB sibling fallback layer |
| `src/dune_rules/artifacts.ml`, `artifacts_db.ml` | `Artifacts.t` sibling field; `analyze_binary` fallback |
| `src/dune_rules/expander.ml` | per-pform fallbacks (`Lib` and `Mod` artifact arms); install context derived from lib's own build dir |
| `src/dune_rules/package_db.ml` | cross-mount package resolution |
| `src/dune_rules/main.ml` | wires `source_tree_of_context` per-mount; constructs per-unique-mount `Source_tree.of_external_root` |


Open Limitations
----------------

- **`dune runtest` (the command, not the alias)** does not fan out
  across all contexts when called from a source directory. This is a
  pre-existing CLI semantics decision (single-context for source-dir
  invocations) and the same wrinkle exists for cross-compile
  contexts. `dune build @runtest` does iterate all contexts via the
  alias machinery.

- **Cross-mount package conflict semantics.** If two siblings declare
  the same package name, `Dune_load.workspace_packages` silently picks
  the first-context's. We currently inherit this for cross-mount and
  haven't decided whether to error, shadow, or namespace. Track via
  user reports.

- **Read-only mounts and parse warnings.** A mount built via
  `Source_tree.of_external_root ~read_only:true` (the default) is
  treated as fully vendored — dune-file parse warnings are not yet
  suppressed even though they're often spurious for read-only trees.
  Suppression requires either a `Dune_lang.Decoder` refactor or a
  fiber-local scope; deferred.

- **Mount × cross-compile target build dir naming.** A mount in a
  user-facing context with `(targets native android)` produces
  internal contexts `default.<mount>`, `default.<mount>.android`,
  etc. Cross-compiling mount sources Just Works, but the naming
  convention is implicit (basename + toolchain suffix). If two mounts
  share a basename across user-facing contexts, naming may collide;
  no explicit user-side rename mechanism exists yet.

- **Workspace-wide aggregation rules are not mount-aware.** The
  cross-mount lookup mechanisms above are all *resolution-side*: when
  a stanza names X, look across siblings until X is found. Two
  existing rules are instead *aggregating*: they walk the dune files
  of one context and emit a single artifact summarising them.

  - `compile_commands.json` (`src/dune_rules/compile_commands.ml`):
    `collect_entries sctx` calls `Dune_load.dune_files (Context.name
    ctx)` for a single internal context and writes
    `_build/<ctx>/compile_commands.json`. With mounts, each internal
    context produces its own file and none of them is the union. A
    C/C++ tool pointed at the workspace sees only one context's
    entries.

  - `ocaml-index` (`src/dune_rules/merlin/ocaml_index.ml`):
    `context_indexes` and `project_rule` iterate one context's
    dune_files; the `(ocaml-index)` alias is attached per-context
    per-project root. Cross-mount cmts are not fed into the aggregate,
    so jump-to-def across a mount boundary misses.

  The fix shape is different from the resolution fallbacks: instead
  of "iterate one context's dune files", iterate `Context.name ctx ::
  Per_context.siblings ctx` and concat. Decisions still owed: which
  internal context "owns" the aggregate output (probably the native
  one, to avoid N near-duplicate files per user-facing context); and
  how the `(ocaml-index)` alias is attached when project roots cross
  sibling boundaries.


Future Work
-----------

### Other Source_tree backings

`Source_tree.of_external_root` is one instance of a broader
abstraction. Two natural future backings:

- **`of_git_tree ~name ~repo ~rev`** — read source from a git tree
  object. Enables `dune build -r <sha>` by synthesising a context
  with this backing. Read-only.

- **`of_fetched_archive ~name ~url`** — for `dune pkg` integration,
  where fetched package sources need to participate in the build
  graph as a directory target. Read-only.

Both follow the existing pattern: register a `Source_resolver` whose
resolve function reads from the external store, and (for read-only
trees) propagate vendored status so the workspace-only behaviours
(parse warnings, missing-`dune-project` warning, etc.) suppress
naturally.


### `(rev …)` field on mounts

Once `of_git_tree` lands, the user-facing syntax extends to:

```
(context
 (default
  (mount /home/ali/project)
  (mount (path /home/ali/another) (rev abc123))))
```

A mount with `(rev …)` reads bytes from the git tree at that
revision rather than the working tree. The internal-context naming
needs to disambiguate `(mount /p)` and `(mount (path /p) (rev x))`
declared in the same context; an explicit `(name …)` field
alongside `(rev …)` is the planned mechanism.


### CLI `-r <sha>` synthesis

`dune build -r <sha>` synthesises an internal user-facing context at
CLI parse time, configured as `(mount (path .) (rev <sha>))` with
`(no_workspace_base)` (an internal-only flag — never user-facing
syntax — that suppresses the workspace base for that synthesised
context). The same machinery for `(mount …)` declarations handles
this transparently.


### Generalisation: "related contexts"

Cross-compile (`for_host`) and mounts both express
*sibling-context relations* in the rules layer. Today they're
encoded as separate fields on `Group.t` (`targets` and `mounts`) and
separate fallback mechanisms in each lookup. A natural future
refactor unifies these into a single "context relations" graph that
each cross-context lookup consults uniformly. The mount fallbacks
already structurally parallel `for_host`; consolidating them after
mounts have settled would simplify the rules layer.


### Per-context Scope.DB / Package DB construction

Some scaffolding work that was originally planned (#25, #26) turned
out unnecessary under the chosen sibling-fallback model: scope DBs
and package DBs remain per-internal-context, and the cross-context
visibility is added at lookup time rather than at construction. If
mount use cases push the system in a different direction (e.g.,
truly aggregated scope DBs), revisit.


Cram Test Coverage
------------------

`test/blackbox-tests/test-cases/workspace-mount/`:

- `basic.t` — mount feature foundation; build dirs materialise; rule
  generation walks the mount source tree.
- `cross-lib.t` — workspace lib `(libraries bar)` resolves bar from
  mount.
- `reverse-cross-lib.t` — bidirectional: mount lib resolves workspace
  lib.
- `cross-bin.t` — workspace rule `(run %{bin:helper})` resolves
  cross-mount executable.
- `cross-cma.t` — workspace rule `%{cma:bar}` expands to mount's
  archive.
- `cross-lib-macro.t` — `%{lib:bar:archives}` install-context
  derivation (intermediate state pin).
- `cross-cmo.t` — module-artifact pforms (`%{cmo:Mod}` etc.) resolve
  cross-mount.
- `cross-pkg.t` — `(deps (package mountpkg))` resolves cross-mount.
- `cross-ppx.t` — `(preprocess (pps mountppx))` resolves the PPX from
  a mount (transitive via Lib.DB).
- `cross-install.t` — mount packages emit install artifacts at the
  mount context's install dir.
- `cross-exe-link.t` — end-to-end: workspace executable links mount
  library and `dune exec` runs it.
