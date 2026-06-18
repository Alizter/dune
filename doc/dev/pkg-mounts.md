Pkg Mounts
==========

A **pkg mount** is a synthesised mount for a `(build (dune))` package
in a lockfile: the outer dune builds the package directly through the
sibling-context machinery instead of shelling out to `dune build -p`.
It is the third application of the source-tree-per-context substrate
described in `doc/dev/workspace-mounts.md`, alongside `dune build -r`
and user-declared workspace mounts.


Motivation
----------

Today every locked package — even one that purely uses dune as its
build system — goes through an opaque `(action (run dune build -p ...
@install))`. The outer build can't see across that boundary: rule
generation, profile selection, the workspace's toolchain, and
incremental change tracking all stop at the action and resume from the
install artefacts. For dune packages this is wasteful: the outer build
already speaks dune, the package's source ships dune files, and the
intermediate `dune` invocation is just a process boundary.

`(dune)` in a lockfile entry signals "this package builds with dune;
the outer build can drive it directly." When the outer build sees one,
it materialises a sibling internal context rooted at the package's
unpacked source and feeds its dune files into the same rule-generation
machinery as the workspace's own sources.


User Model
----------

There is no new user-facing syntax. The trigger is the existing
`(dune)` field in a lockfile entry:

```
(version 1.2.3)
(dune)
(source
 (fetch
  (url "https://example.com/pkg-1.2.3.tbz")
  (checksum md5=...)))
```

For each such entry, an internal sibling context is materialised at
`_build/<parent>.<pkg_name>/`. The package's libraries, binaries, etc.
become visible to the workspace through the same per-resource
sibling-fallback lookups already in place for workspace mounts.

User-declared mounts and pkg mounts coexist: they go through the same
`Workspace.Context.Mount.t` data structure and the same downstream
plumbing.


Architecture
------------

### One mount concept, two path kinds

`Workspace.Mount_path.t` carries the path a mount reads bytes from:

```
type t =
  | External of Path.External.t
  | Build of Path.Build.t
```

`External` paths come from user-declared `(mount ...)` stanzas in
`dune-workspace`. `Build` paths come from synthesised pkg mounts —
the unpacked source directory under `_build/_private/<ctx>/.pkg/<digest>/source`.

`Workspace.Context.Mount.t` is unified across both: the same record,
the same lifecycle, the same downstream consumers. The only
pkg-specific detail is `name_override`: pkg source directories all end
in `/source`, so the basename can't be used as the internal context's
name suffix. The synthesiser sets `name_override = Some pkg_name`;
user-declared mounts leave it `None` and fall back to the path
basename.

### Synthesis hook

`Workspace.workspace ()` calls a one-shot hook to augment each user-facing
context's mount list with synthesised pkg mounts:

```
val set_pkg_mounts_synthesiser
  :  (Context_name.t -> source_path:Path.Source.t -> Context.Mount.t list Memo.t)
  -> unit
```

`main.ml` wires it to `Pkg_rules.dune_built_pkgs_at_source`, which
parses the lockdir at the **source path** (not through `Build_system`,
to avoid cycling with rule generation), filters by build_command =
`Dune`, and emits one mount per qualifying package.

Source-path parsing is in `Lock_dir.read_at_source_path`: an
`Fs_memo`-tracked read that bypasses the workspace-loaded lockdir
data structure, which itself would re-enter `Workspace.workspace ()`.

### Source-tree backing for build paths

`Source_tree.of_build_dir : Path.Build.t -> t` constructs a source tree
whose bytes and listings come from a `Path.Build.t` root via the
build system:

- `readdir path` calls `Build_system.build_dir <build_path>` to
  ensure the producing rule has fired, then reads the directory.
- `byte_provider path` is `Build_system.read_file <build_path>`.
- `file_source path` returns `Vcs_blob (byte_provider path)` — the
  same "bytes via Memo" variant used by VCS-backed trees. This is
  what makes source-file copy rules correct: without it, the
  per-file copy rules in `load_rules.ml` resolve through
  `Filesystem (In_source_dir <logical>)` and fail with "File
  unavailable: <basename>" because the bytes don't live in the
  workspace's source dir.

### Per-backing file_source

The `backing` record now carries its own `file_source` closure rather
than branching on `vcs_tree : option`. Each backing supplies its own
strategy:

| Backing | `file_source` returns |
|---|---|
| `filesystem_backing` (workspace) | `Filesystem (resolver path)` |
| `of_external_root` | `Filesystem (resolver path)` |
| `of_vcs_tree` | `Vcs_blob (Vcs_tree.read_file vcs_tree path)` |
| `of_build_dir` | `Vcs_blob (Build_system.read_file (root/path))` |

This unification means `Dir.file_source` is a single line — no
conditional on the backing kind — and adding new backings won't need
to extend `load_rules.copy_source_action`.

### Backing-aware `(include ...)` resolution

`Source_resolver.t` used to carry only a `Path.Source.t ->
Path.Outside_build_dir.t` translator, locking `(include foo.inc)` into
filesystem reads via `Fs_memo`. VCS and build-dir backings installed
*vestigial* resolvers that satisfied the type but pointed includes at
the workspace source root rather than the backing's actual bytes —
silently breaking `(include foo.inc)` whenever a package ships
generated dune files in its tarball (`js_of_ocaml`, `mdx`, `ppxlib`,
...).

The resolver is now backing-aware: it carries `file_exists` and
`with_lexbuf_from_file` closures alongside `resolve`. Each backing
installs the right closures:

| Backing | `(include ...)` reads via |
|---|---|
| `filesystem_backing` / `of_external_root` | `Fs_memo` at the resolved path (unchanged) |
| `of_vcs_tree` | `Vcs_tree.read_file` → string → lexbuf |
| `of_build_dir` | `Build_system.with_file (root/path)` |

The resolver is persisted on `Source.Dune_file.t` (via `resolver :
Source_resolver.t`) so `src/dune_rules/dune_file.ml`'s `parse_stanzas`
— which re-evaluates `(include ...)` directives on persisted sexps —
uses the same read mechanism as the original load. Same for the
OCaml-syntax dune file path (`Script.t` carries the resolver).

The narrow `is_workspace` check (used only to suppress the
missing-dune-project warning for non-workspace trees) is preserved.

### Filesystem-only resolver fields (cleanup follow-up)

`backing.byte_provider` and `backing.file_source` are conceptually the
same "how do I get bytes" concern as the resolver's reads, just
wrapped differently (`string Memo.t` and `Build_config.source_file`
respectively). Once Source_resolver fully owns reads, `byte_provider`
can be removed and `file_source` derived from the resolver. Not done
in this round — the current shape works and the refactor is
mechanical.

### Lock_dir_active short-circuits on read-only trees

Sibling contexts (pkg mounts, external mounts, vcs revisions) do not
conceptually own a lockdir: the lockdir always belongs to the
workspace source. `Lock_dir.lock_dir_active` now short-circuits to
`false` for any context whose source tree has `read_only = true`:

```
let* source_tree = Source_tree.for_context ctx in
if Source_tree.read_only source_tree
then Memo.return false
else (* normal path: find_dir source_tree default_source_path *)
```

Without this, `Per_context.list ()` iterators (notably
`Fetch_rules.find_checksum` / `find_url`, which aggregate
checksums from every context's lockdir) re-enter
`lock_dir_active` on each sibling. For a build-dir-rooted sibling
that triggers `Source_tree.find_dir` → forces the sibling's
`root_node` → `Build_system.build_dir <source_dir>` → rule
generation, which loops back to `Per_context.list ()` while still
inside the original `root_node` force. Single-Memo-node cycle.

### Filter to directory-target sources

`Pkg_rules.dune_built_pkgs_at_source` only emits mounts for packages
whose `source_dir` is a directory target — i.e., source kind is
`Fetch` or `Local File`. For `Local Directory` sources, the per-file
copy rules populate `source_dir` but it isn't itself a directory
target, so `Build_system.build_dir <source_dir>` (the first step of
`of_build_dir`'s `readdir`) has nothing to build.

In practice this means pinned local directories don't get a pkg
mount; the existing inner-build-via-subprocess flow handles them. The
overwhelming common case — published opam packages with tarball or
git URLs — is covered.


Cram tests
----------

- `test/blackbox-tests/test-cases/pkg/mount/git-dune.t` — `git+file://`
  pin (Fetch source kind, git backend).
- `test/blackbox-tests/test-cases/pkg/mount/tarball-dune.t` — HTTP
  tarball + checksum (canonical published-opam-pkg shape).

Both assert `_build/default.dep/` materialises after the build, so
they pin the sibling-context synthesis, not just that the inner
subprocess happens to produce the right output.


Resolved Issues
---------------

These came up while scaling to real lockdirs (cohttp's 173-pkg
lockfile) and have been fixed.

### Toolchain not shared across sibling contexts (FIXED)

Each pkg-mount context used to resolve `ocaml-base-compiler` through
its own `Pkg_rules.DB.of_ctx <sibling-name>`, computing paths under
`_build/_private/<sibling>/.pkg/...` where no rule existed. Fix:
`Pkg_rules.resolve_pkg_dep` and `Pkg_rules.find_package` redirect
through a new `Per_context.user_facing` helper, so all pkg lookups
(`ocaml_toolchain`, `find_package`, `resolve_installed_file`) on a
sibling resolve through the parent context's DB and produce the
correct `_build/_private/<parent>/.pkg/...` paths.

### `(include ...)` resolution bypassed source-tree backings (FIXED)

`Source_resolver.t` carried only a `Path.Source.t ->
Path.Outside_build_dir.t` translator; `Include_stanza` used it to
read via `Fs_memo`. VCS and build-dir backings installed vestigial
resolvers that satisfied the type but pointed includes at the
workspace source root, breaking `(include foo.inc)` for any package
shipping generated dune files (js_of_ocaml, mdx, ppxlib, ...).

Fix: `Source_resolver.t` now carries `file_exists` and
`with_lexbuf_from_file` closures alongside `resolve`. Each backing
installs the right read mechanism (Fs_memo / Vcs_tree / Build_system).
Persisted on `Source.Dune_file.t` and threaded into `parse_stanzas`
so re-resolution uses the same backing. See "Backing-aware `(include
...)` resolution" above.


Open Issues
-----------

### 1. OCaml-syntax dune files in pkg mounts

Packages like `lwt` ship `src/unix/dune` as OCaml code that reads
sibling files relative to its cwd. `Script.eval_one` runs the
generated program with `cwd = Path.source eval.dir`, which for
pkg-mounts is the *workspace-relative* path interpretation of the
mount's source — not the actual build-mirror location where the bytes
live. Errors look like:

```
Error: open(src/dune): No such file or directory
-> required by - evaluating dune file "src/unix/dune" in OCaml syntax
```

The fix needs `Script.eval_one` to use the mount's actual physical
path (via the backing's resolver or the of_build_dir root) for the
cwd, not `Path.source eval.dir`. Different code path from the
`(include ...)` fix and not addressed yet.

### 2. Eager `Super_context.all` for siblings

`Super_context.all` forces sctx construction for every context,
including pkg-mount siblings. Each sctx calls `Dune_load.dune_files`,
which walks the mount's source tree. For 100+ pkg mounts this is
wasteful (most are never queried by the workspace build) and it's
also the reason every pkg's dune files get evaluated up-front, even
ones whose libraries the workspace never uses.

Sibling sctxs should be constructed lazily — only when something
actually resolves a library / binary / artefact through a
sibling-fallback lookup. Until that lands, every pkg-mount sibling
pays the full evaluation cost up front.

### 3. Dedup source trees by shared source URL

When two packages share the same upstream `(source (fetch ...))`
URL+checksum, the existing fetch-cache mechanism shares the
downloaded bytes (one `_build/.fetch/<checksum>` entry). But each
package still gets its own `_build/_private/<ctx>/.pkg/<digest>/source`
copy because `Paths.make` keys on `pkg_digest`, not on source.

Per-package source dirs aren't a correctness problem, but each one
materialises its own `Source_tree.t` and own sibling context. For
real lockdirs (e.g. multiple `eio_*` packages from the same tarball)
this is several redundant trees of the same bytes. Two fixes are
plausible:

- Key `source_dir` on `(source_url, checksum)` instead of `pkg_digest`
  so multiple packages reuse one directory. Bigger refactor of
  `Paths.make`.
- Dedup at the `Source_tree.t` level in `source_tree_of_context`
  (analogous to the existing external-mount dedup keyed on
  `Path.External.t`). No-op given today's `Paths.make`, but it's a
  one-line change that becomes useful as soon as the first option
  goes in.

### 4. Local-directory pins skipped

As noted in the architecture section, pinned local directories don't
get a pkg mount because `source_dir` isn't a directory target. The
existing `dune build -p` subprocess handles them.

If we want pkg-mount to fully subsume the subprocess for every
`(dune)` lockfile entry, we'd need to either declare `source_dir` as
a directory target even for local-directory sources (which conflicts
with the per-file copy rules) or point the mount at the pin's actual
on-disk source as an `External` path.

The second is cleaner and consistent: a pinned local directory IS an
external source, just like a workspace mount. The synthesiser would
emit `Mount_path.External <pin_source>` for these.

### 5. `backing.byte_provider` redundancy

`Source_resolver` now owns the read mechanism, but `backing` still
carries a separate `byte_provider : Path.Source.t -> string Memo.t`
and a `file_source : Path.Source.t ->
Dune_engine.Build_config.source_file`. Both are derivable from
`resolver`'s reads. Removing the redundancy is mechanical but
non-trivial because both fields have many call sites; deferred until
a cleanup pass.
