# Retrospective: building locked Dune packages in one process

- Status: prototype retrospective
- Current bookmark: `prototype/flatten-dune`
- Current tip reviewed: `acb207429700`
- Earlier design record: [`goal.md`](../../goal.md)
- Historical archive:
  `prototype/flatten-dune-archive-2026-08-24T1337Z`

This document records what the target-backed mounted-package prototype taught
us. It compares the current implementation with the earlier prototype tracks,
audits their behavioral tests, and gives broad implementation guidance for a
future production feature.

It is not a claim that the current implementation is ready to merge. The
prototype still contains broad type migrations, mounted-specific branches, and
interfaces that should be simplified. The implementation guide therefore
records boundaries and sequencing rather than prescribing the current code as
the final design.

## Executive summary

The product goal is viable. Dune can load locked package sources and generate
their rules in the current process instead of running a nested Dune for each
package. The current prototype successfully builds both `ocaml-re` and
`ocaml-cohttp`, including large PPX, compiler, legacy-package, binary, install,
and provider graphs. These successful builds were local prototype observations;
their traces and shell environments are not checked into the repository.

The central architectural improvement over the earlier implementation tracks is
that a fetched source remains a build-backed source:

```text
source owner:   _build/_fetch/.../dir
artifact owner: _build/_default+lockfile/pkg/<package-and-digest>/...
```

It does not masquerade as a workspace `Path.Source.t`. The ordinary engine
source tree remains workspace-only. A separate rules-side `Source_tree.Rules`
view loads real `Path.Build.t` directory targets and gives rule generation a
uniform directory and file API.

This removes the earlier prototypes' defining liabilities:

- virtual `pkg/...` workspace paths;
- `Source_tree.real_path` redirection;
- source and artifact co-location;
- source-claim rules and source manifests;
- a process-global mutable mount registry;
- package-driven exceptions in engine lookup, copying, cleanup, selectors, and
  promotion;
- reconstruction of artifact ownership from source paths and context names.

The behavioral comparison also found real gaps. The current tests are stronger
around target-backed ownership, includes, PPX, binary narrowing, lookup cycles,
and loading multiplicity, but they do not directly retain every useful fixture
from the older prototypes. The highest-value comparison work is:

1. replace recipe-shape routing with prepared package sources and source-only
   `Dune` or `Opam` builder selection;
2. port the complete native A -> Opam-built B -> workspace C composition;
3. restore source refresh, stale-file removal, failed-fetch retry, and reuse;
4. add lock-selected compiler and cross-lock digest-identity regressions;
5. add direct workspace binary and same-project masking cases;
6. complete formatting, warning, version, and promotion coverage;
7. defer auxiliary nested-project visibility to the later in/out design unless
   retaining the complete decoded universe simplifies the current model.

Some archived cases are intentionally outside the current scope. Extra-source
overlays, VCS sources, and live directory sources route through legacy package
rules. The old virtual `pkg/` workspace collision tests no longer apply because
there is no virtual workspace overlay. The current policy also deliberately
lets an immediate selected dependency on `dune` replace the complete recorded
recipe, whereas the archive vetoed any mixed or separate install action.

## Scope of the comparison

The comparison covered these snapshots:

- `prototype/flatten-dune/main` at `8a395ee93d43`;
- `prototype/flatten-dune/fresh` at `371fe553c417`;
- `prototype/flatten-dune/exp3` at `a3a7f32dbcfa`;
- `prototype/flatten-dune-archive-2026-08-24T1337Z` at
  `4c5109f8ff61`;
- current `prototype/flatten-dune` at `acb207429700`.

`prototype/flatten-dune/plan` was reviewed as a design-only predecessor rather
than an implementation snapshot. The historical
`review/flatten-dune-prototypes` bookmark was used as supporting review
evidence, not counted as another implementation.

The early tracks branch from older upstream revisions, so raw line counts are
not directly comparable. The audit compared each prototype with its own common
ancestor and inspected the bodies of its added cram tests. A matching filename
was not treated as proof of equivalent behavior, and a renamed test was not
treated as missing when the same scenario was demonstrably covered elsewhere.

The comparison itself was static. It did not build the historical revisions.
The successful `ocaml-re` and `ocaml-cohttp` builds are evidence from the
current prototype work, not from rerunning every archived snapshot.

## The problem

A locked package is normally built by package rules:

1. fetch or copy its source;
2. create a private package sandbox;
3. execute the translated opam recipe, often by launching another Dune;
4. install the result into a private package layout;
5. expose that installed result to consumers.

For a package already described by Dune files, this duplicates Dune's project
loading, dependency resolution, scheduling, and rule generation. It also gives
nested Dune processes independent job schedulers and requires dependency
closures to be materialized into package sandboxes.

The mounted-package approach replaces the complete recorded recipe for selected
packages with native loading and rule generation in the current process. Other
packages remain **legacy** packages and retain existing package rules.

The required mixed graph is therefore not merely:

```text
workspace -> mounted package
```

It may contain all of these edges:

```text
workspace -> mounted
workspace -> legacy
mounted   -> mounted
mounted   -> legacy
legacy    -> mounted
```

Libraries, public executables, PPX drivers, package variables, install metadata,
compiler tools, and exported environments must all respect the same dependency
visibility boundary.

## The current model

The current prototype's end-to-end dependency flow is:

```text
workspace-only source view
  -> read or generate the lock
  -> retain complete translated package actions
  -> derive lock-only candidates and fetch targets
  -> load eligible build-backed projects through Source_tree.Rules
  -> classify and mask mounted projects
  -> infer all other packages as legacy by absence
  -> generate mounted rules into explicit artifact roots
  -> expose scoped libraries, binaries, PPXs, and install layouts
  -> run old package rules only for packages not classified as mounted
```

Inferring `Legacy` by absence is prototype debt. A production design should
retain the same two-stage dependency order but produce an explicit classified
route after source inspection.

The fetch rule must be available before loading the project contained in its
target. It must therefore be derivable from lock data alone. Otherwise loading a
mounted `dune-project` would create a rule-generation cycle:

```text
Dune_load
  -> read mounted dune-project
  -> build source target
  -> generate source-target rules
  -> Dune_load
```

The current `_fetch` namespace provides the independent source ownership needed
to break this cycle.

## What worked well

### Path and ownership invariants were corrected

The current prototype preserves the existing meanings of path kinds:

- `Path.Source.t` is watched, user-owned workspace input and may be promoted;
- `Path.Build.t` is graph-produced data and is never a source promotion
  destination;
- `Path.External.t` is external input that may be watched but must not be
  modified by build rules.

A fetched source directory is a real build directory target. Generated objects,
metadata, and install entries have another owner. This makes cleanup,
invalidation, promotion, and direct artifact targets ordinary rule-graph
operations rather than mounted exceptions.

### The engine remained package-agnostic

The early prototypes added a virtual-to-real source callback to engine
configuration. Engine source copying, source lookup, selectors, fallback rules,
dependency recording, and cleanup then had to recognize pseudo-sources.

The current engine additions are generic capabilities:

- build and enumerate a directory target;
- read files produced by build rules;
- apply one source/generated/fallback selection policy;
- allow source-copy rules to depend on a general path.

The engine receives no package identity, mounted registry, or reverse source
mapping. Its normal `Source_tree` projection remains workspace-only.

### Source and artifact ownership became explicit

`Loaded_project` carries the values that callers previously reconstructed:

- stable project identity;
- source root;
- rules-side source-tree root;
- build partition and resolver;
- explicit output root;
- visible package mask.

`Loaded_dir` adds the project-relative directory and its output directory.
`Build_partition` distinguishes the resolver/toolchain from the physical output
root and whether implicit workspace targets apply.

This was broad, but it was a coherent migration. It fixed assumptions in
library objects, scopes, PPX drivers, binaries, install entries, diagnostics,
Merlin, and generated-source handling instead of adding another path remapping
layer.

### Real projects drove integration work

Small fixtures found ownership and routing errors. `ocaml-re` and
`ocaml-cohttp` found the interactions between them:

- staged PPXs and cross-package PPX ownership;
- `include_subdirs` groups over build-backed directories;
- generated files and ordinary includes;
- package providers whose names differ from their findlib libraries;
- package-scoped binaries and ambient compiler tools;
- parent-relative install globs;
- workspace and package install-metadata cycles;
- large mounted and legacy dependency closures.

Successfully building both projects is the strongest result of the prototype.
It does not prove that every edge case is covered, but it demonstrates that the
architecture can support a realistic lock universe.

### Focused regressions and separate commits helped

Many difficult failures were first reduced to cram tests. Regression changes
were kept before their fixes, and incomplete vendored-project work was isolated
on a detached revision rather than folded into a working stack.

This made it possible to recover from failed architectural experiments without
losing the useful implementation or its evidence.

### Profiling found genuine algorithmic problems

Two important findings were independent of the source architecture:

- `Per_context.create_by_name` memoizes lookup but does not by itself memoize
  evaluation of a supplied `Memo.t`. Wrapping mounted discovery in
  `Memo.Lazy` reduced repeated loading substantially.
- Package digest lookup rebuilt complete closure digest tables for thousands of
  consumers. Retaining a name and digest index reduced the affected large null
  build from roughly two minutes to a few seconds.

These were real null-build and rule-generation costs. They should not be
confused with the cost of a clean package build. The timings in this section
are local, unarchived observations; the repository retains multiplicity tests,
not benchmark artifacts.

## What could be improved

### Performance workloads were conflated

We did not initially separate:

1. a clean package build;
2. a warm build with action-cache hits;
3. a null rule-generation build;
4. replay of a failed build;
5. native mounted rules versus legacy nested recipes.

The package digest problem dominated one null/failure workload. It did not
explain the successful clean `ocaml-cohttp` trace:

- total build time was about 481 seconds;
- Dune loading took about 28 milliseconds;
- lock-directory loading took about 18 milliseconds;
- the first package sandbox started after about 0.4 seconds;
- the first nested Dune started after about 1.1 seconds.

That build instead contained 171 nested Dune invocations, hundreds of outer
sandboxes, and very large block output. These figures came from a local trace
that is not checked into the repository and must be reproduced before being
used as release evidence. The later
`sandbox/materialize-dependencies` event was added to measure the suspected
copy phase directly. It should have existed before making a causal claim from
the broader `sandbox/create` span.

Future measurements must state the binary revision, environment, target, cache
state, clean/warm state, success status, and whether another Dune process owns
the build directory.

### The implementation grew before the smallest vertical path stabilized

The feature necessarily crosses many rules modules, but some breadth came from
adding autolock, HTTP, watch mode, install layouts, providers, and performance
work while source ownership was still changing.

A future implementation should first prove:

```text
one local archive
  -> one build-backed source target
  -> one mounted library
  -> one separate artifact root
  -> one workspace consumer
```

Only then should it add the mixed dependency graph and broader transports.

### Consumer visibility was discovered piecemeal

Libraries, executables, PPXs, `PATH`, package variables, and install roots all
needed the same concept: a capability derived from the consuming package's
selected dependency branch.

The current implementation gradually threaded package sets through these
systems. A production design should introduce the capability boundary early and
avoid global package tables that later need narrowing.

### Some debugging followed broad traces too long

`Alias builder`, `build-finish`, and `sandbox/create` are enclosing spans. A
large duration does not identify the work inside them. Silent intervals identify
missing instrumentation, not a specific cause.

The most useful investigations added narrow spans or deterministic counters:

- `mounted-dune-load`;
- `mounted-packages-load`;
- `package-digest-table`;
- `materialize-dependencies`.

This should be the default sequence: instrument, reproduce, change one hotspot,
then remeasure a successful workload.

### Environment and binary provenance were not controlled early enough

Investigations were delayed by:

- `_boot/dune.exe` versus the fully built executable;
- inherited `DUNE_SOURCE_ROOT` in isolated copies;
- missing `npm` and `zarith` dependencies;
- HTTP test-server port conflicts;
- concurrent Dune processes sharing one build directory;
- traces containing child events from a previous top-level process.

A benchmark checklist would have avoided much of this churn.

### The lock-index fix became too general during review

The repeated digest work was real, but attempts to make its cache universally
correct temporarily expanded into lock-directory APIs, revision hashing, and
structural equality details. Those changes distracted from the measured
workload and were reverted.

The lesson is to keep a performance patch local to the demonstrated repeated
work, add a focused invalidation test, and avoid generalizing adjacent APIs
until another consumer requires it.

## Comparison with the previous prototypes

### The common premise of the early tracks

`main`, `fresh`, `exp3`, and the archived implementation varied in fetch timing,
context construction, source claims, and invalidation. They nevertheless shared
one premise:

> Every loaded Dune source must have a `Path.Source.t` identity.

They mounted a package under a virtual path such as `pkg/foo.1.0`, redirected
that path to `_build`, and generally placed fetched files and generated
artifacts under the same package root.

Agreement between independent implementations was useful behavioral evidence,
but it did not validate this premise. The archive post-mortem correctly
identified it as the main architectural mistake.

### Source representation

Earlier prototypes represented a mounted root approximately as:

```ocaml
{ virtual_source : Path.Source.t
; physical_build : Path.Build.t
; package_mask : Package.Name.Set.t
}
```

Callers kept the virtual source path and recovered the physical path through
`real_path` when bytes or artifacts were needed.

Current code uses `Source_path.t`:

```ocaml
type t =
  | Workspace of Path.Source.t
  | Build of Path.Build.t
```

The rules-side source tree keeps this distinction private behind directory and
file operations. No arbitrary build path becomes source merely because of its
shape.

### Rule ownership

Earlier prototypes fetched or synchronized files into the final package output
root. The archive refined this with source manifests and non-destructive
updates, but the fetch still owned selected paths beside generated objects.
Synthetic claim rules were also explored so the engine would preserve files
already under `_build`.

Current code gives the complete fetched tree one ordinary directory target under
`_fetch`. The package artifact root is a separate rule domain. Only selected
source inputs are copied to artifact paths, and generated/fallback precedence is
resolved by generic source selection.

### Engine boundary

Earlier engine behavior included some combination of:

- virtual-to-real source lookup;
- suppressing source-copy rules for redirected paths;
- treating unowned build paths as direct source facts;
- adding mounted filenames to selectors;
- mounted cleanup and promotion exceptions.

Current engine behavior is not package-specific. Build-backed topology and bytes
are requested through existing build-system dependencies, while the ordinary
engine source view remains the workspace.

### State and invalidation

Earlier tracks published mounted roots through mutable process-global state and
included a registry generation in memo keys. The archive made the registry value
immutable, but its publication remained a global startup handoff.

Current mounted candidates are prepared per context and carried into loading.
There is no global source overlay or reverse path registry. Some routes are
still recovered by absence from the mounted list, which is noted below as debt.

### Artifact and resolver ownership

Earlier tracks often treated `_default+lockfile` as a derived context and
recovered ownership from the context name plus virtual source root. This could
make it behave like a second workspace context and duplicate implicit targets.

Current `Build_partition` records a resolver context and a separate output root.
A mounted partition shares compiler and resolver semantics with its owning
workspace context while disabling implicit workspace targets.

### Routing policy

The archive used a conservative action veto. Any unconditional non-Dune step or
separate install action kept a package on legacy rules.

Current routing is deliberately different:

- an immediate selected dependency on `dune` is authoritative;
- otherwise the selected build is either the lock's special Dune marker or an
  action with at least one literal `dune build ... @install` and no other
  unconditional executable work;
- condition-guarded actions do not participate in that fallback classification;
- the fallback action route also requires no selected install action and no
  depexts;
- extra sources force legacy routing;
- local archive files and HTTP sources may mount;
- local directories, VCS sources, and other fetch forms remain legacy;
- the decoded source must represent and enable the selected package.

This is the current prototype classifier, not the planned final boundary. The
chosen direction is to prepare a source directory target for every package,
including an empty target for a source-less package. Any Dune build file selects
native loading; only a tree with no Dune build files receives the internal
synthetic `Opam` stanza. Lock metadata and recipe shape do not participate.
`different-dune-in-path.t` must be reconciled with that native-first rule.

### Overall assessment

The current prototype is a clear architectural improvement:

- path kinds retain their ownership meaning;
- fetch targets and artifacts have independent owners;
- source, project, resolver, and artifact identities are explicit;
- the engine is not taught about packages;
- source selection is centralized;
- mixed mounted/legacy lookup is dependency-scoped;
- shared archives can use one fetch target and multiple artifact identities.

Its costs are also real:

- the migration touches many rules modules;
- mounted conditionals remain spread across consumers;
- the rules-side source API exposes more representation than the final feature
  may need;
- physical routing still uses a synthetic mounted context name in places;
- several older focused tests were folded into large multi-scenario cram files;
- some behavior from the archive was not carried forward.

## Behavioral test audit

### Coverage retained or strengthened

The current suite directly covers:

- native loading with no nested package Dune;
- strict absence of mounted `.pkg` rules and cookies;
- distinct recursive fetch and artifact targets;
- exact artifact-path requests after clean;
- source symlink preservation;
- generated, promote-mode, and fallback precedence;
- `%{project_root}` and source-tree dependencies;
- local archive and HTTP transport;
- one-invocation autolock;
- lock replacement in one running watch server;
- shared fetch targets with separate package artifact identities;
- nested locked projects and Cram data-project masking;
- `include_subdirs` over build-backed directories;
- static includes, dynamic includes, and OCaml-syntax Dune files;
- mounted PPX drivers used by mounted and workspace consumers;
- mounted-to-mounted executables and ambient `PATH` fallback;
- mounted-to-legacy and legacy-to-mounted library/PPX boundaries;
- provider packages whose names differ from their libraries;
- package-scoped binary narrowing;
- mounted loading and digest-table construction counts.

These cases are concentrated in:

- `pkg/mounted-dune-package.t`;
- `pkg/mounted-dune-package-projects.t`;
- `pkg/mounted-dune-package-ppx.t`;
- `pkg/mounted-dune-package-tools.t`;
- `pkg/mounted-dune-package-http.t`;
- `pkg/mounted-dune-package-autolock.t`;
- `pkg/mounted-dune-package-watch.t`.

### Coverage gaps and unsettled behaviors

The following old scenarios remain relevant comparison points. Most lack an
exact current regression; a few first require an explicit product-policy
decision.

#### Unselected nested vendored project

Historical tests:

- `mounted-nested-project.t`;
- `e2e-nested-vendor.t`.

A mounted package contains `vendor/.../dune-project`. The nested project
declares a package absent from the lock, and the mounted parent consumes its
public library.

Current nested-project coverage gives the nested package its own lock candidate.
Moreover, `Pkg_sources.mount` filters every discovered project to the selected
candidate package. The old auxiliary-project behavior is therefore not only
untested; it is likely narrower in the current implementation. The `exp3`
fixture also checked that recursive `runtest` did not enter the auxiliary
project.

The desired eventual behavior is that an auxiliary project can be an internal
input without automatically becoming visible outside the package. That belongs
to the later in/out design. Builder unification may retain the complete decoded
universe when that simplifies ownership, but it does not implement or decide
nested-project visibility.

#### Complete native -> Opam-built -> workspace chain

The complete historical fixture is the archive's
`mounted-chain-abc.t`. Similarly named tests on `main`, `fresh`, and `exp3`
covered only parts of the composition.

The full scenario combines several boundaries:

- native A invokes an Opam-built package tool through `%{pkg:...}`;
- Opam-built B compiles and links against native A through its environment;
- B installs a binary;
- workspace C depends only on B, resolves A transitively, and runs B's binary;
- under the planned builder model, only B receives the synthetic Opam stanza.

Current tests exercise these mechanisms separately, including PPX-shaped opaque
chains and native binary lookup. They do not retain this complete end-to-end
shape. A combined test is valuable because capability narrowing can make every
individual edge pass while losing the transitive composition.

#### Refresh, stale-file removal, repair, and HTTP retry

Historical tests:

- `mounted-refetch.t`;
- `mounted-fetch-retry.t`.

Current watch coverage keeps the package name and version stable while replacing
its archive URL. It does not prove:

- changing content and checksum at the same source URL or local path;
- removal of files and empty directories that disappear upstream;
- no fetch or extraction on an unchanged build;
- repair after deleting one source target;
- preservation or correct rebuild of generated siblings;
- retry of a failed HTTP fetch after a lock URL changes;
- reuse of a successful download in the same watch process.

Some archived assertions were specific to source manifests and claim rules and
should not be copied literally. The observable refresh and retry behavior should
be ported using target-backed expectations.

#### Lock-selected compiler and configurator metadata

Historical tests:

- `mounted-lock-compiler.t`;
- `mounted-configurator-runtime.t`.

The first selects compiler wrapper binaries from the lock and verifies that
mounted rules use that toolchain. This is high-value because using the host
compiler can make valid locked `.cmi` files appear corrupted. `ocaml-re` and
`ocaml-cohttp` exercise substantial compiler graphs, but are not substitutes for
a small provenance test.

The second is a separate, cheaper assertion that a mounted runtime action sees
the mounted partition's `.dune/configurator.v2` through `INSIDE_DUNE`.

#### Cross-lock digest identity

Historical test:

- `pkg/ocamlformat/mounted-package-digest-identity.t`.

A project lock and a dev-tool lock contain packages with the same name and
version but different source digests. The project entry is mounted while the
dev-tool entry remains independently resolved.

Current package tables and mounted checks use complete digests, and recent index
work explicitly preserves separate project and dev-tool name indexes. There is
nevertheless no equivalent end-to-end regression.

#### Builder-selection matrix

Historical tests:

- `mounted-action-veto.t`;
- `mounted-veto.t`.

The old expectation that mixed work must veto mounting is intentionally not
retained. The planned contract prepares package sources independently, selects
native `Dune` loading when the tree contains any Dune build file, and otherwise
selects a synthetic `Opam` stanza containing the complete recipe.

Add focused cases proving:

- mixed work, wrappers, separate install actions, depexts, and package
  declarations do not participate in selection;
- a tree with no Dune build file selects `Opam` independently of action syntax;
- an empty source-less package tree also selects `Opam`;
- a Dune file anywhere in the prepared tree selects native loading;
- Dune parsing/loading errors propagate instead of falling back to `Opam`;
- every currently supported source transport implements the common prepared
  source contract before its old `.pkg` source ownership is removed.

Current `extra-sources.t` already proves the observable patched result for an
extra-source package. Future extra-source preparation should produce one
immutable overlaid source target that either builder can consume rather than
remain a permanent routing exception.

#### Same-project package masking

Historical tests:

- `mounted-same-source-masking.t`;
- `mounted-same-source-mask.t`.

Current shared-source coverage places packages in separate root and nested
projects. The older tests place multiple selected packages in one
`dune-project`, sometimes with both libraries and a
`deprecated_library_name` stanza in one Dune file.

The current mask implementation is intended to support this, but the sharper
case should be retained. It also exercises package aliases and redirections
across separately mounted views of one source target.

#### Vendored formatting and warning behavior

Historical tests:

- `mounted-sources-vendored.t`;
- `mounted-vendored.t`;
- `e2e-vendored.t`.

Current tests prove vendored compiler flags and recursive `runtest` exclusion.
They do not directly prove that `dune fmt` avoids mounted files, nor every class
of Dune warning suppression. A focused formatting test is cheap and protects an
important ownership boundary.

#### Direct workspace execution of a mounted public binary

Historical test:

- `mounted-binary.t`.

Current tests cover a mounted package running another mounted executable and a
workspace using a mounted PPX. They do not directly cover an ordinary workspace
rule executing `%{bin:foo-tool}` from a mounted package.

#### Broader promotion behavior

Historical test:

- `mounted-promotions.t`.

Current coverage proves that a mounted promote rule generates an artifact
without changing fetched source, and that workspace promotion still works. It
does not retain the matrix for:

- `promote (until-clean)`;
- `promote (only ...)`;
- `copy_files` with promote mode;
- generated-only promotion targets;
- `dune build --promote`.

The old physical paths should not be copied, but the semantic matrix remains
useful.

#### Remaining focused gaps

Lower-priority archived cases without exact current equivalents include:

- `%{version:foo}` expansion and package-alias routing;
- fetched opam files combined with `(generate_opam_files true)`;
- mounted traversal diagnostics for directory symlink cycles;
- a workspace-only target being absent from the mounted output partition;
- one installed legacy cookie being loaded once across workspace and mounted
  consumers.

### Intentional scope differences

The following should be reported as prototype scope or policy differences, not
blindly restored as old tests.

#### Extra-source overlays

The archive mounted checksum-verified extra sources over the primary archive.
Current `Pkg_sources.prepare` explicitly routes every package with extra sources
to legacy rules. This avoids another source-ownership and overlay problem but
reduces native coverage.

The existing `extra-sources.t` proves the patched result under the current
legacy route. The planned common source layer instead needs a normal rule-owned
overlay target before native loading or the synthetic `Opam` stanza consumes the
source.

#### VCS and live directory sources

Current mounting supports local archive files and HTTP fetches. VCS sources,
live directories, and other fetch forms remain legacy. This is an explicit
transport limitation.

#### Mixed recipes with a selected Dune dependency

The archive's conservative action veto is intentionally retired. The presence
of any Dune build file selects native loading and supersedes the complete
recipe. A package that requires action-specific preparation or install layout
must express that requirement through its Dune files; recipe shape is not a
routing veto.

#### Virtual workspace collisions

The archive reserved `pkg/` and tested collisions with physical and synthetic
workspace directories. Current mounted sources have no virtual workspace path,
so those exact collisions no longer exist. The still-relevant assertion is that
ordinary workspace targets are not generated in the mounted output partition.

#### Source-claim repair

The archive tested re-creating an individually deleted source-claim target while
preserving generated siblings. Source claims were intentionally removed. A
current test should instead request the owning fetch directory or selected
artifact target and assert correct ordinary rule-graph repair.

## Rough implementation guide

This section records the broad sequence and API capabilities a future feature
implementor is likely to need. It intentionally avoids treating every current
module boundary as final.

### Start with independent identities

Keep these concerns independent from the first type design:

```text
lock universe and snapshot identity
exact package identity within that universe
decoded source-project identity
masked loaded-project identity
source owner and source location
explicitly anchored project-relative location
resolver/toolchain
artifact output root
visible package mask
permitted dependency capabilities
```

Do not reconstruct one from another. In particular:

- no virtual workspace path for fetched input;
- no artifact root derived from a source path;
- no library owner recovered from name plus directory;
- no context-name suffix used as the sole artifact authority;
- no package identity recovered by reversing a path.

### Keep separate engine and rules source views

The engine source view should continue to mean the watched workspace. It is used
for source-copy rules, fallback suppression, ordinary workspace loading, and
cleanup.

Rule loading needs a richer source view:

```text
Rules source view = workspace directories + build-backed directory targets
```

Only the rules-side abstraction should know whether enumeration and reads use
workspace filesystem APIs or build-system APIs.

### Rules-side source-tree capabilities

The current reference is `Source_tree.Rules`, but its full shape should not be
copied. The fundamental source-owner API is smaller than the eager prototype.

A directory value needs dependency-recording operations to:

- identify its logical location and owning root;
- enumerate visible files and subdirectories, forcing its producer when needed;
- descend without losing or escaping that owner;
- resolve a directory relative to an explicit project or source-root anchor;
- produce file values for ordinary loading and action dependencies.

A file value needs operations to:

- resolve an ordinary include while enforcing owner-root containment;
- read bytes with the correct workspace or build dependency;
- compare identity for include-cycle detection;
- report a stable diagnostic location;
- deny promotion by default unless it carries an explicit workspace promotion
  capability.

Raw `Path.t` access is an escape hatch for action inputs and working
directories, not the preferred read API. Reading or enumerating through it must
not bypass build dependencies.

Current reference operations include:

```text
Rules.Dir.source_path
Rules.Dir.path
Rules.Dir.file
Rules.Dir.relative_dir
Rules.Dir.filenames
Rules.Dir.sub_dirs / sub_dir_as_t
Rules.Dir.find_dir

Rules.File.source_path
Rules.File.path
Rules.File.relative
Rules.File.read
Rules.File.equal
Rules.File.diagnostic_name
Rules.File.include_context
```

The current `Rules.Dir.relative_dir` is relative to the workspace root for
workspace directories and to the fetched tree for build-backed directories. A
future API should name the anchor explicitly, especially across nested projects.
The current file representation preserves path kind but not a separate owner
root token, so containment also deserves an explicit design.

`Rules.Dir.status`, `project`, `dune_file`, and `Make_map_reduce` are useful
current operations, not fundamental source-owner capabilities. A production
design may keep decoded project and directory status in `Dune_load` or another
loaded-tree layer.

`Source_tree.Rules.Build.load` demonstrates the target-backed case. It uses
`Build_system.directory_target_contents` for topology and
`Build_system.read_file` for bytes, then eagerly loads nested projects and Dune
files. A production design should measure whether topology and decoding can
remain lazier without reintroducing repeated scans or loading cycles.

### Carry source and artifact ownership at the loading boundary

The semantic requirement is an ownership-capable source reference, an explicitly
anchored local directory, stable decoded and masked project identities, a
resolver/toolchain capability, and an artifact owner.

The current `Loaded_project`, `Loaded_dir`, and `Build_partition` modules are
useful references, but their exact fields are prototype shape. A final design
need not retain duplicate source roots, reverse source/output mappings, a
`purpose` enum, or an `implicit_workspace_targets` boolean if stronger types
express those capabilities directly.

What must not return is reconstructing output ownership or package identity from
a source path and context name.

### Prepare package sources before choosing builders

Create each immutable source directory target using only lock data and source
transport. The target must have an independent rule namespace such as `_fetch`.
Archive extraction, VCS checkout, local-source preparation, the lock package's
`files/` tree, and extra-source overlays must converge on this contract rather
than select a build backend themselves. Preserve the current order: primary
source, then `files/`, then each extra source at its declared path. All layers,
paths, and ordering participate in dependencies and source identity.

Use two explicit values in sequence:

```text
package node
  = lock universe + exact package + complete recipe
  + immutable prepared source directory target
  + dependency capabilities + artifact owner

builder
  = Dune of loaded Dune files
  | Opam of complete recorded recipe
```

Every package receives a prepared directory target, including an empty target
for a source-less package. Enumerate it through the rules-side `Source_tree`.
The presence of any Dune build file selects `Dune`; only the absence of all Dune
build files selects `Opam`. Do not inspect the lock recipe, dependency metadata,
package declarations, install layout, or system-provider metadata. External
tools remain resolver capabilities rather than builder outcomes. Once a Dune
file is found, all source, parsing, and loading failures propagate normally
rather than changing builders. Absence from a mounted list must not select or
publish either builder.

Package-node and memo keys must include the owning lock universe or snapshot
plus exact package identity. Fetch data may be shared by checksum, but builder,
artifact, and capability identities remain distinct when two lock universes
contain the same name and version.

### Load first, decide visibility later

Load the complete Dune-file universe without using package visibility to choose
the builder. Complete loading is needed for:

- nested projects;
- shared archives;
- package declarations and versions;
- aliases and redirects;
- Cram data directories;
- package-enabled conditions.

Package masks and auxiliary-project visibility are later in/out decisions. They
may be applied after decoding, but they must not turn a source containing Dune
files into an Opam build. Preserve the complete decoded universe now only where
that makes the ownership model simpler.

### Generate into an explicit artifact owner

A fetched directory target is opaque. Do not generate compilation artifacts
beneath it.

Generate ordinary stanza rules under the project's artifact partition. Use one
central source-selection policy so that:

- standard and contained promote rules may replace corresponding source input;
- an existing source suppresses a fallback rule;
- selectors and module discovery see the same selected source;
- only selected source inputs are materialized into artifact paths;
- no mounted source can become a promotion destination.

The current `Pkg_sources.add_artifact_source_rules` and
`Dune_engine.Source_selection` demonstrate the required behavior. Their exact
placement is prototype debt, not necessarily the final API.

### Represent opaque builds as an internal Opam stanza

A package that cannot use native loading should still be a package-owned rule
subtree, not a parallel source and routing system. Generate one internal
synthetic `Opam` stanza with this boundary:

```text
inputs
  = immutable prepared source directory target
  + exact recipe + dependency capabilities

opaque rule
  = copied source directory in a copy sandbox
  + recorded build/install actions

outputs
  = package-owned install-layout directory target + install cookie
```

The stanza owns its entire output subtree. It may invoke nested Dune, Make, or
shell commands, but it cannot write to `_fetch` and no other rule owns a target
inside its install-layout directory target. Its cookie remains the installation
trace for files and package variables.

Most execution semantics already exist in `Pkg_rules`: source preparation,
action expansion, dependency views, install actions, and install cookies. The
implementation should extract and host that machinery behind the stanza rather
than reinterpret arbitrary Opam actions or translate shell commands into native
Dune rules.

Keep this primitive internal until its ownership and dependency semantics are
stable. The plan does not require user-facing `(opam ...)` syntax.

Existing non-relocatable compiler packages can redirect their prefix to
`Path.Outside_build_dir`. Redesign that behavior before converting them: their
Opam stanza must install into its owned directory target and export toolchain
paths through package capabilities. There is no external-toolchain builder or
exception to output ownership.

### Introduce consumer-scoped capabilities early

For each package node, derive what its selected dependency branch permits it
to consume:

- target-package libraries and package variables;
- exported package executables, install roots, and environments;
- build/host dependencies used by generated actions and PPX drivers;
- ambient compiler and toolchain executables supplied by the resolver.

Do not collapse these into one package set. In particular, narrowing package
binaries must not hide the ambient compiler, while host actions must not see
unrelated target-context package binaries.

Pass these capabilities explicitly. Do not expose a global lock universe and
try to subtract unrelated packages later.

Keep three concepts distinct:

- project mask: which decoded stanzas survive;
- dependency capability: what those stanzas may consume;
- artifact owner: where their outputs are produced.

### Normalize native and Opam-builder interoperability

A native package receives ordinary stanza outputs and install metadata. An
Opam-built package receives an opaque install-layout target and cookie.
Consumers must use a normalized capability interface without pretending the
two builders have identical internal graphs.

Therefore model separately:

1. exact package dependency identity and selected builder;
2. concrete install environment and library/provider visibility.

The current `Pkg_rules.Dependency_view`, package-specific install layouts, and
lazy legacy library databases are references. Prove both consumption directions
and the complete native A -> Opam-built B -> workspace C composition before
generalizing this machinery.

### Preserve a workspace-only lock phase

Autolock requires two explicit loading phases in one invocation:

1. load only the workspace to generate or validate the lock;
2. read the resulting lock, prepare package sources, then select and instantiate
   package builders.

Lock generation must not force package roots whose existence depends on that
same lock.

### Suggested implementation sequence

The prototype already establishes target-backed native loading. Continue from
that foundation:

1. Write path-kind, owner-root, artifact-owner, and lock-universe invariants.
2. Introduce one exact package-node value without choosing a builder by absence.
3. Produce one immutable prepared source directory target, possibly empty, for
   every package and supported transport.
4. Preserve primary, lock `files/`, and extra-source overlay ordering in that
   target, with identity and invalidation tests.
5. Select `Dune` when source enumeration finds any Dune build file and `Opam`
   only when it finds none; propagate all loading errors.
6. Extract the existing action expander, install action, cookie, and dependency
   view behind one internal synthetic `Opam` stanza.
7. Give the stanza a copy-sandbox source dependency and one package-owned
   install-layout directory target.
8. Normalize consumer-scoped library, binary, variable, PPX, host, and
   environment capabilities across both builders.
9. Prove native-to-Opam and Opam-to-native dependency edges.
10. Port the exact native A -> Opam-built B -> workspace C composition.
11. Redesign non-relocatable toolchain installs to remain in stanza-owned
    output.
12. Remove recipe-shape routing, mounted-list absence checks, and obsolete
    parallel `.pkg` source/build ownership only after all existing sources and
    toolchain cases have replacements.
13. Add generated-over-source, fallback, selectors, and promotion containment.
14. Add autolock, source refresh, retry, stale removal, and watch invalidation.
15. Retain the complete decoded universe if useful, but defer all auxiliary
    nested-project visibility semantics to in/out work.
16. Port the remaining historical behavior matrix.
17. Exercise `ocaml-re`, then `ocaml-cohttp` through both applicable builders.
18. Measure successful clean and warm builds separately.
19. Simplify interfaces only after the behavioral boundary is stable.

### Verification milestones

The native vertical milestone should prove:

- source topology and bytes depend on a real fetch directory target;
- source and artifact roots have separate rule ownership;
- a native library compiles and links in the current process;
- the artifact exists only beneath its explicit package output root;
- no nested Dune process builds the package;
- no old `.pkg` target, cookie, or action exists;
- direct artifact targets work after clean;
- workspace loading remains unchanged;
- the engine has no package source registry or redirection callback.

The builder-unification milestone should additionally prove:

- every package has an immutable prepared source directory target, possibly
  empty;
- prepared targets preserve lock `files/` and extra-source overlay semantics;
- an Opam stanza's copy sandbox cannot mutate the prepared source;
- it owns one install-layout directory target and install cookie;
- direct cookie and install-layout targets work after clean;
- native and Opam-built packages consume each other through scoped capabilities;
- only Dune-file presence selects the builder, and loading errors propagate;
- external toolchain installs do not escape claimed stanza ownership.

Later milestones should add focused tests for:

- source/generated/fallback precedence;
- complete package masks, with auxiliary nested visibility deferred to in/out;
- native/Opam-builder chains in both directions;
- public binary and PPX lookup;
- exact locked compiler and version behavior;
- autolock and watch mode;
- refresh, retry, removed files, and no-change reuse;
- same-name packages across lock universes;
- promotion and formatting isolation;
- real package graphs.

Use the fully built Dune executable for end-to-end checks. Trace assertions
about process execution require a fresh action cache. Do not compare a failed
replay with a successful null build.

### Mechanisms not to copy

Do not reintroduce:

- virtual `Path.Source.t` identities for fetched targets;
- virtual-to-real source lookup;
- mounted branches in engine copying, lookup, selectors, fallback handling,
  cleanup, or promotion;
- source and generated artifact co-location;
- build-start synchronization into the artifact root;
- synthetic source-claim rules;
- external source snapshot stores or manifests;
- mutable process-global mount publication;
- reverse path-to-package or path-to-context registries;
- a generic rule that interprets arbitrary `Path.Build.t` as source;
- an Opam action writing directly into an immutable prepared source;
- a parallel `.pkg` source/build system selected by absence from native loading;
- a second semantic workspace context;
- context-name suffixes as the sole artifact authority;
- nested Dune execution or an Opam stanza for a package selected for native
  loading;
- compatibility shims whose only purpose is preserving an incorrect
  `Path.Source.t` API.

## Current prototype debt

The current code should be treated as evidence, not polished production design.
Known broad areas for cleanup include:

- `Source_path.t` is visible to many callers; ownership dispatch should ideally
  remain concentrated in the rules-side source API.
- Build-backed file relatives preserve path kind but do not carry an explicit
  owner-root token or containment proof.
- Mounted conditionals remain in `Gen_rules`, `Dune_file`, `Scope`,
  `Super_context`, install rules, PPX handling, and other consumers.
- `Mounted_context` still encodes physical routing in a context-name suffix.
- The mounted package list represents only one route; legacy is often inferred
  by absence and rechecked by name and digest.
- Existing package source preparation separately layers primary sources, lock
  `files/`, and extra sources rather than producing one shared immutable target.
- Non-relocatable compiler packages may install into an external toolchain
  prefix, outside the proposed Opam stanza's directory-target ownership.
- `Source_tree.Rules.Build.load` recursively enumerates and parses the complete
  build-backed tree.
- Promotion eligibility is not a first-class file capability.
- Source selection still accepts raw paths and is attached in `Pkg_sources`.
- Some install-layout integration uses callbacks and process-local reverse
  tables.
- Mounted lookup paths and exported environments require further performance
  measurement.
- `Pkg_sources.find_mounted` remains a linear lookup.
- Broad `Vendored` status currently conflates mounted-root behavior with an
  explicit `(vendored_dirs ...)` declaration. The paused Menhir experiment
  exposed this distinction.
- Recipe-shape routing and `different-dune-in-path.t` do not yet implement the
  chosen native-first builder model.
- Several large cram tests should be split back into focused regressions.

These are reasons to redesign interfaces before productionizing the feature,
not reasons to discard the target-backed model.

## Recommended next steps

1. Introduce the exact package node and one immutable prepared source directory
   target, possibly empty, for every package.
2. Move every supported transport, lock `files/`, and extra-source overlay onto
   that common target contract.
3. Select `Dune` solely when source enumeration finds a Dune build file and
   `Opam` otherwise, with loading errors propagated normally.
4. Extract one internal Opam stanza from the existing package action, install,
   cookie, and dependency machinery.
5. Make it consume the prepared source in a copy sandbox and own one
   install-layout directory target.
6. Add the source-only builder-selection matrix, proving that recipes and
   package declarations are irrelevant.
7. Port the exact native A -> Opam-built B -> workspace C composition.
8. Redesign non-relocatable compiler/toolchain installs to remain in
   stanza-owned output.
9. Remove the old parallel package path only after all source and toolchain
   cases have replacement coverage.
10. Add direct workspace `%{bin:...}` coverage for a native package executable.
11. Add the one-project shared-source mask, redirects, and package aliases.
12. Port refresh/retry behavior without restoring manifests or source claims.
13. Add cross-lock digest identity and lock-selected compiler provenance, with a
    separate small configurator metadata test.
14. Preserve the complete decoded universe if useful, but defer all auxiliary
    nested-project visibility semantics to in/out work.
15. Add smaller ownership regressions for `dune fmt`, Dune warnings, version
    pforms, generated opam files, workspace-target isolation, and symlink
    cycles.
16. Add the broader promotion matrix after builder ownership is stable.
17. Run a successful clean `ocaml-cohttp` build with the new
    `materialize-dependencies` span and attribute sandbox creation precisely.
18. Compare identical successful clean and warm workloads under Opam and native
    builders.
19. Only then decide whether source materialization or scheduling needs another
    architectural change.
20. Turn the broad guide above into a smaller feature design with explicit
    module ownership and migration boundaries.

## Bottom line

The previous prototypes proved the behavior was possible. Their post-mortem
identified that virtual workspace paths were the wrong representation. The
current prototype validates the replacement: target-backed source trees can be
loaded through a rules-side API while the engine remains workspace-only and
artifacts retain separate ownership.

Building `ocaml-re` and `ocaml-cohttp` is a substantial success. The remaining
work is not to return to the old architecture, but to unify native and opaque
package builders around prepared sources and explicit output ownership, restore
the useful missing fixtures, measure the full-build path with narrow events, and
turn the broad prototype migration into a smaller, reviewable feature design.
