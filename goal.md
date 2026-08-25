# Build locked Dune packages in one workspace

This is the design plan for the next `flatten-dune` prototype. The archived
prototype remains evidence for supported behaviour, but its virtual-source
architecture is not a compatibility constraint.

## Goal

A locked package described by Dune is loaded and built by the current Dune
process as part of the workspace rule graph. Dune does not launch a nested Dune
process for that package.

A **mounted** package uses native Dune loading and rules. A **legacy** package
keeps the existing `.pkg` fetch/build/install path and executes the complete
action stored in the lock.

Workspace packages retain their existing behaviour.

## First vertical milestone

The first working milestone contains only:

- one existing explicit source lock;
- one local archive containing one Dune package;
- one literal translated `dune build ...` action;
- one target-backed package source root whose real location is a `Path.Build.t`;
- one separate package artifact root;
- one workspace library consuming the mounted library;
- no virtual `Path.Source.t`, nested Dune process, old `.pkg` rule for the mounted
  package, or package-specific engine behaviour.

HTTP, VCS and live-directory sources, autolock, shared sources, nested projects,
legacy consumers, source refresh, and watch mode are outside this milestone. They
are added only after the core path works.

## Path and ownership invariants

Path kinds retain their existing meanings:

- `Path.Source.t` is watched, user-owned workspace input and may be promoted to;
- `Path.Build.t` is graph-produced data, is not watched as workspace input, and
  is never a promotion destination;
- `Path.External.t` is external input that may be watched but must not be modified
  by build rules or promotion.

A fetched package source is not a `Path.Source.t`. If its producing rule owns a
build directory, that directory and the files beneath it remain build-backed
sources. Generated objects and install entries live under a different output
root; they are never placed beneath an opaque source directory target.

The following are independent values:

| Concern | Representation |
|---|---|
| Lock package identity | Exact package identity in one lock universe |
| Project identity | Stable semantic identity, independent of physical paths |
| Source location | Workspace `Path.Source.t` or mounted `Path.Build.t` |
| Relative project path | `Path.Local.t` |
| Artifact ownership | Explicit resolver/toolchain and `Path.Build.t` output root |

No value is reconstructed from another. In particular:

- no mounted source is given a virtual workspace path;
- no output directory is derived from a source path and context name;
- no library object owner is recovered from its name and source path;
- no context-name suffix stands in for artifact ownership.

## Generalizing `Path.Source.t`

Existing rules-layer APIs use `Path.Source.t` because workspace input was
historically the only source kind. Those types are hypotheses, not compatibility
boundaries.

At each affected API:

1. If it reads bytes or records a dependency, accept a source/build location
   variant and preserve the real path kind.
2. If it needs only project-relative identity, take `Path.Local.t` and an explicit
   project identity instead of a physical source root.
3. If it places generated files, take the output `Path.Build.t` explicitly.
4. If it reports a location, use the real input path without making it an artifact
   authority.
5. If it promotes, permit only genuine workspace `Path.Source.t` inputs.

An illustrative rules-side location is:

```ocaml
type source_location =
  | Workspace of Path.Source.t
  | Mounted of
      { root : Path.Build.t
      ; package : Package_instance.t
      ; visible_packages : Package.Name.Set.t
      }
```

The exact type and module name are not prescribed. There need not be one global
variant when an API can simply stop depending on a source path. What is required
is that mounted input remains `Path.Build.t` and that consumers cannot silently
apply workspace semantics to it.

A loaded directory or project must carry, directly or through its owner:

```text
source location + relative directory + project identity + artifact output root
```

This is the boundary at which source and output paths become explicit.

## Engine and rules source views

The engine continues to receive the ordinary workspace `Source_tree`. It uses
that tree for workspace source-copy rules, fallback suppression, directory
loading, and cleanup. It receives no mount registry, package identity, or mounted
source exception.

`Dune_load` and rule generation need a richer rules-side view containing:

- ordinary workspace directories; and
- mounted directories rooted at real `Path.Build.t` fetch targets.

This may be implemented by generalizing the rules-side `Source_tree` path type or
by a separate rules-layer representation. It must not install build-backed
pseudo-sources into the engine's workspace view.

Mounted nodes are built and read through existing build-system APIs. Fetch and
source-preparation rules are derived from lock data alone, so loading a mounted
`dune-project` cannot depend on rules that themselves require that project to be
loaded.

```text
lock data
  -> independent fetch/source target rules
  -> prepared mounted-or-legacy routes
  -> rules-side source view
  -> Dune_load
  -> package rules
```

## Package preparation and routing

The lock remains a cache of repository metadata. It stores each selected
package's complete translated action, including wrappers, filters, environment
updates, configure steps, and mixed commands. It does not store a `dune_based`
marker, and a build does not consult the opam repository again.

Source transport and build routing are separate decisions. Preparation returns an
explicit immutable value for each selected package:

```text
exact package identity + source target, if any + Mounted or Legacy route
```

That value is passed to source-tree construction, `Dune_load`, package-rule
routing, and dependency integration. It is not published through a mutable global
registry or recovered by reverse path lookup.

For the first milestone, the local archive is mounted only if:

1. its complete `dune-project` package universe declares the locked package; and
2. every unconditional executable step in the selected action is a literal
   `dune build ...` invocation.

Wrappers such as `chdir` and environment updates are transparent. Non-Dune,
dynamic, shell, patch, substitute, install, mixed, or unknown unconditional work
fails closed to the legacy route. Package masking is applied after the complete
project has been decoded.

## Artifact ownership and dependency resolution

A mounted package uses the workspace context's compiler, tools, resolver, and
host relationship, but owns artifacts beneath a separate package output root.
This is an alternate physical owner, not a second semantic workspace context.
Implicit workspace aliases and path targets do not run in it.

Libraries, objects, binaries, install entries, scopes, diagnostics, Merlin data,
and compile commands must use the explicit source and artifact owners. The first
milestone migrates only the consumers needed by its package and workspace library;
later milestones complete the same type migration rather than add mounted
conditionals.

A mounted package receives no old `.pkg` target, cookie, or second build/install
action. Legacy consumers are deferred, but their eventual integration has two
separate edges:

- dependency identity must not request the mounted package's old `.pkg` rule;
- build dependency and environment must use its concrete mounted install output.

## Source selection

With source and artifact roots separated, the rules layer owns one consistent
selection policy for each output path:

- a standard or promote-mode generated rule may replace the corresponding source
  input when ordinary Dune semantics say it does;
- an existing source suppresses a fallback target;
- selectors and module discovery observe the same selected input;
- promotion never writes to mounted `Path.Build.t` sources.

Do not reintroduce engine source claims or source/output co-location to implement
this precedence.

## End-to-end flow

```text
workspace source view
  -> read explicit lock
  -> retain complete translated actions
  -> create source targets from lock data
  -> inspect and classify packages
  -> construct the rules-side source view
  -> lazily build/read mounted Path.Build roots
  -> load complete projects and apply semantic masks
  -> generate mounted rules into explicit package output roots
  -> expose mounted libraries to workspace rules
  -> route only Legacy packages through existing .pkg rules
```

Logical project identity, physical source location, and artifact ownership remain
separate throughout this flow.

## Behaviour retained from the archived prototype

Later milestones retain these proven decisions:

- runtime source inspection chooses native loading versus legacy rules;
- the conservative action veto prevents dropping non-Dune work;
- mounted projects have vendored warning, alias, and promotion behaviour;
- masks are applied after complete project decoding;
- mounted packages strictly bypass old package rules;
- legacy consumers receive mounted install outputs and environments;
- lock generation uses a workspace-only source view;
- autolock may complete in one invocation through two explicit loading phases;
- source refresh, generated/fallback precedence, and watch invalidation are
  correctness requirements;
- mounted outputs remain isolated from workspace outputs.

## Mechanisms not to reuse

The new implementation must not contain:

- virtual `Path.Source.t` identities for fetched targets;
- virtual-to-real source lookup or `Source_tree.real_path` engine configuration;
- mounted exceptions in engine copying, lookup, selectors, fallback handling,
  cleanup, or promotion;
- co-located fetched sources and package artifacts;
- build-start synchronization into the artifact root;
- synthetic source-claim rules;
- a mutable process-global mount registry or registry-generation invalidation;
- reverse path-to-package or path-to-context lookups;
- a second full workspace context;
- an external source-snapshot store, manifest, or provider callback layer;
- compatibility shims around the archived prototype's internal APIs.

The archived implementation may be consulted for behaviour and tests, not used as
a scaffold.

## Implementation order

1. Remove the snapshot-store detour and return package input to real build-backed
   paths.
2. Define the minimal rules-side source-location and loaded-directory boundaries.
3. Migrate the workspace loading path through those boundaries without changing
   behaviour; the engine source view remains workspace-only.
4. Derive the local archive's source rule from lock data and load its
   `dune-project` and `dune` files through the real `Path.Build.t` root.
5. Generate one mounted library into an explicit, separate package output root.
6. Expose that library to and link it from one workspace library.
7. Add source/generated/fallback cases before expanding materialization or source
   selection machinery.
8. Extend the proven path to HTTP and action fallback, then legacy consumers,
   package masking and nested projects, autolock, refresh, and watch mode.
9. Exercise a real package graph once the smallest end-to-end path works.

No step adds an abstraction solely to preserve an API that incorrectly requires
`Path.Source.t`. Generalize that API or remove its physical-path dependency.

## Verification

The first milestone is complete only when the built Dune executable demonstrates:

1. A local-archive package is loaded and built in the current process.
2. A workspace library compiles and links against the mounted library.
3. Mounted source reads depend on their real build targets.
4. Package artifacts exist only beneath the explicit package output root.
5. The mounted package has no old `.pkg` build directory, cookie, or action.
6. No nested/external Dune invocation occurs.
7. The engine has no mounted-source branch, fake source fact, or cleanup exception.
8. Existing workspace loading and build behaviour remain unchanged.
9. The source root and artifact root have distinct rule ownership.
10. The implementation contains no virtual source redirection or snapshot provider.

Use `_build/default/bin/main.exe` for the end-to-end scenario. Trace assertions
must use a fresh action cache when checking process execution.

After that milestone, carry forward focused cases for HTTP and fallback routing,
generated/fallback precedence, vendored behaviour, masking and nested projects,
legacy-package interoperability, autolock, refresh and watch invalidation,
symlinks, promotion suppression, and a real opam-repository package graph.

## Review evidence

The implementation review should show:

- the source-location and loaded-directory boundaries;
- the rule-generation dependency path from lock data to source targets;
- explicit source and artifact ownership at changed call sites;
- the end-to-end trace and artifact layout;
- any remaining `Path.Source.t` assumptions and why they are workspace-only.
