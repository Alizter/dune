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

## Current Implementation Shortcomings

| Issue | Location | Problem |
|-------|----------|---------|
| Hardcoded 10 tools | `src/dune_pkg/dev_tool.ml:3-13` | Can't add arbitrary packages |
| Deep pkg coupling | `bin/lock_dev_tool.ml` | Uses full solver, synthetic packages |
| No multi-version | `src/dune_rules/pkg_dev_tool.ml` | Single global version per tool |
| Confusing dirs | `.dev-tools.locks/` | GitHub #10955 |
| Special-cased format | `src/dune_rules/format_rules.ml:34-102` | Two paths (locked/unlocked) |

---

## Related GitHub Issues

This implementation addresses numerous GitHub issues. Issues are grouped by theme.

### Core Dev Tools Redesign

| Issue | Title | How Tool Stanza Helps |
|-------|-------|----------------------|
| [#12914](https://github.com/ocaml/dune/issues/12914) | **pkg: reworking dev tools** | Umbrella issue - this plan implements the redesign |
| [#12913](https://github.com/ocaml/dune/issues/12913) | **pkg: general support for installing tools** | `(tool)` stanza allows any opam package, not just hardcoded ones |
| [#12741](https://github.com/ocaml/dune/issues/12741) | **Replace auto-installation of dev tools with autolocking** | Explicit `(tool)` stanza avoids race conditions from on-the-fly locking |

### Tool Versioning and Constraints

| Issue | Title | How Tool Stanza Helps |
|-------|-------|----------------------|
| [#12777](https://github.com/ocaml/dune/issues/12777) | **pkg: specifying constraints for dev tools** | `(tool (package (ocamlformat (= 0.26.2))))` provides robust version constraints in workspace |
| [#12866](https://github.com/ocaml/dune/issues/12866) | **Adding constraint to ocamlformat developer tool fails** | New stanza-based constraints avoid path-based approach that causes internal errors |
| [#12868](https://github.com/ocaml/dune/issues/12868) | **Dev tools and special compiler branches** | `Tool_compiler` module properly detects `ocaml-variants`, `ocaml-base-compiler`, and pinned compilers |

### Directory Structure

| Issue | Title | How Tool Stanza Helps |
|-------|-------|----------------------|
| [#10955](https://github.com/ocaml/dune/issues/10955) | **Kind of annoying to have both `dune.lock` and `dev-tools.locks`** | New `.tools.lock/` directory with cleaner naming |

### Format Rules and Formatter Issues

| Issue | Title | How Tool Stanza Helps |
|-------|-------|----------------------|
| [#10688](https://github.com/ocaml/dune/issues/10688) | **pkg: avoid `dune fmt` capturing `ocamlformat` from the PATH** | `Tool_resolution` uses locked version, only falls back to PATH if no stanza/lock |
| [#11038](https://github.com/ocaml/dune/issues/11038) | **`dune fmt` requires `ocamlc` to be in path** | `Tool_build.tool_env` provides proper environment including compiler |
| [#11037](https://github.com/ocaml/dune/issues/11037) | **`dune fmt` builds all project dependencies when lockdir present** | Tools are isolated in `_build/default/.tools/`, separate from project |
| [#3642](https://github.com/ocaml/dune/issues/3642) | **adding new formatters can break older projects** | Explicit `(tool)` stanza means formatters are opt-in per project |
| [#7619](https://github.com/ocaml/dune/issues/7619) | **Possibility to specify another formatter for OCaml/ReasonML** | Generic tool mechanism can be extended for custom formatters |
| [#10578](https://github.com/ocaml/dune/issues/10578) | **`dune build @fmt` exits with 1 if `ocamlformat` not installed** | `Tool_resolution` graceful fallback prevents hard failures |
| [#10863](https://github.com/ocaml/dune/issues/10863) | **use a custom command to format dune files** | General tool abstraction enables per-project formatter customization |
| [#3836](https://github.com/ocaml/dune/issues/3836) | **More general support for formatters?** | `(tool)` provides the generic mechanism this issue requested |

### Tool Installation and Execution UX

| Issue | Title | How Tool Stanza Helps |
|-------|-------|----------------------|
| [#12135](https://github.com/ocaml/dune/issues/12135) | **`dune tools setup` to install `:with-dev-setup` deps** | Workspace `(tool)` stanzas can be batch-installed |
| [#12557](https://github.com/ocaml/dune/issues/12557) | **`dune tools install` should take multiple package arguments** | New CLI design supports this |
| [#12818](https://github.com/ocaml/dune/issues/12818) | **If dune tools install fails it can break environment** | Cleaner lock directory structure enables atomic operations |
| [#12975](https://github.com/ocaml/dune/issues/12975) | **running `dune tools exec <p>` when not installed should suggest install** | Unified resolution can provide better error messages |
| [#13235](https://github.com/ocaml/dune/issues/13235) | **dune build @doc should hint installation of odoc dev tool** | Generic tool system provides consistent messaging |

### Tool Isolation and Conflicts

| Issue | Title | How Tool Stanza Helps |
|-------|-------|----------------------|
| [#12551](https://github.com/ocaml/dune/issues/12551) | **pkg: `dune utop src/...` fails because of duplicate .cmas** | Tools built in isolated `_build/default/.tools/<pkg>/` avoid conflicts |
| [#11229](https://github.com/ocaml/dune/issues/11229) | **ocamllsp cannot read stdlib.cmi (corrupted compiled interface)** | `compiler_compatible` flag ensures tools are built with matching compiler |

### Scoping

| Issue | Title | How Tool Stanza Helps |
|-------|-------|----------------------|
| [#12777](https://github.com/ocaml/dune/issues/12777) (note) | Different projects need different ocamlformat versions | Per-project tool scoping via workspace stanzas |

---

## Syntax

```lisp
;; Simple - just package name
(tool (package ocamlformat))

;; With version constraint
(tool (package (ocamlformat (= 0.26.2))))

;; With additional options
(tool
  (package (ocamlformat (= 0.26.2)))
  (executable ocamlformat-rpc)
  (compiler_compatible))
```

---

## Implementation Status

### Completed (Phases 1-6)

#### Phase 1-2: Tool Configuration Module ✅

**Created `src/source/tool_stanza.ml` and `.mli`**

```ocaml
type t =
  { package : Package.Name.t
  ; version : Package_constraint.t option
  ; executable : string option
  ; compiler_compatible : bool
  ; loc : Loc.t
  }
```

**Modified `src/source/workspace.ml`**
- Added `tools : Tool_stanza.t list` field to workspace type
- Added `(tool)` stanza parsing via `multi_field "tool" Tool_stanza.decode`
- Added `find_tool : t -> Package.Name.t -> Tool_stanza.t option`

**Modified `src/source/workspace.mli`**
- Exposed `tools` field and `find_tool` function

#### Phase 3: Tool Lock Directory Management ✅

**Created `src/dune_rules/tool_lock.ml` and `.mli`**

```ocaml
(* Lock directory paths *)
val external_lock_dir : Package.Name.t -> Path.External.t  (* .tools.lock/<pkg>/ *)
val build_lock_dir : Package.Name.t -> Path.t              (* _build/default/.tools/<pkg>/ *)

(* Lock directory operations *)
val lock_dir_exists : Package.Name.t -> bool Memo.t
val load : Package.Name.t -> Dune_pkg.Lock_dir.t Memo.t
val load_if_exists : Package.Name.t -> Dune_pkg.Lock_dir.t option Memo.t
```

#### Phase 4: Compiler Detection ✅

**Created `src/dune_rules/tool_compiler.ml` and `.mli`**

```ocaml
type compiler_source =
  | From_pkg of { name : Package.Name.t; version : Package_version.t }
  | From_system of { version : string }
  | From_opam_switch of { prefix : string }
  | Unknown

val detect : unit -> compiler_source Memo.t
val constraints_for_tool : compiler_source -> Package_dependency.t list
val get_constraints : unit -> Package_dependency.t list Memo.t
```

#### Phase 5: Tool Build Infrastructure ✅

**Created `src/dune_rules/tool_build.ml` and `.mli`**

```ocaml
(* Installation paths *)
val install_path : Package.Name.t -> Path.Build.t
val exe_path : package_name:Package.Name.t -> executable:string -> Path.Build.t
val exe_path_of_stanza : Tool_stanza.t -> Path.Build.t

(* Environment *)
val tool_env : Package.Name.t -> Env.t Memo.t
val tool_bin_dirs : Tool_stanza.t list -> Path.t list
val add_tools_to_path : Tool_stanza.t list -> Env.t -> Env.t
```

#### Phase 6: Tool Resolution ✅

**Created `src/dune_rules/tool_resolution.ml` and `.mli`**

```ocaml
type resolved =
  { package : Package.Name.t
  ; exe_path : Path.Build.t
  ; env : Env.t Memo.t
  }

type resolution_source =
  | From_workspace_stanza of Tool_stanza.t
  | From_legacy_dev_tool of Dune_pkg.Dev_tool.t
  | From_system_path

val resolve_opt : package_name:Package.Name.t -> (resolved * resolution_source) option Memo.t
val resolve : package_name:Package.Name.t -> resolved Memo.t
val ensure_built : resolved -> Path.t Action_builder.t
val with_tool_env : resolved -> f:(exe_path:Path.t -> env:Env.t -> 'a) -> 'a Action_builder.t
```

**Modified `src/dune_rules/import.ml`**
- Added `Tool_stanza` to imports from Source

---

### Remaining Work (Phases 10-11)

#### Phase 7: Refactor format_rules.ml ✅

**Completed**. Refactored `src/dune_rules/format_rules.ml` to use the unified `Tool_resolution` system.

**Changes Made**:
1. Removed `dev_tool_lock_dir_exists()` check
2. Replaced `action_when_ocamlformat_is_locked` with `action_when_resolved` using `Tool_resolution.with_tool_env`
3. Renamed `action_when_ocamlformat_isn't_locked` to `action_when_not_resolved`
4. Rewrote `format_action` to take `~ocamlformat_resolved` parameter
5. Updated `gen_rules_output` to call `Ocamlformat.resolve()` via `Tool_resolution.resolve_for_formatting`
6. Removed dependencies on `Lock_dir.dev_tool_external_lock_dir`, `Pkg_dev_tool.exe_path`, `Pkg_rules.dev_tool_env`, and `Config.get Compile_time.lock_dev_tools`

**New Flow**:
- `Ocamlformat.resolve()` calls `Tool_resolution.resolve_for_formatting`
- Returns `Some (resolved, source)` when tool is configured via stanza, legacy dev tool, or lock dir
- Returns `None` when tool should come from system PATH
- `action_when_resolved` uses `Tool_resolution.with_tool_env` to get exe path and environment
- `action_when_not_resolved` uses system PATH lookup via expander

#### Phase 8-9: CLI Updates ✅

**Completed**. Created generic tool locking and updated CLI commands.

**Created `bin/lock_tool.ml` and `.mli`**:
- Generalized version of `lock_dev_tool.ml` that works with any package
- `lock_tool : Package_name.t -> unit Memo.t` - lock any package
- `lock_tool_at_version` - lock with explicit version constraint
- `lock_tool_from_stanza` - lock using Tool_stanza configuration
- Uses new `.tools.lock/<package>/` directory structure
- Supports `compiler_compatible` flag for matching project compiler

**Modified `bin/tools/tools_common.ml`**:
- Added generic tool support functions:
  - `generic_tool_exe_path` - get exe path for any package
  - `build_generic_tool_directly` - build using Lock_tool
  - `lock_and_build_generic_tool` - full lock + build flow
  - `run_generic_tool` - run any package
- Added generic command terms:
  - `generic_exec_term` - execute any package
  - `generic_install_term` - install any package
  - `generic_which_term` - find any package's exe path

**Modified `bin/tools/group.ml`**:
- Updated Exec, Install, and Which modules with generic defaults
- `dune tools exec <package>` now works for any opam package
- `dune tools install <package>` now works for any opam package
- `dune tools which <package>` now works for any opam package
- Legacy tool-specific commands still available as subcommands

**Exported from `dune_rules.ml`**:
- `Tool_build`, `Tool_resolution`, `Tool_lock`, `Tool_compiler`

#### Phase 8 (original): Create Generic Tool Locking Command

**Goal**: Generalize `bin/lock_dev_tool.ml` for any package.

**Create `bin/lock_tool.ml`**:
```ocaml
(* Lock a tool package with compiler constraints *)
val lock_tool :
  package:Package.Name.t ->
  version:Package_version.t option ->
  compiler_compatible:bool ->
  unit Memo.t
```

**Key Changes from `lock_dev_tool.ml`**:
1. Remove hardcoded `Dev_tool.t` references
2. Use `Tool_compiler.detect` for compiler constraints
3. Write to `.tools.lock/<package>/` instead of `.dev-tools.locks/`
4. Read version from `(tool)` stanza if present

#### Phase 9: Update CLI Commands

**Modify `bin/tools/group.ml`**:
```ocaml
(* New: dune tools exec <package> [-- args] *)
let generic_exec =
  Cmd.v (Cmd.info "exec")
    (let+ package = Arg.pos 0 string ...
     and+ args = Arg.pos_right 0 string [] ... in
     (* Use Tool_resolution to find and run the tool *)
     ...)

(* New: dune tools lock <package> *)
let generic_lock = ...

(* Keep legacy commands for backward compatibility *)
```

**Modify `bin/tools/tools_common.ml`**:
- Update `dev_tool_bin_dirs` to include tools from workspace stanzas
- Update `run_dev_tool` to work with any package via `Tool_resolution`

#### Phase 10: Backward Compatibility

**Modify `src/dune_pkg/dev_tool.ml`**:
```ocaml
(* Convert legacy tool to Tool_stanza.t *)
val to_tool_stanza : t -> Tool_stanza.t

(* Check if package matches a legacy tool *)
val of_package_name_opt : Package.Name.t -> t option
```

**Modify `src/dune_rules/pkg_dev_tool.ml`**:
- Delegate path calculations to `Tool_build`
- Keep `exe_path` working for existing code

#### Phase 11: Migration and Directory Structure

**Directory structure change**:
```
OLD: .dev-tools.locks/ocamlformat/
NEW: .tools.lock/ocamlformat/

OLD: _build/default/.dev-tool-locks/
NEW: _build/default/.tools/
```

**Add migration helper in `Tool_lock`**:
```ocaml
val migrate_legacy_lock_dir : Dev_tool.t -> unit
```

---

## Testing Plan

### Unit Tests (parsing)

Location: `test/blackbox-tests/test-cases/pkg/tool-stanza/`

1. **Parsing tests**: Valid syntax variations
2. **Error tests**: Missing fields, invalid values

### Integration Tests (with mock repo)

Location: `test/blackbox-tests/test-cases/pkg/tool-stanza/`

Using the existing test infrastructure (`mkrepo`, `mkpkg`, etc.):

1. **Basic tool locking**:
   - Create mock repo with fake tool package
   - Configure via `(tool (package foo))`
   - Run `dune tools lock foo`
   - Verify `.tools.lock/foo/` created

2. **Tool building**:
   - Lock a tool
   - Run `dune tools exec foo`
   - Verify tool builds and executes

3. **Version constraints**:
   - Create multiple versions in mock repo
   - Use `(tool (package (foo (= 1.0))))`
   - Verify correct version locked

4. **Compiler compatibility**:
   - Use `(compiler_compatible)` flag
   - Verify compiler constraints in lock file

5. **PATH integration**:
   - Run `dune tools env`
   - Verify tool bin dirs in PATH output

6. **Format rules integration**:
   - Configure ocamlformat via `(tool)` stanza
   - Run `dune fmt`
   - Verify uses configured version

### Example Test Structure

```
test/blackbox-tests/test-cases/pkg/tool-stanza/
├── dune
├── helpers.sh
├── tool-stanza-basic.t
├── tool-stanza-version.t
├── tool-stanza-compiler.t
├── tool-stanza-format.t
└── tool-stanza-env.t
```

---

## Files Summary

### Created
| File | Purpose |
|------|---------|
| `src/source/tool_stanza.ml` | Tool configuration types and parsing |
| `src/source/tool_stanza.mli` | Interface |
| `src/dune_rules/tool_lock.ml` | Lock directory management |
| `src/dune_rules/tool_lock.mli` | Interface |
| `src/dune_rules/tool_compiler.ml` | Compiler detection |
| `src/dune_rules/tool_compiler.mli` | Interface |
| `src/dune_rules/tool_build.ml` | Build paths and environment |
| `src/dune_rules/tool_build.mli` | Interface |
| `src/dune_rules/tool_resolution.ml` | Unified resolution |
| `src/dune_rules/tool_resolution.mli` | Interface |

### Modified
| File | Changes |
|------|---------|
| `src/source/workspace.ml` | Added `tools` field, `(tool)` stanza |
| `src/source/workspace.mli` | Exposed `tools` field |
| `src/source/source.ml` | Exported `Tool_stanza` |
| `src/dune_rules/import.ml` | Added `Tool_stanza` import |
| `src/dune_rules/format_rules.ml` | Use `Tool_resolution` for unified ocamlformat handling |

### To Be Modified (Phases 8-11)
| File | Changes |
|------|---------|
| `src/dune_pkg/dev_tool.ml` | Add backward compat functions |
| `src/dune_rules/pkg_dev_tool.ml` | Delegate to Tool_build |
| `bin/tools/group.ml` | Add generic commands |
| `bin/tools/tools_common.ml` | Use Tool_resolution |
| `bin/lock_dev_tool.ml` | Delegate to new lock_tool |

### To Be Created (Phases 7-11)
| File | Purpose |
|------|---------|
| `bin/lock_tool.ml` | Generic tool locking command |
| `test/blackbox-tests/test-cases/pkg/tool-stanza/*` | Test suite |
