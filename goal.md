# Build locked Dune packages in one workspace

This is the design plan for the `flatten-dune` prototype and its next
builder-unification phase. The current prototype establishes target-backed
native source loading. The archive remains a behavioral reference, but its
source remapping is not retained: build-backed sources are first-class in the
rules-side `Source_tree` rather than masquerading as workspace `Path.Source.t`
values.

## Goal

Every selected lock package is represented by an exact package node in the
current Dune rule graph. Every package receives an immutable, rule-owned
prepared source directory target, which may be empty, and owns a separate
artifact subtree.

Source contents alone select one of two builders:

- if the prepared tree contains Dune files, `Dune` loads them through the
  rules-side `Source_tree` and generates native rules in the current process;
- if the prepared tree contains no Dune files, an internal synthetic `Opam`
  stanza runs the complete recorded recipe in a copy sandbox and owns an opaque
  install-layout directory target and cookie.

A package built by `Dune` does not launch a nested Dune process. Its projects
and stanzas compose with other loaded Dune projects like an ordinary monorepo;
it receives no opaque package rule or install cookie. An `Opam` builder may
invoke Dune, Make, shell scripts, or another opaque build system as part of its
recorded action. The install-layout target and cookie are specific to that Opam
boundary.

Workspace packages retain their existing behaviour.

## Native foundation milestone

The first working milestone contained only:

- one existing explicit source lock;
- one local archive containing one Dune package;
- one literal translated `dune build ...` action;
- one target-backed package source root whose real location is a `Path.Build.t`
  in an independent fetch namespace;
- one separate package artifact root beneath `_build/_default+lockfile/pkg/`;
- one workspace library consuming the native library;
- no virtual `Path.Source.t`, nested Dune process, or old `.pkg` rule for the
  native package, and no package-specific engine behaviour.

HTTP, VCS and live-directory sources, autolock, shared sources, nested projects,
Opam-built consumers, source refresh, and watch mode are outside this milestone.
They are added only after the core path works.

The next unification milestone adds one non-native package as an internal `Opam`
stanza. It depends on the same kind of prepared source target, receives a
writable copy only inside its sandbox, and produces a package-owned install
layout and cookie. It must not require a parallel source namespace or be chosen
by absence from a mounted-package list.

## Path and ownership invariants

Path kinds retain their existing meanings:

- `Path.Source.t` is watched, user-owned workspace input and may be promoted to;
- `Path.Build.t` is graph-produced data, is not watched as workspace input, and
  is never a promotion destination;
- `Path.External.t` is external input that may be watched but must not be
  modified by build rules or promotion.

A fetched package source is not a `Path.Source.t`. Its independently derived
fetch rule owns a build directory, and that directory and the files beneath it
remain build-backed sources. The source directory target is the real package
source root, not staging for another representation. Generated objects and
install entries live beneath `_build/_default+lockfile/pkg/`; they are never
placed beneath the source directory target.

The following are independent values:

| Concern | Representation |
|---|---|
| Lock package identity | Exact package identity in one lock universe |
| Project identity | Stable semantic identity, independent of physical paths |
| Source location | Workspace or build-backed package source |
| Relative project path | `Path.Local.t` |
| Artifact ownership | Explicit resolver and `Path.Build.t` output root |

No value is reconstructed from another. In particular:

- no package source is given a virtual workspace path;
- no output directory is derived from a source path and context name;
- no library object owner is recovered from its name and source path;
- no context-name suffix stands in for artifact ownership.

## Generalizing `Path.Source.t`

Existing rules-layer APIs use `Path.Source.t` because workspace input was
historically the only source kind. Those types are hypotheses, not compatibility
boundaries.

The distinction belongs in the rules-side `Source_tree`, not in every rule that
happens to receive a `Path.Build.t`. A generic build path is not necessarily a
package source, so rules must not dispatch on `Path.Build.t` or reconstruct
source ownership from paths. They receive a `Source_tree` directory or file and
ask it to perform source operations.

The private representation is conceptually:

```ocaml
type root =
  | Workspace of Path.Source.t
  | Build_backed of Path.Build.t

type dir =
  { root : root
  ; local : Path.Local.t
  }
```

The exact private types are not prescribed. The public rules-side API must make
these operations first class:

- enumerate a directory and build its source target when necessary;
- resolve a relative directory or file without changing its ownership;
- read a file while recording the appropriate workspace or build dependency;
- return a logical source location for parsing and diagnostics;
- distinguish workspace promotion from non-promotable build-backed input.

At each affected rules API:

1. If it reads bytes, enumerates topology, or records a source dependency, take
   a `Source_tree` directory or file rather than dispatching on a generic path.
2. If it needs only project-relative identity, take `Path.Local.t` and an
   explicit project identity instead of a physical source root.
3. If it places generated files, take the artifact `Path.Build.t` explicitly.
4. If it reports a location, use the real source-tree location without making it
   an artifact authority.
5. If it promotes, permit only a source-tree file backed by a genuine workspace
   `Path.Source.t`.

Build-backed package input remains a real `Path.Build.t` internally, but
consumers cannot silently apply workspace semantics to it or learn that an
arbitrary build path is a source merely from its path shape.

A loaded directory or project must carry, directly or through its owner:

```text
source location + relative directory + project identity + artifact output root
```

This is the boundary at which source and output paths become explicit.

## Engine and rules source views

The engine continues to receive the ordinary workspace `Source_tree`. It uses
that tree for workspace source-copy rules, fallback suppression, directory
loading, and cleanup. It receives no mount registry, package identity, or
build-backed source exception.

`Dune_load` and rule generation need a richer rules-side view containing:

- ordinary workspace directories; and
- package directories rooted at real `Path.Build.t` prepared-source targets.

The rules-side `Source_tree` privately distinguishes workspace and build-backed
roots and presents one directory/file API to rule generation. It is the sole
deciding point for whether an operation uses workspace filesystem APIs or
build-system APIs. Rules do not contain package-source branches and do not treat
all `Path.Build.t` values as sources. The engine's existing `Source_tree`
projection remains workspace-only and receives no build-backed pseudo-sources.

Build-backed source nodes are built, enumerated, and read through existing
build-system APIs. Their directory target and source-preparation rules are
derived from lock data alone, so loading a package `dune-project` cannot depend
on rules that themselves require that project to be loaded. Ordinary `(include)`
resolution also goes through the source-tree file API; `dynamic_include` remains
a normal build-graph operation.

```text
lock data
  -> independent prepared-source target rules
  -> package node with an explicit artifact owner
  -> choose Dune or Opam builder
  -> native monorepo rules or one opaque Opam rule
  -> bridge only Opam boundaries through install layouts and cookies
```

## Package preparation and builders

The lock remains a cache of repository metadata. It stores each selected
package's complete translated action, including wrappers, filters, environment
updates, configure steps, and mixed commands. It does not store a `dune_based`
marker, and a build does not consult the opam repository again.

Source transport and build selection are independent decisions. Preparation
returns one immutable node for each exact selected package:

```text
package node
  = lock universe + exact package identity
  + immutable prepared source directory target
  + complete recorded recipe
  + dependency capabilities
  + artifact owner
```

Fetch data may be shared by content identity, but package nodes and artifact
owners remain distinct across lock universes. Archive extraction, VCS checkout,
local-source preparation, lock-package `files/`, and extra-source overlays must
converge on the same prepared-source contract before the old source path is
removed. A source-less package receives an empty directory target rather than a
second source representation.

The prepared directory preserves existing overlay semantics: materialize the
primary source, overlay the lock package's `files/` tree, then place each
extra-source entry at its declared local path. Later layers replace colliding
entries. Every layer, destination path, and ordering decision participates in
rule dependencies and prepared-source identity so refresh and stale-file removal
remain correct.

Build selection is a property of that directory's contents:

```text
builder
  = Dune of loaded Dune files
  | Opam of complete recorded recipe
```

Enumerate the prepared tree through the rules-side `Source_tree`. If it contains
any Dune build files, load them normally and use `Dune`. If it contains no Dune
build files, use `Opam`. Do not inspect recipe shape, dependencies, depexts,
package declarations, install actions, or system-provider metadata to make this
decision. External tools remain resolver capabilities rather than builder
outcomes.

Once Dune files are found, parsing and loading errors are ordinary Dune errors;
they do not fall back to `Opam`. Native rule generation supersedes the complete
recorded recipe even if only an auxiliary Dune file caused native loading. The
later in/out work will refine which loaded projects are internal or externally
visible, not whether the source is loaded.

The `Opam` builder is an internal synthetic stanza, not initially user-facing
syntax. It participates in ordinary rule generation at the package's artifact
owner and owns one opaque package output subtree. Its rule:

1. depends on the immutable prepared source target and dependency capabilities;
2. copies the source into a writable copy sandbox;
3. expands and executes the complete recorded build and install actions;
4. produces a package-owned install-layout directory target; and
5. records installed files and package variables in the install cookie.

The existing package action expander, install action, cookie, and dependency
view are the starting implementation. They should be extracted from the
parallel `.pkg` routing path and hosted by this stanza rather than rewritten.
The prepared source target is never writable, and the stanza owns no target
beneath it.

Existing non-relocatable compiler packages redirect their prefix to a
`Path.Outside_build_dir` toolchain location. That behavior must be redesigned
before converting those packages: the Opam stanza must install into its owned
directory target and export any toolchain location through package capabilities.
There is no external-toolchain builder or exception to output ownership.

## Artifact ownership and dependency resolution

Every package node uses the workspace context's compiler, tools, resolver, and
host relationship, but owns artifacts beneath a separate package output root.
This is an alternate physical owner, not a second semantic workspace context.
Implicit workspace aliases and path targets do not run in it.

Libraries, objects, binaries, install entries, scopes, diagnostics, Merlin data,
and compile commands must use the explicit source and artifact owners. The first
milestone migrates only the consumers needed by its package and workspace
library; later milestones complete the same type migration rather than add
builder-specific conditionals.

A `Dune` builder generates ordinary fine-grained stanza rules. Loaded native
projects compose directly through normal Dune scopes, libraries, executables,
PPX rules, and dependencies. Do not wrap their outputs in a directory target or
synthesize an install cookie.

An `Opam` builder instead owns its full output directory target and produces an
install cookie as the trace of files and variables created by its opaque action.
Adapters are needed only when crossing this opaque boundary:

- native rules consume an Opam-built package through its installed artifacts and
  cookie;
- an Opam stanza consumes native rules through their ordinary install
  projection, binaries, and exported environment.

Dependency identity selects the exact package node without requesting a parallel
`.pkg` package rule or making native-to-native composition package-opaque.

## Source selection

With source and artifact roots separated, the rules layer owns one consistent
selection policy for each output path:

- a standard or promote-mode generated rule may replace the corresponding source
  input when ordinary Dune semantics say it does;
- an existing source suppresses a fallback target;
- selectors and module discovery observe the same selected input;
- promotion never writes to build-backed package sources.

Do not reintroduce engine source claims or source/output co-location to
implement this precedence.

## Deferred in/out boundary

Auxiliary nested projects in one prepared source may eventually be internal
inputs to the selected package without becoming packages visible to unrelated
consumers. That is the later in/out problem, not a prerequisite for the builder
unification.

The current design should avoid destroying the complete decoded project
universe. Keeping that representation may simplify source ownership, but no
nested-project visibility or masking semantics are decided or implemented before
the in/out work.

## End-to-end flow

```text
workspace source view
  -> read explicit lock
  -> retain complete translated actions
  -> create prepared source targets from lock data
  -> construct exact package nodes and artifact owners
  -> inspect source and select Dune or Opam builder
  -> load native projects or instantiate one synthetic Opam stanza
  -> compose native projects through ordinary Dune rules
  -> expose Opam boundaries through install, binary, and environment adapters
```

Logical package identity, physical source location, builder selection, and
artifact ownership remain separate throughout this flow.

## Behaviour retained from the archived prototype

Later milestones retain these proven decisions:

- runtime source inspection chooses the native `Dune` or opaque `Opam` builder;
- any Dune build file selects native loading, independently of lock metadata;
- the native builder supersedes the complete recorded recipe;
- native projects have vendored warning, alias, and promotion behaviour;
- masks are applied after complete project decoding;
- native packages strictly bypass the Opam stanza and its cookie;
- native projects compose directly, while Opam boundaries expose scoped install
  outputs and environments through adapters;
- lock generation uses a workspace-only source view;
- autolock may complete in one invocation through two explicit loading phases;
- source refresh, generated/fallback precedence, and watch invalidation are
  correctness requirements;
- package outputs remain isolated from workspace outputs.

## Mechanisms not to reuse

The new implementation must not contain:

- virtual `Path.Source.t` identities for fetched targets;
- virtual-to-real source lookup or `Source_tree.real_path` engine configuration;
- package-source exceptions in engine copying, lookup, selectors, fallback
  handling, cleanup, or promotion;
- co-located fetched sources and package artifacts;
- build-start synchronization into the artifact root;
- synthetic source-claim rules;
- a mutable process-global mount registry or registry-generation invalidation;
- reverse path-to-package or path-to-context lookups;
- rule-local dispatch that interprets a generic `Path.Build.t` as a package
  source;
- a second full workspace context;
- an external source-snapshot store, manifest, or provider callback layer;
- a parallel `.pkg` source/build subsystem selected by absence from native
  loading;
- executing an Opam action directly in an immutable prepared source target;
- compatibility shims around the archived prototype's internal APIs.

The archived implementation may be consulted for behaviour and tests, not used
as a scaffold.

## Implementation order

The current prototype has established the native foundation: independent fetch
targets, build-backed rules-side source loading, explicit artifact owners, and
native package consumption. Continue from that foundation in this order:

1. Introduce one exact package-node value containing source, recipe, dependency,
   resolver, and artifact ownership without choosing a builder by absence.
2. Produce one immutable prepared source directory target for every package and
   every currently supported transport; source-less packages receive an empty
   target.
3. Preserve the primary-source, lock `files/`, and extra-source overlay order in
   that target, with focused identity and invalidation tests.
4. Extract the existing package action expander, install action, install cookie,
   and dependency view behind an internal synthetic `Opam` stanza.
5. Make the stanza depend on the prepared source, run with a writable copy in a
   copy sandbox, and own one install-layout directory target and cookie.
6. Generate that stanza in the package artifact partition rather than the
   parallel `.pkg` package-rule namespace.
7. Select `Dune` when source enumeration finds any Dune build file and `Opam`
   only when it finds none. Propagate source and Dune-loading errors normally.
8. Add adapters at Opam boundaries for native install projections, Opam
   cookies, libraries, binaries, variables, environments, and host tools. Keep
   native-to-native composition on ordinary Dune rules.
9. Prove a native consumer of an Opam-built dependency and an Opam-built
   consumer of a native dependency, then port the complete A -> B -> C
   composition.
10. Redesign non-relocatable compiler/toolchain installs so their Opam stanza
    owns the complete output directory target.
11. Remove recipe-shape routing, mounted-list absence checks, and obsolete
    `.pkg` source/build ownership only after all existing source forms,
    builders, and toolchain cases have replacement coverage.
12. Add refresh, retry, stale-removal, and watch tests over prepared sources.
13. Preserve the complete decoded universe if useful, but defer all auxiliary
    nested-project visibility semantics to the later in/out work.
14. Re-run real package graphs and compare successful native and Opam-builder
    workloads before optimizing source materialization or scheduling.

No step adds an abstraction solely to preserve an API that incorrectly requires
`Path.Source.t`. Generalize that API or remove its physical-path dependency.

## Verification

The native milestone is complete only when the built Dune executable
demonstrates:

1. A local-archive package is loaded and built in the current process.
2. A workspace library compiles and links against the native package.
3. Native source topology and reads depend on the real fetch directory target
   through `Source_tree`.
4. Package artifacts exist only beneath the explicit package output root.
5. The native package has no old `.pkg` build directory, cookie, or action.
6. No nested/external Dune invocation occurs.
7. The engine has no package-source branch, fake source fact, or cleanup
   exception.
8. Existing workspace loading and build behaviour remain unchanged.
9. The source root and artifact root have distinct rule ownership.
10. The implementation contains no virtual source redirection, snapshot
    provider, or rule-local generic `Path.Build.t` source dispatch.

The builder-unification milestone additionally demonstrates:

1. Every package has an immutable prepared source directory target, possibly
   empty, and an Opam stanza consumes that target directly.
2. Prepared directories preserve primary, lock `files/`, and extra-source
   overlay semantics.
3. Its action receives a writable sandbox copy and cannot mutate the prepared
   target.
4. It owns exactly one package install-layout subtree and its install cookie.
5. Building the cookie or a file in the install layout works directly after a
   clean build.
6. Native and Opam-built packages consume one another through boundary adapters,
   while native projects compose through ordinary fine-grained Dune rules.
7. Builder selection depends only on whether the prepared tree contains Dune
   build files; loading errors and system-provider metadata never select or
   bypass a builder.
8. No package depends on absence from a mounted list to receive rules.
9. Non-relocatable toolchain installation is redesigned to remain entirely
   within stanza-owned output.

Use `_build/default/bin/main.exe` for the end-to-end scenarios. Trace assertions
must use a fresh action cache when checking process execution.

After those milestones, carry forward focused cases for source transports and
builder selection, generated/fallback precedence, vendored behaviour, masking,
Opam/native interoperability, autolock, refresh and watch invalidation,
symlinks, promotion suppression, and a real opam-repository package graph.

## Review evidence

The implementation review should show:

- the source-location and loaded-directory boundaries;
- the rule-generation dependency path from lock data to source targets;
- explicit source, builder, and artifact ownership at changed call sites;
- the Opam stanza's source dependencies, sandbox, directory target, and cookie;
- the end-to-end trace and artifact layout;
- any remaining `Path.Source.t` assumptions and why they are workspace-only.
