Building at a VCS Revision (`--rev`)
====================================

`dune build --rev <rev>` (also `--rev`/`-r` on `runtest`, `exec`)
builds the current project at a specific VCS revision without
disturbing the working tree. The flag is repeatable; each occurrence
is passed verbatim to the backend's revset resolver, so single shas,
ranges (`HEAD~3..HEAD`), and richer revsets all expand uniformly.

This document records the design and the performance characteristics
observed on a multi-rev build of dune against itself.


User Model
----------

```
$ dune build -r HEAD                     # 1 context
$ dune build -r HEAD -r HEAD~1 @fmt      # 2 contexts in parallel
$ dune build -r HEAD~5..HEAD @check      # 6 contexts (revset expansion)
```

Each resolved rev becomes an independent user-facing context named
`default-<short-sha>`, with its own build dir
`_build/default-<short-sha>/`. The regular `_build/default/` and the
working tree are untouched. Contexts are isolated from each other:
there is no cross-rev resolution of libraries, binaries, packages,
etc. (contrast with `(mount ...)` whose internal contexts ARE
siblings of the same user-facing context).

Specifically, the user's working tree is **not scanned at all** when
`--rev` is in effect — locked in by
`test/blackbox-tests/test-cases/build-rev/no-worktree-scan.t`. A
later `--worktree` flag may opt in to building the working tree as an
additional context alongside the revs.


Architecture
------------

```
$ dune build -r <rev>
    │
    ▼
bin/revs.ml: Vcs.find_repo_root + Vcs_tree.resolve_set
    │   expands revsets and dedups by content sha
    ▼
Workspace.set_synthesised_for_revs       (one-shot hook)
    │
    ▼
Workspace.workspace ()
    │   when the hook is populated, synthesises a Workspace.t with
    │   one Context.Default per rev, each carrying a vcs_tree on
    │   its Common.t base. The on-disk dune-workspace is ignored
    │   under --rev; the user's --config-file and CLI config still
    │   apply (so the shared cache stays on).
    ▼
Context.build_contexts
    │   emits one Build_context.t per rev with a Vcs_rev source
    ▼
main.ml: source_tree_of_context dispatches
    │   Vcs_rev vcs_tree → Source_tree.of_vcs_tree vcs_tree
    ▼
Source_tree.of_vcs_tree
    │   - directory enumeration via Vcs_tree.list_dir
    │   - file bytes via Vcs_tree.read_file (Memo'd closures)
    │   - read_only:true (promotion blocked) but vendored:false
    │     (rules generate normally)
    ▼
Engine consumes the Source_tree.t as usual
    │   Source_tree.Dir.file_source returns
    │   Build_config.Vcs_blob (string Memo.t) instead of a
    │   filesystem path; Load_rules.copy_source_action emits
    │   Action.Write_file with the bytes from the Memo. No
    │   source-side disk staging.
```

The current Git backend reads via `git rev-parse`, `git rev-list`,
`git ls-tree -r`, and `git cat-file blob <sha>:<path>` (one shell-out
per file read). Hg and Jj backends are stubbed for now.


Key files
---------

| File | Role |
|---|---|
| `src/dune_vcs/vcs_tree.ml(i)` | Backend-agnostic [t]; resolve_set/list_dir/read_file/blob_sha |
| `src/dune_vcs/git_subprocess.ml(i)` | git rev-parse / rev-list / ls-tree / cat-file wrappers |
| `src/dune_vcs/vcs.ml(i)` | Vcs.Kind + find_repo_root ancestor walker |
| `src/source/source_tree.ml(i)` | of_vcs_tree, vcs_backing, Dir.file_source |
| `src/source/workspace.ml(i)` | synthesise_for_revs, set_synthesised_for_revs hook, Build_context_source.Vcs_rev, Context.Common.vcs_tree |
| `src/dune_engine/build_config.ml(i)` | source_file = Filesystem \| Vcs_blob neutral variant |
| `src/dune_engine/load_rules.ml` | copy_source_action branches on source_file |
| `src/dune_rules/main.ml` | source_tree_of_context: Vcs_rev → Source_tree.of_vcs_tree; promote_source rejection on read_only |
| `bin/revs.ml`, `bin/common.ml` | CLI: --rev/-r flag, rev resolution + dedup |


Performance Observations
------------------------

Measured on a `dune build -r main..HEAD @check` against the dune
codebase itself: 38 revisions in the range, ~382s wall time, ~728s
total subprocess CPU (about 1.9× parallelism).

### Event counts

| Category | Count | Notes |
|---|---|---|
| `process start/finish` | 137,915 / 137,897 | One pair per subprocess fork |
| `process signal_received` | 130,689 | SIGCHLD wait events |
| `log info` ("cache store success") | 134,353 | Cache populated; **no hit events seen** |
| `action write-file` | 82,936 | Source-file copies (Vcs_blob → build dir) |
| `action start/finish` (user rules) | 4,417 / 4,417 | ocamldep, copy-line-directive, etc. |
| `sandbox create/extract/destroy` | 342 each | Modest |
| `rules Dune load` | 38 | One per context, ~7s each, runs in parallel |
| `rules Source deps` | 152 | |

### CPU by subprocess command

| Cmd | CPU | Calls | per call |
|---|---|---|---|
| `ocamldep.opt -modules` | **405.5s** | 46,941 | 8.6ms |
| `git cat-file blob` | **314.3s** | 90,802 | **3.5ms** |
| `ocaml gen_c_flags.ml` | 4.1s | 38 | 108ms |
| `ocaml c_flags.ml` | 3.3s | 38 | 87ms |
| `git ls-tree -r <sha>` | 0.6s | 38 | 16ms |
| `ocamlc.opt -config` | 0.2s | 38 | 6ms |
| **Total subprocess CPU** | **728s** | 137,897 | |

### Cache state

`Shared cache enabled` at `~/.cache/dune/db`; 134,353 store events;
**zero hit events visible** in the trace. Either hits aren't logged
in this trace mode, or genuinely no hits across the 38 revs — worth
chasing under `DUNE_TRACE=cache` on a smaller repro to confirm. The
small-test `build-rev/cache-share.t` does show working cache sharing
via hardlink counts, so the machinery works in principle; the
question is whether something rev-specific leaks into trace digests
on real builds.

### Bottleneck story

1. **`git cat-file` fork-storm is the smoking gun for vcs-backed
   builds.** 91k forks at 3.5ms each = 314s CPU. Each file in each
   rev shells out git once.

2. **`ocamldep` accounts for the most CPU (405s).** This is dune
   doing its normal job; the relevant question is whether the shared
   cache should be reusing this work across revs. With 38 incremental
   commits of the same project, many .ml/.mli files are byte-identical
   between adjacent revs and should hit the cache.

3. **`Dune load` runs once per context** (~7s each, 38 concurrent).
   Total CPU 270s but wall-clock ~7s. Acceptable as-is; would
   benefit from content-addressed dune-file ASTs (a much bigger
   change).

4. **Sandboxing is cheap.**


Optimisation Opportunities
--------------------------

Ranked by estimated impact.

### 1. Batch `git cat-file` with `--batch` mode

Replace 91k individual `git cat-file blob <sha>:<path>` invocations
with one long-lived `git cat-file --batch` process per build that
reads `(sha:path)` pairs from stdin and writes `<header>\n<bytes>\n`
on stdout. **Estimated saving: ~250s CPU** (most of the file-read
overhead, leaving just `read` + parsing).

Implementation lives in `Git_subprocess`: replace `cat_file_blob`'s
per-call `Process.run_capture` with a persistent process spawned on
first use, with a mutex-guarded read loop. Hg and Jj have analogous
batch facilities (`hg cat` accepts multiple paths per invocation;
`jj` delegates to git anyway).

### 2. Memoise `Vcs_tree.read_file` by blob sha

Right now each rev's tree has its own `read_file` closure keyed by
`Path.Source.t`. Two revs that contain a byte-identical file have
distinct closures and distinct Memo entries. Switch the in-memory
cache key to the **git blob sha** (already in `t.blob_shas`) so the
same content across revs is read at most once. Cheap fix; pairs
naturally with batching.

### 3. Investigate the zero-cache-hit anomaly

The trace shows 134k cache stores and 0 hits across 38 commits of
the same project. The small cram test
(`build-rev/cache-share.t`) proves the cache machinery works when
inputs are truly identical — so either:

- Hit events aren't emitted unless `DUNE_TRACE=cache` is set.
- The trace digest is being polluted by something rev-specific
  (the synthesised context name? the build path? the Vcs_blob
  Memo's reproducibility tag?) and breaking cross-rev sharing.

Worth a focused investigation under `DUNE_TRACE=cache` + a 2-rev
repro that's known to have identical compile inputs.

### 4. Deduplicate `Dune load` across rev contexts

`Dune_load.load_for_context_impl` walks each context's source tree
separately. For 38 revs of the same project with mostly unchanged
dune files, this is wasted CPU. A future refactor could
content-address dune-file ASTs and let load reuse across contexts
whose dune-files have identical hashes. Lower priority than the
above; would also benefit the regular workspace + mounts case.


Open Limitations
----------------

- **`(include ...)` stanzas don't work for vcs-backed trees yet.**
  `Include_stanza` still routes through `Fs_memo.with_lexbuf_from_file`
  + the resolver, which produces synthetic paths that don't exist on
  disk. Vcs builds that hit an include error with "file doesn't
  exist."

- **`(deps (glob_files ...))` runtime globbing.**
  `dep_conf_eval.dir_contents` calls `Fs_memo.dir_contents` for
  glob expansion; this fails for vcs-backed trees. Would need a
  backing-aware variant.

- **OCaml-script dune files (`(jbuild_plugin)`).**
  `dune_file.ml:create_plugin_wrapper` reads the plugin source via
  `Fs_memo.file_contents`. Out of scope for v1; rare in practice.

- **Hg and Jj backends.** Stubbed; the abstraction shape is in
  place but only Git is implemented.

- **No `--worktree` flag yet.** Future work to opt into building
  the working tree as an additional context when `--rev` is in
  effect.

- **No remote-fetched `-r` yet.** `--rev` reads the user's local
  `.git`; building at a rev not present in the local repo would
  need to integrate with `Rev_store`'s remote fetching machinery.
