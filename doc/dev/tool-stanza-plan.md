# Tool Stanza Implementation Plan

## Overview

This document outlines the plan to overhaul dune's developer tools system to support arbitrary opam packages as tools via a new `(tool)` stanza in `dune-workspace`.

## Goals

1. Support **any** opam package as a tool (not just 10 hardcoded ones)
2. Add `(tool)` stanza to dune-workspace for configuration
3. Scope tools per dune-project
4. Store tools project-locally in `_build/default/.tools/`
5. Match compiler constraints from dune_rules (pkg or system)
6. Decouple from package management while reusing per-tool lock directories

---

## Current Status

### Working ✅

1. **Tool stanza parsing**: `(tool (package ocamlformat))` works in dune-workspace
2. **CLI commands**: `dune tools lock <pkg>`, `dune tools run <pkg>`, `dune tools path <pkg>`
3. **Lock directory creation**: `.tools.lock/<package>/` created correctly
4. **Compiler detection**: System OCaml version detected via `Sys_vars.poll.sys_ocaml_version`
5. **Fs_memo tracking**: Lock directory existence tracked properly for memo invalidation
6. **Checksum collection**: Tool lock dirs included in fetch rules checksum map
7. **`.pkg/` rules always generated**: No longer gated by `lock_dir_active`

### In Progress 🔄

1. **System OCaml preference**: Changed to require `ocaml-system` directly instead of `ocaml`
2. **Build system isolation**: `compiler_package_opt()` now reads from disk directly to avoid triggering builds

### Blocked/Issues 🔴

1. **Internal error on lock**: "Unexpected build progress state" when calling lock - may be related to how memo/fiber interact with the scheduler

---

## Key Lessons Learned

### 1. Avoid Build System Triggers in Lock Commands

**Problem**: `Lock_tool.lock_tool` was calling `Lock_dir.get context` which triggers the build system to load the project lock dir.

**Solution**: Read lock dir directly from disk using `Lock_dir.read_disk` instead of going through the memo system.

```ocaml
(* BAD - triggers build system *)
let* result = Dune_rules.Lock_dir.get context in

(* GOOD - reads directly from disk *)
let lock_dir_path = Path.source (Path.Source.relative workspace.dir "dune.lock") in
match Lock_dir.read_disk lock_dir_path with
```

### 2. Use Fs_memo for Tracked Filesystem Operations

**Problem**: `Path.Untracked.exists` doesn't invalidate memos when files change.

**Solution**: Use `Fs_memo.dir_exists` for any filesystem check that affects memoized computations.

```ocaml
(* BAD - untracked *)
Path.Untracked.exists (Path.external_ dir)

(* GOOD - tracked *)
Fs_memo.dir_exists (Path.Outside_build_dir.External path)
```

### 3. Checksum Collection Must Include All Lock Dirs

**Problem**: Fetch rules only collected checksums from dev tools and project lock dirs, not generic tools.

**Solution**: Added scanning of `.tools.lock/` directory in `fetch_rules.ml`:

```ocaml
(* Scan .tools.lock/ for generic tool lock dirs *)
let* init =
  match Path.Untracked.readdir_unsorted_with_kinds tools_lock_path with
  | Error _ -> Memo.return init
  | Ok entries -> ...
```

### 4. `.pkg/` Rules Should Always Generate

**Problem**: `.pkg/` rules were gated by `lock_dir_active`, which fails when only tools (not project) have dependencies.

**Solution**: Always generate `.pkg/` rules. When no project lock dir exists, create a tools-only DB:

```ocaml
if lock_dir_active then DB.of_ctx ctx ~allow_sharing:true
else
  (* Create DB from just tool packages *)
  let+ dev_tools_table = Memo.Lazy.force DB.Pkg_table.all_existing_dev_tools
  and+ tools_table = Memo.Lazy.force DB.Pkg_table.all_existing_tools in
  DB.create ~pkg_digest_table:(DB.Pkg_table.union dev_tools_table tools_table) ...
```

### 5. System OCaml Requires `ocaml-system` Package

**Problem**: Constraining `ocaml = 5.4.0` allows solver to pick `ocaml-base-compiler` instead of using system.

**Solution**: Require `ocaml-system` explicitly when system OCaml is available:

```ocaml
[ { Package_dependency.name = Package_name.of_string "ocaml-system"; constraint_ } ]
```

### 6. Lock Command Should Always Re-solve

**Problem**: `dune tools add` was checking if lock dir exists and skipping solve.

**Solution**: `dune tools lock` always re-solves (like `dune pkg lock`). Separate `lock_tool` and `lock_tool_if_needed`:

```ocaml
(* For explicit lock command - always re-solve *)
val lock_tool : Package_name.t -> unit Memo.t

(* For run command - only lock if missing *)
val lock_tool_if_needed : Package_name.t -> unit Memo.t
```

---

## Architecture Decisions

### Lock Directory Location

| Type | External (Source) | Internal (Build) |
|------|------------------|------------------|
| Project | `dune.lock/` | `_build/default/.lock/dune.lock/` |
| Dev tools | `_build/.dev-tools.locks/<pkg>/` | `_build/default/.dev-tool-locks/<pkg>/` |
| Generic tools | `_build/.tools.lock/<pkg>/` | `_build/default/.tool-locks/<pkg>/` |

Copy rules move from external to internal location.

### CLI Commands

```bash
# Lock a tool (always re-solves)
dune tools lock <package>

# Run a tool (locks if needed, then builds and executes)
dune tools run <package> [-- args]

# Print tool executable path
dune tools path <package>

# Legacy dev tool commands still available
dune tools exec ocamlformat
dune tools install odoc
```

### Compiler Constraints

1. **Project has lock dir with compiler**: Use that exact compiler version
2. **No project lock dir, system OCaml available**: Require `ocaml-system` at system version
3. **Neither**: No compiler constraints (solver picks freely)

### Multiple Versions

**Target**: Version in lock dir path.

```
_build/.tools.lock/<package>/<version>/
_build/.tools.lock/ocamlformat/0.26.2/
_build/.tools.lock/ocamlformat/0.27.0/
```

**Implementation challenge**: The solver (`Pkg.Lock.solve`) takes the lock dir path upfront, but we don't know the version until after solving.

**Solution options**:
1. **Two-phase**: Solve to temp location, read version from result, move to final path
2. **Callback**: Pass a function `version -> path` to solver, called after resolution
3. **Return-then-write**: Have solver return solution without writing, caller writes to versioned path

**Current implementation**: One version per package (`_build/.tools.lock/<package>/`). Marked as TODO.

**CLI support added**: `dune tools lock <pkg> --version <ver>` (constraint passed to solver)

### Binary Discovery

Package names and binary names are not 1-to-1. After building a package, we discover available binaries:

1. **Single binary**: Use automatically (e.g., `ocamlformat` package → `ocamlformat` binary)
2. **Multiple binaries**: Require `--bin <name>` flag to disambiguate
3. **Binary location**: Check `<install_path>/bin/` for available executables

```bash
# Single binary - works automatically
dune tools run ocamlformat

# Multiple binaries - need to specify
dune tools run menhir --bin menhir
dune tools run menhir --bin menhirLib  # error: not a binary

# Stanza can specify default
(tool (package menhir) (executable menhir))
```

The `(executable ...)` field in `(tool)` stanza provides a default when the package has multiple binaries.

---

## Remaining Work

### High Priority

1. **Fix internal error on lock**: Investigate "Unexpected build progress state" error
   - May need different scheduler invocation for lock-only operation
   - Compare with how `dune pkg lock` is invoked

2. **Test tool building end-to-end**: Once lock works, verify dependencies build correctly

### Medium Priority

3. **Migration from dev tools**: Helper to migrate `.dev-tools.locks/` to `.tools.lock/`

4. **Test compiler matching**: Verify tools work when project has lock dir with specific compiler

### Low Priority

5. **Performance**: Consider caching tool builds across projects

6. **Documentation**: User-facing docs for `(tool)` stanza

---

## Files Modified

### Core Changes

| File | Changes |
|------|---------|
| `bin/lock_tool.ml` | Simplified locking, system OCaml detection, avoid build triggers |
| `bin/lock_tool.mli` | Added `lock_tool_if_needed` |
| `bin/tools/tools_common.ml` | CLI terms, use `lock_tool_if_needed` for run |
| `bin/tools/group.ml` | Simplified CLI (removed `add`, kept `lock`) |
| `src/dune_rules/pkg_rules.ml` | Always generate `.pkg/` rules, tools-only DB |
| `src/dune_rules/fetch_rules.ml` | Include tool lock dirs in checksum collection |
| `src/dune_rules/lock_dir.ml` | Use `Fs_memo` instead of `Path.Untracked` |

### New Modules

| File | Purpose |
|------|---------|
| `src/source/tool_stanza.ml` | `(tool)` stanza parsing |
| `src/dune_rules/tool_lock.ml` | Lock directory management |
| `src/dune_rules/tool_compiler.ml` | Compiler detection |
| `src/dune_rules/tool_build.ml` | Build paths and environment |
| `src/dune_rules/tool_resolution.ml` | Unified resolution |

---

## Next Steps

1. Debug the internal error when running `dune tools lock`
2. Compare invocation pattern with `dune pkg lock`
3. Once locking works, test full build cycle
4. Add cram tests for tool stanza functionality
