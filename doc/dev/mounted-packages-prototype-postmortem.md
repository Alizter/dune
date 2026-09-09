# Final retrospective: building locked Dune packages in one process

- Status: prototype complete; production design still required
- Final implementation reviewed: `283eeae6bb78`
- Historical design record: [`goal.md`](../../goal.md)
- Historical archive:
  `prototype/flatten-dune-archive-2026-08-24T1337Z`

This document compares the completed prototype with its original plan. It
records which ideas survived contact with real package graphs, which ones were
changed, and which mechanisms were deliberately avoided or removed.

The prototype is evidence that the product direction works. It is not a claim
that this 286-file implementation should be merged as one production change.
Its value is the set of validated invariants, reduced regressions, performance
measurements, and rejected designs that a smaller implementation can start
from.

## Executive conclusion

The core thesis worked: Dune can load selected lock-package projects and
produce their rules in the current process. Native packages do not need a
nested Dune invocation, an opaque package build, or a digest-addressed `.pkg`
root. Native and opaque packages can coexist in one dependency graph, and
locked packages can also depend on live workspace packages.

The final normal package address is:

```text
_build/<context>/.lockfile/pkg/<package-name>
```

That path is both the logical source hierarchy seen by native rule generation
and the artifact hierarchy for the package. Authored bytes remain backed by
immutable `_build/_fetch` targets. Fine-grained source rules materialize only
the selected files into the package hierarchy. No source directory target owns
the package root, so generated rules can own neighboring targets normally.

This differs from the original plan, which proposed one immutable prepared
source directory target separate from the artifact root. The useful part of
that separation survived as a **logical/backing** distinction. The extra
physical source-tree representation did not.

The resulting flow is:

```text
selected lock package, keyed by name
  -> immutable acquisition under _build/_fetch
  -> ordered logical source layers at pkg/<name>
  -> statically extractable patches and substitutions
  -> classify the resulting source view
     -> selected package represented: native fine-grained Dune rules
     -> otherwise: opaque Opam rule and owned install-layout target
```

The most important result is not any individual path layout. It is that all of
the following held together on realistic graphs:

- build-backed source loading;
- ordinary fine-grained native rules;
- opaque Opam boundaries;
- package-local artifact ownership;
- direct capability visibility and transitive build ordering;
- private-library and install metadata;
- PPXs, binaries, generated files, includes, globs, and source traversal;
- mixed workspace and lock-package edges; and
- null-build performance within a usable range.

## Final invariants

The prototype ended with the following invariants.

### One normal package root

A selected normal package has exactly one stable root:

```text
_build/<context>/.lockfile/pkg/<name>
```

The selected lock universe guarantees one package per name. Version remains
metadata. A source checksum identifies acquisition data under `_build/_fetch`;
it is not part of the package's normal build address.

Normal project builds no longer route through `.pkg/<digest>`. The recursive
legacy package runtime remains only for `.dev-tool`, where it is a separate
compatibility concern.

### Logical source, immutable backing

Mounted files carry a canonical logical path under `pkg/<name>` and one or more
immutable backing layers. The layer model has four operations:

```text
Directory   map a backing hierarchy into the logical hierarchy
File        map one backing file to one logical path
Contents    own transformed bytes at one logical path
Delete      hide a logical path and its descendants
```

Primary source, lock `files/`, and ordered extra sources are represented by the
first two forms. Only `Contents` and `Delete` represent transformed bytes and
deletions. Later layers win.

Rules load, enumerate, and diagnose the logical hierarchy. Reads depend on the
actual backing input. Materialization uses per-file copy or write rules and
preserves executable permission. There is no prepared root, shadow tree,
manifest, snapshot, source provider, or whole-source directory target beneath
the package root.

### Fine-grained native rules and an opaque fallback

A package is native only when the transformed source view contains Dune files
and its decoded projects define the selected package. Incidental Dune files in
an otherwise opaque source do not make an unrelated selected package native.

Static source transformations are extracted conservatively. Literal patches,
substitutions, and statically decidable conditions extend the source layers.
When a source-affecting operation needs build-time package data or unsupported
action structure, the package remains opaque. It is not partially transformed
and then loaded natively.

An opaque package remains a data-only boundary. Its source does not enter
`Dune_load`; one Opam rule owns its install-layout directory target and cookie.
It may invoke Dune or another build system internally. Native packages receive
neither that wrapper nor that cookie.

### Canonical package graph

`Package.t`, `Package.depends`, and `Package_db` are authoritative. The Opam
stanza consumes a concrete `Package_deps.t` materialization rather than storing
a second recursive package graph.

Capabilities such as binaries, package variables, and exported environments
are visible through direct declared dependencies. Build ordering and installed
library resolution can use the required transitive closure. Virtual packages
and the selected compiler use explicit forwarding rather than accidental
global visibility.

Auxiliary libraries remain private to their owning mounted package. Only the
selected package and the private closure needed to implement it are exported.

### Workspace and lock packages can alternate

The prototype supports both directions across the workspace boundary. For
example, this graph builds:

```text
locked consumer -> workspace library -> locked base
```

Generated mixed lockdirs retain repository-to-workspace names without creating
fake `.pkg` files or `pkg/<name>` roots for workspace packages. Workspace path
and binary entries take precedence where the locked consumer directly depends
on the workspace package.

This implementation is deliberately live-workspace and name-bound. It does not
yet record a workspace version or solver-metadata fingerprint in the lockdir.
That limitation is production debt, not a reason to add fake lock-package
nodes for workspace packages.

## Outcome of the original plan

### Kept

- Build selected Dune packages in the current process. This is the central
  successful result.
- Keep `Path.Source.t` for real workspace input only. Build-backed input belongs
  behind a rules-side source API.
- Keep the engine package-agnostic. Generic source selection and dependency
  operations were sufficient.
- Use a separate rules-side source-tree view. It became the main ownership
  boundary for logical and backing files.
- Fall back to an opaque Opam boundary for non-Dune and source-less packages.
- Expose one Opam stanza primitive. Synthetic and unreleased authored stanzas
  share the same rule path.
- Use canonical `Package.depends` and `Package_db`. This removed the normal
  recursive legacy package graph.
- Add package scopes over canonical decoded projects. They preserve owner-local
  auxiliary code while providing selected-package views.
- Remove normal `.pkg` routing. Only `.dev-tool` retains the legacy recursive
  route.

### Changed or refined

- Separate physical source and artifact roots became immutable `_fetch` backing
  plus one fine-grained logical package hierarchy.
- Exact or digest-addressed output identity became package-name identity inside
  one selected lock universe. Version and digest are metadata.
- "Any Dune file means native" became "a Dune project represents the selected
  package".
- A second transformed source root became direct `Contents` and `Delete` layers
  for static transformations, with opaque fallback for unsupported cases.
- Preserving workspace behavior expanded into supporting locked-to-workspace
  edges and generated mixed lockdirs.

### Avoided or narrowed

- A whole prepared directory target was avoided because it conflicts with
  fine-grained generated ownership and adds another source representation.
- The broad auxiliary-project in/out design was narrowed to the owner-private
  closure required for correctness.

## Branch feature inventory

This section inventories behavior present in the final branch. Some items are
user-visible package behavior, while others are enabling rules infrastructure
or prototype-only interfaces. The smaller fixes are listed separately below so
they are not lost inside the main architectural story.

### Mapping to the in-and-out issue

The latest prototype checklist in issue #8652 named seven pieces. Their status
on this branch is:

1. **Load sources directly in an adjacent context: implemented, then simplified.**
   Native package projects now use a build-only `.lockfile` subtree in the
   owning workspace context, without a synthetic engine context.
2. **Add an Opam stanza: implemented.** The unreleased stanza and synthetic
   lock-package form use the same rule generator.
3. **Add a scope stanza: implemented.** The unreleased package-selection stanza
   is also used to construct mounted package views.
4. **Move legacy package rules to the Opam stanza: implemented for normal
   selected packages.** The old recursive implementation remains only for
   `.dev-tool`.
5. **Load Dune packages directly and apply scopes: implemented.** Selected
   package projects generate normal fine-grained rules and retain only their
   owner-local auxiliary closure.
6. **Allow lockdirs to express in-and-out edges: implemented as a prototype.**
   Both hand-written/current lockdirs and solver-generated
   repository-to-workspace edges can be consumed. The persisted workspace
   boundary and complete mixed cycle validation remain production work.
7. **Remove package toolchains: not implemented.** The prototype demonstrated
   direct loading of compiler packages, but the existing package-toolchain
   machinery was not removed and should not be counted as a branch feature.

The branch also implements several prerequisites from the older #8652
checklist: package-scoped binary lookup, package-scoped `PATH`, narrowed
`resolve_program`, dependency-specific workspace install layouts, and
transitive locked/workspace ordering.

### Source and native-loading features

- A `Source_path` representation distinguishes real workspace input from
  build-backed package input without turning fetched files into
  `Path.Source.t` values.
- `Source_tree.Rules` provides dependency-recording directory traversal, file
  reads, includes, diagnostics, and materialization for both source kinds.
- `Loaded_project`, `Loaded_dir`, and `Build_partition` separate project
  identity, relative source location, resolver context, and artifact owner.
- Lock packages use a build-only `.lockfile` subtree in their owning context.
  Their `Build_partition` purpose still distinguishes them from workspace
  projects without creating another engine or semantic context.
- Normal package roots are stable and package-name-only:
  `_build/<context>/.lockfile/pkg/<name>`.
- Primary archives and extra sources remain immutable, reusable `_fetch`
  targets.
- Logical package trees combine primary source, lock `files/`, and ordered
  extra-source layers.
- Native patches and substitutions are evaluated as exact content and deletion
  layers when their inputs and conditions are statically available.
- Unsupported build-dependent transformations conservatively select the opaque
  builder.
- Native classification uses the transformed source view and verifies that an
  enabled decoded project defines the selected package.
- Native rules replace the complete recorded Opam recipe; no nested Dune builds
  a native package.
- Authored package files are materialized by individual copy or write rules,
  including executable permission and exact backing dependencies.
- Source/generated/fallback precedence is shared with normal rule selection.
- Mounted promotion is contained in the build hierarchy and cannot modify
  immutable backing input.
- Exact package artifact paths can be requested directly without first building
  a workspace alias.
- Local archive and HTTP acquisition, one-invocation autolock, and lock-change
  watch invalidation are exercised by mounted-package tests.
- Shared archives and nested projects can be decoded once and used by separately
  owned package views.
- Mounted projects retain vendored warning and recursive-alias behavior rather
  than behaving like another workspace root.

### Opaque package and Opam-stanza features

- An unreleased `(opam ...)` stanza exposes the opaque package rule primitive
  for focused tests without making a stable language promise.
- The stanza carries build and install actions, depexts, exported environment
  updates, and one canonical `Package.t` owner.
- Opam actions execute in a writable copy sandbox and cannot mutate their source
  input.
- Source-backed opaque packages apply primary source, lock `files/`, and ordered
  extra-source overlays in the package sandbox.
- Source-less packages start from an empty working directory and do not receive
  a fabricated fetch target or loaded project.
- Generated `.install` and `.config` files are interpreted by the shared package
  implementation.
- Each opaque package owns one install-layout directory target and an install
  cookie recording installed files and package variables.
- Libraries and binaries discovered from the cookie become providers without
  needing duplicate declarations in the stanza.
- Synthetic lock packages and user-authored Opam stanzas use the same rule and
  dependency-materialization path.
- Opaque sources stay out of ordinary mounted `Dune_load`, including packages
  that merely contain an incidental unrelated Dune project.

### Scope and package in/out features

- An unreleased `(scope (packages ...))` stanza selects package-owned interfaces
  for its logical directory and intentionally has no `dir` field.
- Scope placement follows ordinary Dune files, static includes, and `(subdir
  ...)` placement.
- Nested scopes intersect; a child cannot re-enable a package excluded by an
  ancestor.
- Scope filtering runs before duplicate-package detection and before
  `--only-packages` selection.
- Scopes do not override a package's `enabled_if` result.
- Duplicate package names in one scope, duplicate scope stanzas in one logical
  directory, and names not defined beneath the scope are diagnosed.
- Package ownership is applied to libraries, executables, deprecated library
  names, Cram stanzas, MDX stanzas, and generated package metadata.
- Package-owned interfaces are filtered while unowned private implementation
  stanzas remain available.
- Mounted synthetic scopes intersect with source-authored scopes rather than
  replacing them.
- Multiple selected packages from one source retain independent artifact
  owners.
- Auxiliary libraries needed to implement a selected package remain visible
  inside that owner but are not exported globally.
- Private auxiliary archives and metadata required by public libraries are
  included in the owner's install metadata closure.

### Dependency and capability features

- `Package.depends` and `Package_db` form the canonical package graph for both
  native and opaque normal packages.
- `Package_deps` materializes concrete paths, environments, binaries, package
  variables, install roots, and build dependencies from that graph.
- The user-authored Opam path no longer constructs a recursive package runtime.
- Normal project dependencies no longer use the legacy package database as a
  fallback.
- Immediate package edges control capability visibility. Undeclared siblings
  and transitive package binaries, variables, and exported environments remain
  hidden.
- The required transitive closure still supplies build ordering and installed
  library metadata.
- Virtual/system packages forward the concrete provider capabilities they are
  intended to expose.
- Findlib library lookup can resolve the actual `META` or `dune-package`
  provider when its lock package name differs from the requested library name.
- Workspace and lockdir binaries are both narrowed to the owning package's
  declared dependency plan.
- `%{bin:...}`, `%{bin-available:...}`, and
  `Super_context.resolve_program` use the narrowed artifacts.
- Tools invoked later by bare name receive the same package-scoped binary
  precedence through `PATH`.
- Environment-defined binaries without a package owner retain their existing
  ambient behavior.
- Workspace binaries shadow lockdir binaries when the workspace dependency is
  the selected direct provider.
- Ambient `PATH` remains the fallback when no declared package supplies a
  program.
- Path-like exported environments are retained as lists until final
  serialization, preserving precedence without repeated splitting and joining.

### Dune rule-family coverage

The source and ownership migration supports these rule families in mounted
projects:

- public, private, wrapped, unwrapped, virtual, and implementation libraries;
- deprecated and built-in library redirects;
- ordinary executables, public executables, local `env` binaries, and staged
  `.binaries` directories;
- PPX libraries, PPX drivers, replacement drivers, and mounted/workspace PPX
  consumers;
- `include_subdirs` groups;
- static include stanzas, generated dynamic includes, and OCaml-syntax Dune
  files;
- `copy_files`, source globs, and recursive `(source_tree ...)` dependencies;
- ordinary rules, generated files, fallback rules, aliases, and contained
  promotion;
- Cram, MDX, Cinaps, odoc, and OCaml index/Merlin integration;
- foreign rules and configurator metadata;
- JavaScript and Melange library lookup;
- Rocq source and scope handling;
- install stanzas, sites, section-relative paths, `META`, `dune-package`, and
  relocation metadata; and
- external `ocamlfind` and Opam/Topkg-style consumers of installed layouts.

Not every family has an equally small standalone regression, but all required
ownership paths were exercised while building the external package graphs.

### Mixed workspace and lockdir features

- A locked package can compile and link against a directly declared workspace
  library.
- It can run a public executable installed by a workspace package.
- It can depend on multiple workspace packages or an `allow_empty` workspace
  package.
- Alternating graphs such as locked -> workspace -> locked retain correct build
  ordering.
- Workspace install layouts, binaries, and exported paths are materialized for
  the locked consumer without exposing the complete workspace install tree.
- Direct workspace capabilities take precedence over equivalent lockdir paths.
- Lock generation no longer rejects repository packages solely because they
  select a workspace package.
- Generated mixed lockdirs retain those dependency names without serializing
  fake workspace package files.
- The project build path has a dedicated unchecked structural loader so it can
  apply active-workspace validation, while generic on-disk lockdir validation
  remains closed-world and strict.
- Workspace source edits do not require relocking under the current live model.
  A future solver-metadata boundary is needed before that behavior is a complete
  product contract.

### Install and metadata features

- Native packages generate ordinary fine-grained install entries rather than an
  opaque package cookie.
- Installed metadata preserves selected lock versions.
- Private-library archives needed by an exported public library are retained
  without globally exporting the private library.
- Install entries are indexed and evaluated by loaded owner and package,
  avoiding cross-package ownership and metadata cycles.
- Mounted packages retain `META`, `dune-package`, relocation, site, and
  `Install_layout` information needed by internal and external consumers.
- Mounted packages do not acquire workspace install aliases or ownership merely
  because their metadata participates in an install layout.
- Opaque packages keep their existing cookie-backed directory target boundary.

### Incrementality, tracing, and performance features

- Mounted loading and sandbox dependency materialization have dedicated trace
  events.
- Mounted discovery is memoized once per context rather than reevaluating one
  supplied memo computation for each lookup.
- Package digest lookup retains name/digest indexes instead of rebuilding full
  closure tables repeatedly.
- Concatenated `PATH` construction is linear.
- Package environments retain list-valued path entries and serialize them once.
- Native layout roots are added once per environment rather than once per
  dependency traversal.
- Selected lock-package paths are memoized.
- Opaque package materialization and opaque binary maps are shared.
- Mounted scope databases are reused.
- Mounted library and install stanzas are indexed by artifact owner.
- Rich tracing no longer creates runtime-event files in the source tree or
  forces `_build/.db` to be rewritten on a cache-stable null build.

## Smaller correctness fixes found along the way

These fixes are worth tracking independently from the mounted-package feature.
Some are generally useful; others close subtle mounted ownership holes.

### Source loading and rule selection

- **Includes use the owning source tree** (`a303763b2f5e`). Static and dynamic
  includes no longer assume that every included Dune file is workspace-backed.
- **Parent-relative workspace globs remain workspace-relative**
  (`1a52443f894e`). Adding mounted source directories initially changed ordinary
  `../stuff/*.txt` behavior; workspace expanders now retain their existing
  source-tree lookup.
- **Mounted `copy_files` enumerates authored logical inputs directly**
  (`48608fc3bd8a`). This avoids recursive parent rule generation without
  changing ordinary `copy_files` semantics for generated files.
- **Recursive mounted `source_tree` dependencies materialize their files**
  (`7edd32c9fecf`). Depending on topology alone was insufficient for sandboxed
  actions that read descendants.
- **Built-in library redirects retain mounted artifact targets**
  (`a5563dc4644e`). Redirect resolution no longer falls back to a path that
  loses the selected package owner.
- **Opaque Opam sources are not loaded as native projects** (`52d79e195edd`). An
  incidental Dune file can no longer leak unrelated project stanzas into the
  workspace graph.
- **Compile-command generation is workspace-root-only** (`249d901f047a`).
  Mounted roots also have an empty component list, so that list alone cannot
  identify the workspace root. The explicit mounted guard removed the
  `re/private_re` directory-content cycle.

### Library, PPX, and executable ownership

- **Mounted-to-legacy lookup preserves the consumer's resolver boundary**
  (`3806f6f17a73`). Library lookup no longer sees unrelated package branches.
- **Legacy libraries are resolved by their actual metadata provider**
  (`866388ff6f7a`). This covers virtual packages such as `base-bytes`, where the
  package name and findlib provider differ.
- **Mounted PPX drivers stay in the package partition** (`47ddbe4502b7`) and are
  subsequently **owned by the mounted consumer** (`713ca3062362`). This prevents
  driver artifacts and dependency sets from leaking into the workspace
  partition.
- **Mounted `include_subdirs` groups use mounted directory status**
  (`d928de5dc92a`) instead of reconstructing workspace directories.
- **Staged binaries use the directory's narrowed artifacts** (`e9f2edddf2c5`).
  `%{bin:x}` and a bare `x` invoked through the staged `.binaries` directory now
  select the same executable.
- **Mounted automatic `.bin` directories receive their symlink rules**
  (`a0fc402789ac`). Build-backed source directories were previously omitted from
  automatic local-binary subdirectory generation.
- **Context-wide C compiler probing stays on the base path** (`cd9a837104e1`).
  Package binary narrowing applies to package actions without accidentally
  narrowing global compiler detection.

### Capability and metadata boundaries

- **Opam and workspace consumers see only direct package capabilities**
  (`f297150d6d34`, `916425aeca85`). Transitive ordering no longer implies
  transitive binary, variable, or environment visibility.
- **Virtual packages forward their selected concrete capabilities**
  (`51a18456c8e2`) rather than disappearing when legacy adapters are removed.
- **Install entries are computed per loaded package** (`d839b13cab25`).
  Filtering by loaded-project identity avoids cross-owner metadata and
  workspace install cycles while allowing metadata and layouts to share the
  result.
- **Required auxiliary libraries are exported into owner metadata**
  (`06ef15b4ff81`) without becoming globally public.
- **Mounted library closure boundaries are retained** (`97775cdd4a55`),
  including JavaScript lookup, instead of expanding every private library from
  a shared source.
- **Selected lock versions appear in generated package metadata.** Source
  project versions no longer override the version chosen by the lock.

### Build hygiene and host-tool fixes

- **Runtime-event traces no longer modify the source tree** (`1f1326a52e2e`).
  This prevents rich tracing from invalidating the filesystem memo and rewriting
  the workspace cache on a null build.
- **The Dune source rules that run `%{ocaml}` declare `%{ocaml_where}`**
  (`283eeae6bb78`). They set action-local `OCAMLLIB`, so a relocatable selected
  compiler sees its stdlib in a sandbox without adding a global package-binary
  runtime-closure mechanism.
- **A fake or different `dune` earlier on `PATH` cannot capture native package
  builds.** Native packages use the current process; only explicitly opaque
  recipes may invoke another Dune.
- **Mounted compiler and error paths use the stable package-name hierarchy.**
  Source checks reject `_fetch` as the intended native diagnostic identity.

## What worked as planned

### Current-process loading is viable

Native packages are ordinary loaded Dune projects with explicit output
ownership. Their libraries, executables, PPXs, generated files, aliases, and
install metadata are generated by the top-level Dune process. Native-to-native
edges compose directly rather than crossing an installed-package boundary.

This remained true even for large staged PPX graphs and packages with nested
projects. The architecture therefore passed the most important feasibility
test: native package rules do not need a second scheduler or a nested package
Dune.

### Path kinds retained their meaning

The prototype did not give fetched files virtual workspace identities.
Workspace paths remain watched, user-owned, and promotable. Fetch and package
paths remain build-owned and are not promotion destinations. External paths
remain external inputs.

This avoided the earlier prototypes' most expensive mistake: once a fetched
file pretends to be a `Path.Source.t`, copying, selectors, fallback handling,
cleanup, promotion, and diagnostics all need mounted-package exceptions.

### The source abstraction was the correct seam

Rules that need topology or bytes use `Source_tree.Rules.Dir` and
`Source_tree.Rules.File`. A mounted file decides how to enumerate, read,
materialize, and diagnose itself. Consumers do not infer source ownership from
a generic `Path.Build.t` shape.

This abstraction supported ordinary includes, dynamic includes, OCaml-syntax
Dune files, `copy_files`, recursive `(source_tree ...)`, module discovery, and
source/generated/fallback selection. Mounted `copy_files` was fixed locally;
ordinary `copy_files` still sees generated files unless `(only_sources)` is
requested.

### Explicit artifact ownership scaled

`Build_partition`, loaded projects, loaded directories, scopes, objects,
install entries, PPX drivers, and local binaries carry an explicit output
owner. This was a broad migration, but it was more reliable than recovering an
owner from a source path or context-name suffix.

Mounted packages retain install entries needed by `dune-package`, relocation,
`Install_layout`, external `ocamlfind`, and Opam/Topkg consumers. They do not
gain workspace install aliases or workspace ownership.

### Builder unification worked

The synthetic Opam stanza proved useful as a real rule primitive rather than a
second package universe. Source-backed and source-less opaque packages use the
same action expansion, sandbox, install layout, and cookie model. Native
consumers can use opaque libraries and binaries; opaque consumers can receive
native install layouts and environments.

The package dependency refactor was especially successful. Moving from the
mechanically extracted recursive runtime to `Package.depends`, `Package_db`,
and `Package_deps` made capability visibility explicit and allowed normal
`.pkg` dispatch to be removed.

### Scopes solved the practical ownership problem

The unreleased scope stanza and synthetic mounted scopes operate over canonical
decoded projects. They prevent every package found in a shared source from
becoming globally visible, while preserving private implementation libraries
needed by the selected package.

A general nested-project export policy was not required for the prototype. The
smaller rule, "selected owner plus required private closure", was enough and is
a better starting point for production.

### Regression-first development paid off

The difficult failures were reduced to focused Cram tests before their fixes.
This was particularly valuable for:

- mounted source and artifact paths;
- private and virtual library metadata;
- PPX ownership;
- binary narrowing;
- overlays, patches, substitutions, and deletion;
- recursive source-tree materialization;
- mixed workspace dependencies;
- compile-command collection cycles; and
- null-build workspace-cache writes.

Keeping test and fix changes separate made it possible to discard broad fixes
without losing the evidence that motivated them.

## What changed during implementation

### Separate source and artifact trees became one logical hierarchy

The original plan treated `_fetch/.../dir` as the package's complete native
source root and generated artifacts elsewhere. That is clean in isolation, but
native Dune semantics repeatedly relate a source directory to its corresponding
build directory. Carrying two unrelated physical hierarchies through every
rule either multiplied path plumbing or encouraged another remapping layer.

The final design retains `_fetch` only as immutable backing. The rules-side
source tree gives each file its canonical logical path under `pkg/<name>`, and
fine-grained rules materialize it there. Authored and generated paths can then
participate in ordinary Dune selection without a directory target claiming the
whole package root.

This is controlled coexistence, not the old source/artifact co-location:
ownership is per file, immutable bytes stay in `_fetch`, and no synchronization
step mutates or mirrors a complete source tree.

### Package identity became name-based

Digest-addressed output roots made a transport property part of package
identity. They also leaked long, unstable paths into diagnostics, metadata, and
tests. The selected lock universe already provides one package per name, so the
normal package map and root now use `Package.Name.t`.

The source digest still does the job it is good at: identifying reusable
acquisition content under `_fetch`. It does not select scopes, capabilities,
artifacts, or normal package rules.

### Classification became ownership-aware

"Any Dune file means native" was too broad. Real Opam sources can contain an
incidental Dune project in an example, test fixture, or vendored directory that
does not define the selected package.

The final classifier first constructs the transformed logical view, detects
Dune files, and then checks whether an enabled decoded project defines the
selected package. Otherwise the package remains opaque. Parsing errors in a
candidate native project are still real errors; they are not silently converted
into an opaque build.

### Native preparation became a static extraction problem

The plan originally deferred patches, substitutions, lock `files/`, and extra
sources to a transformed source target. The final one-root invariant ruled out
that second root.

Instead, overlays are source layers and deterministic transformations produce
exact in-memory contents or deletion layers. This handles ordinary Opam patches
and substitutions while preserving immutable acquisition data. If evaluation
requires package build outputs or unsupported dynamic action structure, native
loading is rejected conservatively and the complete recipe runs opaquely.

### Mixed workspace locks grew beyond the initial scope

The first goal concentrated on workspace consumers of lock packages. Real
projects, especially Dream, required repository packages to depend back on
workspace packages. The prototype therefore added:

- unchecked project-context loading for a generated mixed lockdir;
- workspace `Install_layout` environments and binaries for locked consumers;
- workspace precedence for path-like capabilities;
- lock generation that retains repository-to-workspace names; and
- tests with alternating locked and workspace nodes.

Generic disk validation remains strict. The project loader is the only place
that interprets the live workspace boundary.

### A few root-only rules needed explicit mounted guards

Mounted package roots and the workspace root can both appear to have no project
components. Dune 3.23 compile-command collection therefore tried to generate
`compile_commands.json` from every mounted root and created a directory-content
cycle in `re/private_re`.

The correct fix was not a source glob or load restriction. Compile-command
generation is a workspace-root service, so mounted dispatch skips it explicitly.
This is a useful general lesson: an empty component list is not proof that a
rule is running at the workspace root.

### Toolchain runtime data remained the user's dependency

The relocatable compiler exposed another distinction. Sandboxing the selected
`ocaml` executable without its sibling stdlib produced:

```text
Error: Unbound module Stdlib
```

A proposed generic package-binary runtime-closure mechanism was deliberately
abandoned. The affected Dune source rules execute the OCaml toplevel directly,
so those rules now declare `%{ocaml_where}` and set `OCAMLLIB` for that action.
The fix is local to the authored consumer rather than changing every package
binary's semantics or injecting a global `OCAMLLIB`.

## Mechanisms deliberately avoided or removed

The final prototype contains none of the following in the normal package path:

- virtual `Path.Source.t` values for fetched files;
- virtual-to-real source redirection;
- mutable process-global mount registries;
- reverse path-to-package lookup;
- source claim rules;
- prepared, snapshot, shadow, or copied source trees;
- source manifests or provider callbacks;
- symlink mounts;
- a whole-source directory target under `pkg/<name>`;
- digest-addressed normal package roots;
- a parallel normal `.pkg` package graph;
- a second semantic workspace context;
- global exposure of all mounted binaries or environments;
- global attachment of every package's runtime closure;
- treating all `copy_files` globs as source-only;
- loading opaque Opam sources into `Dune_load`; or
- accepting `_fetch` paths in native diagnostics as the intended interface.

Several of these were tried temporarily. Removing them was progress, not lost
work: each experiment clarified which ownership fact was missing from the
simpler model.

The prototype also rejected performance changes that had no stable measured
benefit. Complete package-metadata memoization and an optimization for absent
lock `files/` were reverted rather than retained on intuition.

## Unexpected costs and lessons

### The migration was broader than the first vertical slice suggested

The net prototype range touches 286 files and adds substantially more code than
a reviewable production change should. Native loading reached almost every
rule family that had encoded the assumption that source and output directories
were paired workspace paths:

- libraries and executables;
- PPXs and preprocessing;
- Merlin and OCaml index data;
- foreign stubs and configurator metadata;
- MDX, odoc, Cinaps, and Cram;
- JavaScript and Melange rules;
- Rocq rules;
- install metadata and public binaries;
- aliases, globs, includes, and generated sources.

The lesson is not that the abstraction was wrong. It is that a production
series should establish the ownership types first and land consumers in
reviewable groups, each with a focused package regression.

### Capability visibility is different from build ordering

A package may need its full transitive closure to be built without being
allowed to resolve every transitive binary or package variable. Early global
maps caused both accidental visibility and dependency cycles.

The final useful split is:

```text
direct declared edges  -> capabilities and path precedence
transitive closure      -> ordering and installed-library availability
explicit forwarding    -> virtual packages and compiler facilities
```

This distinction should be part of the first production package-dependency API,
not repaired independently in binary, environment, and library lookup.

### Metadata is observable behavior

A package can compile successfully and still be unusable if private archives,
`META`, `dune-package`, relocation information, or install-section paths are
wrong. Real external projects exposed these issues more effectively than small
library-only tests.

Mounted install entries should therefore be described as package metadata, not
as workspace installation requests.

### Observability can perturb the build

Rich runtime tracing originally wrote `<pid>.events` into the source root. The
filesystem memo observed that transient file and rewrote `_build/.db` on an
otherwise null build. Moving runtime events outside the source tree restored a
stable cache.

Tracing configurations also affect rule digests and must be warmed separately.
Enclosing spans such as `Alias builder` cannot be interpreted as exclusive CPU
time, and overlapping child durations must be combined by wall-time union.

### External provenance must be controlled early

Several investigations were delayed by using `_boot/dune.exe`, inheriting
Dune/OCaml environment variables, or sharing a build directory between
processes. External validation became reliable only after consistently using:

```text
/home/ali/dune3/_build/default/bin/main.exe
```

with `DUNE_SOURCE_ROOT`, `INSIDE_DUNE`, `OCAMLPATH`, `OPAM_SWITCH_PREFIX`, and
compiler-library overrides unset.

## Performance outcome

Profiling the real `ocaml-cohttp` graph found repeated structural work rather
than one dominant source-loading cost. The useful optimizations were small and
composable:

- linear construction of concatenated `PATH` values;
- retained list-valued environments with one final serialization;
- one shared native environment root;
- memoized selected package paths;
- shared opaque materialization and binary maps;
- reused mounted scope databases; and
- owner-indexed mounted library and install stanzas.

On the measured cache-stable null workload, wall time fell from roughly 30
seconds to about 4.2 seconds. Maximum RSS fell from roughly 1.7 GiB to about
607--609 MiB. Minor allocation fell from about 3.036 billion to about 396.8
million words.

These are local prototype measurements, not portable benchmark claims. Timing
variation was larger than some attempted changes, and those changes were not
credited. Allocation sampling was a more stable guide for structural work.

The remaining graph is still large: one instrumented run had about 143,000
Memo nodes and 866,000 edges. Mounted Merlin configuration serialization was
the largest identified direct-major allocator. It could not simply be disabled
because compilation rules currently consume `.merlin-conf`. Production work
should decouple compilation dependency tracking from editor configuration
before trying to remove that cost.

## Validation evidence

The focused package suite covers, among other cases:

- one-root package-name layout and absence of normal `.pkg` rules;
- local, HTTP, source-less, and opaque sources;
- source overlays, executable files, patches, substitutions, and deletion;
- generated/fallback precedence and promotion isolation;
- includes, dynamic includes, `copy_files`, and recursive source trees;
- nested projects, scopes, private libraries, and redirects;
- native and opaque libraries, PPXs, binaries, variables, and environments;
- direct capability narrowing and virtual-package forwarding;
- install cookies, `META`, `dune-package`, and external `ocamlfind` behavior;
- autolock and watch paths;
- alternating workspace and locked dependencies;
- compile-command cycle prevention; and
- null-build cache stability under rich tracing.

During development, the prototype completed real `ocaml-re` and
`ocaml-cohttp` workloads. Dream validated a real repository-to-workspace edge
and reached source compilation before an unrelated selected Caqti API
incompatibility.

The Dune self-build found the mounted compile-command cycle and the relocatable
compiler stdlib issue. After the two local fixes, both `dune build src` and
`dune build %{bin:dune}` succeeded in the existing external build directory
without an ambient `OCAMLLIB`. A fresh alternate build directory reached
construction of the relocatable compiler before that validation run was
interrupted, so this document does not claim a final clean self-build from that
run.

Focused `@check`, formatting, package, lockdir, and regression suites passed
throughout the stack. The complete `@runtest` environment still includes
unrelated timeouts, network fixtures, benchmark dependencies, and existing
expectation differences. Prototype completion therefore means the architecture
and target scenarios are demonstrated, not that this branch is ready to merge
unchanged.

## Work intentionally left for productionization

The following are no longer blockers for the prototype conclusion, but they
must be resolved before a production feature is proposed.

### Mixed-lock contract

Generated mixed lockdirs need an explicit workspace boundary containing at
least referenced package names, selected versions, and hashes of solver-relevant
metadata. Contextual validation must distinguish harmless source edits from
changes that require relocking, including portable conditional-platform
branches.

Cycle detection must operate over one graph whose nodes are either workspace or
locked packages and report complete mixed-origin paths. Standalone lockdir
validation should remain strict unless an explicit boundary format gives it the
information needed to do otherwise.

### API and implementation reduction

The production design should reduce the visibility of `Source_path.t`, make
mounted owner containment explicit, and group consumer migrations into smaller
changes. Mounted branches that merely compensate for weak ownership types
should be replaced by capability-bearing values where practical.

The unreleased `scope` and `opam` stanzas are useful test interfaces, but their
public future remains a separate product decision.

### Diagnostics and audits

Native errors should consistently show logical package paths and source
excerpts, never acquisition paths. Acquisition still needs a final audit for
VCS refresh, failed-fetch retry, stale removal, symlink edge cases, cross-lock
reuse, watch invalidation, and interrupted materialization.

The remaining `.dev-tool` regressions should be handled without reopening the
normal legacy route. `dune pkg print-digest` should also be removed, renamed, or
explicitly documented now that normal package roots are not digest-addressed.

### Final external and performance checks

A production series should rerun clean current-head `ocaml-re`,
`ocaml-cohttp`, Dream, and Dune self-builds in isolated build directories. It
should retain the cache-stable null benchmark and add focused counters that
prevent full mounted scope or install traversals from returning.

## Recommended production sequence

If this work is rebuilt as a mergeable feature, the shortest sequence is:

1. Introduce the package-name root and explicit artifact owner without changing
   normal package routing.
2. Introduce logical/backing mounted files and prove one local native library
   with fine-grained materialization.
3. Move rule consumers in coherent groups, retaining one regression per group.
4. Add canonical package scopes and owner-private auxiliary closure.
5. Materialize dependencies from `Package.depends` and `Package_db`, with
   direct capabilities and transitive ordering separated from the start.
6. Add the opaque Opam boundary and then remove normal `.pkg` routing.
7. Add ordered overlays and conservative static transformation extraction.
8. Add mixed workspace edges only together with their persisted boundary and
   cycle-validation contract.
9. Run real external graphs and profile cache-stable null builds before adding
   further memoization.

Do not start by porting the current branch wholesale. Start from the invariants
and tests that survived it.

## Bottom line

The original plan was right about the hard boundaries:

- build native lock packages in the current process;
- keep fetched input out of `Path.Source.t`;
- put build-backed operations behind a rules-side source API;
- preserve opaque packages as explicit boundaries;
- make artifact and dependency ownership explicit; and
- avoid teaching the engine about packages.

It was wrong or incomplete about three important details:

- native source did not need a second prepared physical root;
- digest was not the right normal package address; and
- the presence of any Dune file was not enough to identify the selected
  package's builder.

The final prototype replaced those assumptions with one package-name hierarchy,
logical files backed by immutable acquisition data, per-file transformation
layers, and ownership-aware classification. It also demonstrated that the
model can preserve realistic metadata and capability boundaries and can be made
fast enough for large null builds.

That is a successful prototype outcome. The next task is not to add more
features to this branch. It is to turn the validated model into a smaller,
staged production design while preserving the negative lessons just as
carefully as the working mechanisms.
