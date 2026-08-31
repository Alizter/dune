# Build locked Dune packages in one workspace

This is the design plan for the `flatten-dune` prototype and its remaining
builder-unification work. The current implementation establishes target-backed
native source loading and synthetic Opam builds in the same rule graph. The
archive remains a behavioral reference, but its source remapping is not
retained: build-backed sources are first-class in the rules-side `Source_tree`
rather than masquerading as workspace `Path.Source.t` values.

## Goal

Every selected lock package is represented by an exact package node in the
current Dune rule graph and owns a separate artifact subtree. A source-backed
package has an immutable, rule-owned primary-source directory target. Absence
of a primary source is represented explicitly and does not create an empty
fetch target.

Primary-source contents select one of two builders:

- if the source tree contains Dune files, `Dune` loads them through the
  rules-side `Source_tree` and generates native rules in the current process;
- if the source tree contains no Dune files, a synthetic `opam` stanza runs the
  complete recorded recipe in a copy sandbox and owns an opaque install-layout
  directory target and cookie;
- if there is no primary source, the package selects `Opam` directly and starts
  with an empty sandbox working directory.

A package built by `Dune` does not launch a nested Dune process. Its projects
and stanzas compose with other loaded Dune projects like an ordinary monorepo;
it receives no opaque package rule or install cookie. An `Opam` builder may
invoke Dune, Make, shell scripts, or another opaque build system as part of its
recorded action. The install-layout target and cookie are specific to that Opam
boundary.

An unreleased user-facing `opam` stanza exercises the same rule primitive as a
synthetic lock package. Explicit package scopes over one canonical native decode
remain planned work; the future `scope` stanza will also remain behind the
unreleased language extension.

Workspace packages retain their existing behaviour.

## Implemented milestones

The current implementation provides:

- target-backed package source roots whose real locations are `Path.Build.t`
  values in the independent fetch namespace;
- rules-side loading of native package projects without virtual
  `Path.Source.t` values or nested Dune processes;
- separate package artifact roots beneath `_build/_default+lockfile/pkg/`;
- source-content classification: any Dune file selects native loading, while a
  source tree without Dune files selects a synthetic Opam stanza;
- explicit `No_source` classification, with no fake fetch target or loaded
  source project;
- copy-sandbox Opam builds that overlay lock `files/` and ordered extra sources
  without mutating the primary source;
- package-owned Opam install layouts and cookies in the alternate package
  context;
- native consumers of synthetic Opam outputs and dynamically discovered
  libraries, binaries, variables, installed files, and environments;
- unreleased user-authored `opam` stanzas using the same build primitive;
- clean `ocaml-re` and `ocaml-cohttp` builds through the current graph.

Normal selected packages no longer request `.pkg` outputs, but explicit legacy
`.pkg` rule generation remains temporarily available. `.dev-tool` routing is
unchanged. Native packages currently consume raw primary sources: patches,
substitutions, lock `files/`, and extra-source transformations for native builds
remain a separate design problem.

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
- package directories rooted at real `Path.Build.t` primary-source targets.

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
  -> independent primary-source target rules when a source exists
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
  = lock identity + exact package identity
  + optional immutable primary-source directory target
  + complete recorded recipe
  + exact selected package dependencies
  + artifact owner
```

Fetch data may be shared by content identity, but package nodes and artifact
owners remain distinct across lock identities. Multiple exact package nodes may
therefore reference one primary-source target without sharing recipes,
loaded-project identities, dependencies, outputs, or cookies. Archive
extraction, VCS checkout, and local-directory acquisition converge on the same
immutable primary-source contract. A source-less package has no primary-source
target.

For an Opam build, the copy sandbox is assembled in this order: primary source,
lock `files/`, then ordered extra sources. Later layers replace colliding
entries. A source-less package starts from an empty sandbox before applying the
same overlays. Native-selected packages currently read the raw immutable
primary source; a separate raw-source to transformed-source phase is required
before native builds can honor patches, substitutions, lock `files/`, or extra
sources.

Build selection is a property of that directory's contents:

```text
builder
  = Dune of loaded Dune files
  | Opam of complete recorded recipe
```

Enumerate a primary source through the rules-side `Source_tree`. If it contains
any Dune build files, load them normally and use `Dune`. If it contains no Dune
build files, use `Opam`; absence of a primary source also selects `Opam`
directly. Do not inspect recipe shape, dependencies, depexts, package
declarations, install actions, or system-provider metadata to make this
decision. External tools remain resolver capabilities rather than builder
outcomes.

Once Dune files are found, parsing and loading errors are ordinary Dune errors;
they do not fall back to `Opam`. Native rule generation supersedes the complete
recorded recipe even if only an auxiliary Dune file caused native loading. The
later in/out work will refine which loaded projects are internal or externally
visible, not whether the source is loaded.

The package-builder layer turns either choice into ordinary loaded-project input
for rule generation:

```text
Dune files present -> loaded source universe with exact artifact ownership
Source, no Dune    -> one synthetic loaded project and Opam stanza per package
No source          -> synthetic Opam rules without a loaded source project
```

Generic workspace `Dune_load` remains unaware of locks and Opam recipes. Native
sources are loaded as ordinary projects under explicit artifact ownership;
canonical package scopes remain planned work. A source-backed Opam package gets
a synthetic project after source enumeration and passes through ordinary stanza
traversal and `Gen_rules`. A source-less package dispatches the same synthetic
Opam rule directly because it has no source project to load.

`opam` is a real Dune stanza type. Lock-package loading synthesizes its internal
value, while users may write the stanza in a Dune file only with the unreleased
language extension enabled:

```lisp
(using unreleased 0.1)
```

The decoder and fields are explicitly unstable. This gives focused tests and
experiments direct access to the rule primitive without requiring a lock or
promising a released feature. Decoded and synthesized stanzas must share one
representation and rule generator.

The stanza participates in ordinary rule generation at the package's artifact
owner and owns one opaque package output subtree. Its rule:

1. depends on its optional immutable primary source and exact package
   dependencies;
2. initializes a writable copy sandbox from that source, or from an empty
   directory when there is no source;
3. expands and executes the complete recorded build and install actions;
4. produces a package-owned install-layout directory target; and
5. records installed files and package variables in the install cookie.

The first shared implementation mechanically moved the legacy recursive package
graph, dependency view, mutable exported environments, digest paths, and
`Package_universe` into `Opam_package_rules`. That is migration debt, not the
intended stanza interface. Before deleting `.pkg`, replace it with the existing
package model: use `Package.depends` for edges, `Package_db` for lookup, and one
shared package-dependency materializer behind `(deps (package ...))`. The
materialized action-builder result supplies the environment, binaries, package
variables, concrete paths, and build dependencies needed by the Opam action.
`Opam_stanza.t` remains the recipe. The user-facing decoder is guarded by
`Dune_lang.Unreleased`, and synthetic lock packages construct the same value.

## Experimental scope stanza and package masks

Package masking should use a second real stanza, `scope`, also guarded by
`(using unreleased 0.1)`. Users can exercise masking directly, while the package
builder synthesizes the same scope value for each exact native package view.
Decoded and synthetic scopes must share one representation and evaluator.

A scope is applied to the complete decoded source universe. It selects which
package-associated stanzas belong to that view without changing source identity,
builder selection, or artifact ownership. Several exact package nodes may
therefore reuse one parsed source universe under independent scopes and output
roots. Do not destructively replace the canonical project's package map.

This should simplify source mounting: build and decode each primary source
once, then construct cheap package scopes over that canonical result. Package
views no longer require remounting the source or cloning filtered
`Dune_project.t` values. They also do not recover the selected package from a
mounted-list lookup.

PR #13337 is useful prior art for a `(scope ...)` stanza, but is not the
required API. In particular, this plan does not yet adopt its `dir` grammar,
ancestor precedence, duplicate-stanza union rules, or library-only filtering.
A package mask must eventually apply coherently to every package-associated
stanza class; auxiliary-project in/out semantics remain deferred.

Like `opam`, `scope` has no released compatibility promise. Synthetic package
loading constructs its value directly rather than manufacturing or rewriting a
Dune file.

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
Its inputs are the exact package dependencies declared by the owning
`Package.t`. Synthetic lock packages construct that package value from the
platform-selected lock edges; user-authored stanzas use the existing
`(package ... (depends ...))` declaration.

Package-dependency resolution looks names up in `Package_db` and materializes
the selected set through the same operation used by `(deps (package ...))`. Its
`Action_builder` result records native install-layout and Opam target or cookie
dependencies and returns the environment, binaries, variables, and concrete
paths needed by action expansion. Ordinary rule dependencies retain their
immediate-only semantics; an Opam build asks for the owning package's transitive
closure to preserve Opam environment semantics. No recursive package value is
stored in `Opam_package_rules`.

Native rules consuming an Opam-built package cross the inverse boundary through
that dependency's installed artifacts and cookie. Native-to-native composition
remains direct and fine-grained. Dependency identity never requests a parallel
`.pkg` package rule.

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

The experimental scope establishes an explicit package mask now because that
simplifies package views and testing. Auxiliary nested projects may eventually
be internal inputs to the selected package without becoming packages visible to
unrelated consumers. That broader visibility policy remains the later in/out
problem.

Keep the complete decoded project universe independent of every scope. Do not
use the first package-mask implementation to decide nested-project visibility,
ancestor composition, or other in/out semantics prematurely.

## End-to-end flow

```text
workspace source view
  -> read explicit lock
  -> retain complete translated actions
  -> create optional primary-source targets from lock data
  -> construct exact package nodes and artifact owners
  -> inspect source and select Dune or Opam builder
  -> load native projects under synthetic scopes or instantiate an Opam stanza
  -> compose native projects through ordinary Dune rules inside each scope
  -> resolve Opam stanza inputs through exact package-dependency edges
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
- native projects compose directly, while each Opam stanza receives its selected
  package dependencies and derives installed paths and environments from them;
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
- lock-package or Opam-recipe branches in generic workspace `Dune_load`;
- an unguarded or released compatibility promise for the experimental `opam` or
  `scope` stanza;
- destructive per-package filtering of the canonical decoded source project;
- executing an Opam action directly in an immutable primary-source target;
- compatibility shims around the archived prototype's internal APIs.

The archived implementation may be consulted for behaviour and tests, not used
as a scaffold.

## Current TODO

The native and synthetic Opam vertical paths, including explicit source-less
packages, are implemented. `ocaml-re` and `ocaml-cohttp` are clean. Continue in
this order:

1. Replace the mechanically extracted package runtime in
   `Opam_package_rules` before removing `.pkg`:
   - keep `Opam_stanza.t` as the recipe;
   - remove its duplicate dependency list and use `Package.depends`;
   - look dependencies up by name through `Package_db` rather than constructing
     a recursive `Pkg.t` graph;
   - extract the package-set materializer behind `(deps (package ...))` so its
     `Action_builder` result records build dependencies and returns the action
     environment, binaries, package variables, and concrete paths;
   - preserve immediate-only semantics for ordinary rule dependencies, while
     materializing the transitive package closure for an Opam build;
   - remove `Dependency_view`, mutable exported-environment refresh,
     `Package_universe`, and the fake digest used by user-authored Opam stanzas.
2. Adapt the temporary legacy `.pkg` and `.dev-tool` callers to that concrete
   package-dependency result. Keep `.dev-tool` routing and ownership unchanged.
3. Remove normal `Package_universe.Dependencies` `.pkg` rule generation and
   migrate package tests to the alternate package targets.
4. Design a separate raw-source to transformed-source phase before applying
   patches, substitutions, lock `files/`, or extra sources to native packages.
5. Define the unreleased `scope` stanza and replace per-package filtered project
   copies with views over one canonical decode.
6. Add the remaining VCS, refresh, retry, stale-removal, watch, cross-lock, and
   promotion coverage.
7. Re-run the real package graphs and compare successful clean and warm
   workloads after each architectural cutover.

Do not replace the recursive package graph with another graph-shaped type or
rename `Package_universe` into another owner sum. Package identity remains in
the package database; the Opam rule consumes only one recipe and a concrete
materialized dependency set.

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

1. Every source-backed package has an immutable primary-source directory target;
   a source-less package has no fabricated source target.
2. Opam sandboxes preserve primary, lock `files/`, and ordered extra-source
   overlay semantics without mutating the primary source.
3. A user-authored `scope` stanza is rejected without
   `(using unreleased 0.1)` and uses the same representation and evaluator as a
   synthetic package scope.
4. Two exact native package nodes can share one decoded source universe while
   retaining independent package masks, artifact owners, and rule views.
5. Package masks apply consistently to package-associated stanza classes and do
   not affect Dune-versus-Opam selection.
6. An Opam action receives a writable sandbox copy and cannot mutate its
   primary source; a source-less action starts from an empty sandbox directory.
7. It owns exactly one package install-layout subtree and its install cookie.
8. Each source-backed Opam package has its own synthetic loaded project, recipe,
   artifact root, and cookie even when its source target is shared. A
   source-less package owns the same Opam result without a loaded source project.
9. A user-authored `opam` stanza is rejected without
   `(using unreleased 0.1)` and exercises the same representation and rule
   generator when enabled.
10. Building the cookie or a file in the install layout works directly after a
    clean build.
11. The Opam stanza sees its exact package dependencies, whose builder-owned
    outputs supply its environment, binaries, variables, and installed paths.
12. Native and Opam-built packages consume one another across that package edge,
    while native projects compose through ordinary fine-grained Dune rules.
13. Builder selection depends only on primary-source contents, with explicit
    no-source selecting Opam; loading errors and system-provider metadata never
    select or bypass a builder.
14. No package depends on absence from a mounted list to receive rules.

Use `_build/default/bin/main.exe` for the end-to-end scenarios. Trace assertions
must use a fresh action cache when checking process execution. The current
implementation has completed clean external builds of both `ocaml-re` and
`ocaml-cohttp`.

After those milestones, carry forward focused cases for source transports and
builder selection, generated/fallback precedence, vendored behaviour, masking,
Opam/native interoperability, autolock, refresh and watch invalidation,
symlinks, promotion suppression, and a real opam-repository package graph.

## Review evidence

The implementation review should show:

- the source-location and loaded-directory boundaries;
- the rule-generation dependency path from lock data to source targets;
- explicit source, package-scope, builder, and artifact ownership at changed
  call sites;
- proof that decoded and synthetic scopes share one evaluator over a canonical
  loaded source universe;
- the Opam stanza's source dependencies, sandbox, directory target, and cookie;
- the end-to-end trace and artifact layout;
- any remaining `Path.Source.t` assumptions and why they are workspace-only.
