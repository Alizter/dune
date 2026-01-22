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
2. **CLI commands**: `dune tools lock <pkg>`, `dune tools run <pkg>`, `dune tools which <pkg>`
3. **Versioned lock directories**: `.tools.lock/<package>/<version>/` structure implemented
4. **Compiler detection**: System OCaml version detected via `Sys_vars.poll.sys_ocaml_version`
5. **Fs_memo tracking**: Lock directory existence tracked properly for memo invalidation
6. **Checksum collection**: Tool lock dirs included in fetch rules checksum map
7. **`.pkg/` rules always generated**: No longer gated by `lock_dir_active`
8. **System OCaml preference**: Requires `ocaml-system` when system OCaml is available
9. **Build system isolation**: `compiler_package_opt()` reads from disk directly to avoid triggering builds
10. **Version selection**: 0 versions → error, 1 version → auto-select, N versions → error
11. **Binary discovery**: Auto-detect binaries from install cookie's `Section.Bin`
12. **Build dependency via cookie**: Depend on `target/cookie` to ensure package is built before accessing binaries

### In Progress 🔄

1. **Add `--bin` flag**: When multiple binaries exist, require explicit selection
2. **End-to-end testing**: Verify full lock → build → run cycle works

### Blocked/Issues 🔴

1. **Internal error on lock**: "Unexpected build progress state" when calling lock - may be related to how memo/fiber interact with the scheduler (needs investigation)

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

### 7. Directory Targets - Depend on Cookie, Not Files Inside

**Problem**: Depending directly on `_build/default/.tools/<pkg>/<ver>/target/bin/<exe>` fails because it's inside a directory target. Dune's error: "This rule defines a directory target... but the rule's action didn't produce it".

**Solution**: Depend on the install cookie (`target/cookie`) instead. The cookie is created when the package is fully installed, so depending on it ensures:
1. The package is fully built
2. All files in `target/` are available
3. We can then read the cookie to discover available binaries

```ocaml
(* BAD - depends on file inside directory target *)
let exe_path = Tool_build.exe_path ~package_name ~version ~executable in
Action_builder.path (Path.build exe_path)

(* GOOD - depend on cookie, then discover binaries *)
let cookie_path = Tool_build.install_cookie ~package_name ~version in
let+ () = Action_builder.path (Path.build cookie_path) in
(* Now safe to read cookie and access files *)
let exe = Tool_build.select_executable ~package_name ~version ~executable_opt:None in
Tool_build.exe_path ~package_name ~version ~executable:exe
```

### 8. Binary Discovery from Install Cookie

**Problem**: Package name doesn't always match binary name (e.g., `menhir` package installs `menhir` and potentially other binaries).

**Solution**: After building, read installed binaries from the install cookie's `Section.Bin`:

```ocaml
let read_binaries_from_cookie ~package_name ~version =
  let cookie_path = Path.build (install_cookie ~package_name ~version) in
  let cookie = Pkg_rules.Install_cookie.load_exn cookie_path in
  let files = Pkg_rules.Install_cookie.files cookie in
  match Section.Map.find files Bin with
  | None -> []
  | Some paths -> List.map paths ~f:Path.basename

let select_executable ~package_name ~version ~executable_opt =
  let binaries = read_binaries_from_cookie ~package_name ~version in
  match executable_opt, binaries with
  | Some exe, _ -> exe                   (* Explicit choice *)
  | None, [] -> error "no binaries"
  | None, [ single ] -> single           (* Auto-select singleton *)
  | None, multiple -> error "specify --bin"
```

### 9. Expose Install_cookie in pkg_rules.mli

**Problem**: `Pkg_rules.Install_cookie` wasn't exposed, causing "Unbound module" errors.

**Solution**: Add to `pkg_rules.mli`:

```ocaml
module Install_cookie : sig
  type t
  val load_exn : Path.t -> t
  val files : t -> Path.t list Section.Map.t
end
```

### 10. Path.rm_rf Requires Path.Build for Build Directory Paths

**Problem**: `Path.rm_rf (Path.external_ some_path)` fails when the path is inside `_build/` because it's technically a build path, not an external path.

**Solution**: For paths inside `_build/`, construct as `Path.Build` then convert:

```ocaml
(* BAD - external path for _build/ directory *)
let final_path = Path.External.relative external_root ".tools.lock/..." in
Path.rm_rf (Path.external_ final_path)

(* GOOD - use Path.Build for _build/ paths *)
let final_build_path =
  Path.Build.L.relative Path.Build.root [ ".tools.lock"; package; version ]
in
Path.rm_rf (Path.build final_build_path)
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

### Multiple Versions ✅

**Implemented**: Version in lock dir path.

```
_build/.tools.lock/<package>/<version>/
_build/.tools.lock/ocamlformat/0.26.2/
_build/.tools.lock/ocamlformat/0.27.0/
```

**Implementation**:
1. Solve to temp location (`.tools.lock/.solving/`)
2. Read solved lock dir, extract tool version from packages
3. Move to final versioned path using `Unix.rename`

**Files updated for versioned paths**:
- `lock_tool.ml:solve` - solves to temp, moves to versioned path
- `lock_dir.ml` - `tool_external_lock_dir` and `tool_lock_dir` require `~version`
- `lock_dir.ml` - `tool_locked_versions` scans for all versions
- `pkg_rules.ml` - `Package_universe.Tool` includes version, rule generation handles versioned paths
- `fetch_rules.ml` - checksum collection scans versioned structure
- `lock_rules.ml` - copy rules iterate over all package/version pairs
- `tool_lock.ml` - updated for versioned external/build paths
- `tool_build.ml` - install paths include version
- `tool_resolution.ml` - resolves version (0→error, 1→use it, N→error)
- `tools_common.ml` - CLI commands handle versioned paths

**Run command logic**:
```
If 0 versions locked → error
If 1 version locked → use it automatically
If N versions locked → error (user must specify --version)
```

**CLI**: `dune tools lock <pkg> --ver <version>` passes constraint to solver

### Binary Discovery ✅

Package names and binary names are not 1-to-1. After building a package, we discover available binaries from the install cookie:

**Implementation**:
1. Depend on `target/cookie` to ensure package is built
2. Read `Pkg_rules.Install_cookie.files cookie`
3. Look up `Section.Bin` to get list of installed binaries
4. Auto-select if single binary, error if multiple

```ocaml
(* In tool_build.ml *)
let select_executable ~package_name ~version ~executable_opt =
  let binaries = read_binaries_from_cookie ~package_name ~version in
  match executable_opt, binaries with
  | Some exe, _ -> exe
  | None, [] -> error "no binaries"
  | None, [ single ] -> single
  | None, multiple -> error "specify --bin"
```

**CLI behavior**:
```bash
# Single binary - works automatically
dune tools run ocamlformat

# Multiple binaries - need to specify (TODO: add --bin flag)
dune tools run menhir --bin menhir

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

2. **Add `--bin <name>` flag**: For packages with multiple binaries, allow explicit selection
   - Add to `dune tools run` and `dune tools which` commands
   - Integrate with `Tool_build.select_executable`

3. **End-to-end testing**: Create cram tests for:
   - `dune tools lock <pkg>` → creates versioned lock dir
   - `dune tools run <pkg>` → builds and runs
   - `dune tools which <pkg>` → shows path after build
   - Multiple versions coexisting
   - Binary discovery (single and multiple)

### Medium Priority

4. **`--ver` flag for run**: Allow `dune tools run <pkg> --ver <ver>` when multiple versions locked

5. **Migration from dev tools**: Helper to migrate `.dev-tools.locks/` to `.tools.lock/`

6. **Test compiler matching**: Verify tools work when project has lock dir with specific compiler

### Low Priority

7. **Performance**: Consider caching tool builds across projects

8. **Documentation**: User-facing docs for `(tool)` stanza

---

## Files Modified

### Core Changes

| File | Changes |
|------|---------|
| `bin/lock_tool.ml` | Versioned solve (temp→final), system OCaml detection, avoid build triggers |
| `bin/lock_tool.mli` | Added `lock_tool_if_needed` |
| `bin/tools/tools_common.ml` | CLI with version handling, cookie-based build targets, binary discovery |
| `bin/tools/group.ml` | Simplified CLI (removed `add`, kept `lock`) |
| `src/dune_rules/pkg_rules.ml` | `Package_universe.Tool` with version, `Install_cookie.files` exposed |
| `src/dune_rules/pkg_rules.mli` | Exposed `Install_cookie` module with `files` accessor |
| `src/dune_rules/fetch_rules.ml` | Scan versioned tool lock dirs for checksums |
| `src/dune_rules/lock_dir.ml` | Versioned paths, `tool_locked_versions` scanner |
| `src/dune_rules/lock_dir.mli` | Updated signatures for versioned paths |
| `src/dune_rules/lock_rules.ml` | Copy rules iterate over package/version pairs |

### New Modules

| File | Purpose |
|------|---------|
| `src/source/tool_stanza.ml` | `(tool)` stanza parsing |
| `src/dune_rules/tool_lock.ml` | Lock directory management with version support |
| `src/dune_rules/tool_compiler.ml` | Compiler detection |
| `src/dune_rules/tool_build.ml` | Versioned build paths, cookie reading, binary selection |
| `src/dune_rules/tool_resolution.ml` | Unified resolution with version selection |

---

## Next Steps

1. **Add `--bin` flag to CLI**: Allow explicit binary selection for packages with multiple executables
   - Add to `generic_exec_term` and `generic_which_term` in `tools_common.ml`
   - Thread through to `Tool_build.select_executable`

2. **Create cram tests**: Start with simple cases
   - Lock a tool: `dune tools lock hello`
   - Run a tool: `dune tools run hello`
   - Which a tool: `dune tools which hello`

3. **Debug internal error on lock**: Compare with `dune pkg lock` invocation
   - The error "Unexpected build progress state" suggests scheduler issue
   - May need to avoid mixing fiber/memo with direct scheduler calls

4. **Integrate with format_rules**: Use `Tool_resolution` for ocamlformat
   - Replace dual-path (locked/unlocked) logic with unified resolution
   - Test that `dune fmt` works with tool-locked ocamlformat
