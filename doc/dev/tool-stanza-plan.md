# Developer Tools Design Document

## Overview

This document describes the design and implementation of dune's new developer
tools system, supporting arbitrary opam packages as tools via a `(tool)` stanza
in `dune-workspace`.

## Requirements

### Core Requirements

1. **Arbitrary packages**: Support any opam package as a tool, not just hardcoded ones
2. **Version pinning**: Allow specific versions via `.ocamlformat`, CLI, or stanza
3. **Multi-version support**: Multiple versions of the same tool can coexist
4. **Isolated builds**: Tools are built separately from project packages
5. **Project-local storage**: Tools stored in `_build/_private/default/.tools/` per workspace
6. **Compiler matching**: Tools can optionally match the project's compiler version

### CLI Requirements

1. **Add tools**: Lock new tools to versioned directories
2. **Run tools**: Execute tools, building if needed
3. **List tools**: Show all locked tools and versions
4. **Remove tools**: Clean up tool lock directories
5. **Path discovery**: Print path to tool executable

### Integration Requirements

1. **Format rules**: `dune fmt` uses locked ocamlformat or falls back to PATH
2. **Workspace stanza**: `(tool)` stanza for declarative configuration
3. **No build triggers**: Tool locking doesn't trigger project builds

### Non-Requirements (Explicit Exclusions)

1. **Global cache**: Tools are project-local, not shared across projects
2. **Automatic updates**: Tools don't auto-update; explicit `dune tools add` required
3. **IDE integration**: Out of scope for initial implementation

## Design Goals

1. Support **any** opam package as a tool (not just 10 hardcoded ones)
2. Add `(tool)` stanza to dune-workspace for configuration
3. Scope tools per workspace (future: per dune-project)
4. Store tools in `_build/_private/default/.tools/` (separate from regular build artifacts)
5. Match compiler constraints from dune_rules (pkg or system)
6. Decouple from package management while reusing per-tool lock directories

---

## Legacy Dev Tools Shortfalls

The original dev tools system was designed as a quick solution to provide tools
like ocamlformat, ocamllsp, and odoc. It evolved into a complex system with
significant limitations that this new design addresses.

### 1. Hardcoded Tool Registry (`src/dune_pkg/dev_tool.ml`)

**Problem**: Only 10 tools supported as compile-time enum:
- Ocamlformat, Odoc, Ocamllsp, Utop, Ocamlearlybird, Odig, Opam_publish,
  Dune_release, Ocaml_index, Merlin

**Issues**:
- Adding new tools requires modifying source code in multiple places
- 65+ lines of boilerplate for the `equal` function alone
- Package names don't match tool names (e.g., "Ocamllsp" → "ocaml-lsp-server")
- Executable names don't match package names (e.g., "Merlin" → "ocamlmerlin")
- Compiler matching is hardcoded per-tool with uncertain logic (CR-someday comments)

**New Design Fix**: ✅ Any opam package can be a tool via `(tool)` stanza or `dune tools add`

### 2. Wrapper Package Antipattern (`bin/lock_dev_tool.ml`)

**Problem**: Creates fake "dev_tool_wrapper" packages to inject tools into solver:
```
ocamlformat_dev_tool_wrapper → depends on ocamlformat
```

**Issues**:
- Pollutes package namespace with phantom packages
- Solver doesn't understand these are workarounds
- Complex regeneration logic with 5+ different outcomes
- Relaxed version constraint hack (`___MAX_VERSION` suffix)

**New Design Fix**: ✅ Tools solved with isolated synthetic package, no project package mixing

### 3. Single Global Version (`src/dune_rules/pkg_dev_tool.ml`)

**Problem**: Only one version per tool globally:
```
_build/default/.dev-tool/ocamlformat/target/bin/ocamlformat
```

**Issues**:
- Can't have multiple projects with different tool versions
- No version in path structure
- Upgrading tool affects all projects

**New Design Fix**: ✅ Versioned paths: `_build/.tools.lock/<pkg>/<version>/`

### 4. Confusing Directory Structure

**Problem**: Two top-level lock directories:
- `dune.lock/` (project packages)
- `.dev-tools.locks/` (dev tools)

**User Complaint**: "Kind of annoying to have both as top-level folders" ([#10955](https://github.com/ocaml/dune/issues/10955))

**New Design Fix**: ✅ Tools in `_build/.tools.lock/` - inside build directory, not source tree

### 5. Compiler Coupling Issues (`bin/lock_dev_tool.ml:105-143`)

**Problem**: Tools must query project's build context to find compiler:
- Tight coupling between tool locking and project lock dir
- Fails with confusing error if project has no lock dir
- Platform-dependent locks become invalid when switching OS

**New Design Fix**: ✅ `solver_env_without_ocaml_version` for OCaml tool itself; system OCaml detection reads from disk directly

### 6. Binary Download Incompatibility

**Problem**: Pre-built tool binaries may be compiled with different compiler/toolchain than project

**User Report**: ocamllsp binary download (musl toolchain) doesn't work with locally-built OCaml ([#11229](https://github.com/ocaml/dune/issues/11229))

**New Design Fix**: ✅ Tools built from source with matching compiler constraints

### 7. `@fmt` Hard Dependency on ocamlformat

**Problem**: `dune build @fmt` fails if ocamlformat not installed, even for non-OCaml formatting

**User Complaint**: "Unnecessarily limits @fmt alias" ([#10578](https://github.com/ocaml/dune/issues/10578))

**New Design Fix**: ✅ Format rules fall back to system PATH when:
- No version specified in `.ocamlformat`, OR
- Version specified but not locked (user gets "command not found" from system)

---

## Related GitHub Issues

| Issue | Title | Status | Problem | Addressed? |
|-------|-------|--------|---------|------------|
| [#10955](https://github.com/ocaml/dune/issues/10955) | Annoying to have both `dune.lock` and `dev-tools.locks` as top-level folders | Closed | Confusing directory structure | ✅ Tools now in `_build/.tools.lock/` |
| [#11229](https://github.com/ocaml/dune/issues/11229) | ocamllsp cannot read stdlib.cmi (corrupted compiled interface) | Closed | Binary downloads built with different compiler | ✅ Tools built from source |
| [#10578](https://github.com/ocaml/dune/issues/10578) | `dune build @fmt` exits with 1 if ocamlformat not installed | Open | Hard dependency on ocamlformat | ✅ Falls back to PATH |
| [#12097](https://github.com/ocaml/dune/issues/12097) | Do not write lock directories into worktree by default | Open | Lock dirs clutter source tree | ✅ `_build/.tools.lock/` |
| [#10647](https://github.com/ocaml/dune/pull/10647) | Build and make ocamlformat dev-tool available | Merged | Need workspace config, not CLI | ✅ `(tool)` stanza |

---

## New Design Advantages

| Old System | New System |
|------------|------------|
| 10 hardcoded tools | Any opam package |
| Single global version | Multiple versions coexist |
| `.dev-tools.locks/` in source tree | `_build/.tools.lock/` hidden |
| Wrapper package hack | Isolated tool solving |
| Binary downloads | Build from source |
| Tight compiler coupling | Flexible compiler constraints |
| Complex regeneration logic | Simple lock/build/run |

---

## Current Limitations

### Workspace-Scoped Tools

**Current behavior**: Tools are scoped to the **workspace** (via `dune-workspace`), not
individual projects within a workspace.

**Implication**: All projects in a workspace share the same tool configuration. You
cannot have different tool versions for different `dune-project` files within the
same workspace.

**Future enhancement**: Allow `(tool)` stanzas in `dune-project` files to enable
per-project tool configuration. This would allow:

```lisp
; In project-a/dune-project
(tool (package ocamlformat) (version (= 0.26.2)))

; In project-b/dune-project
(tool (package ocamlformat) (version (= 0.27.0)))
```

Resolution order would be: project-level → workspace-level → CLI.

### No Batch Install Command

**Current behavior**: Each tool must be added individually via `dune tools add <pkg>`.

**Missing feature**: A command to install all tools required by a project:

```bash
dune tools install
```

This should collect tools from multiple sources:

1. **Explicit `(tool)` stanzas** in `dune-workspace` (and eventually `dune-project`)
2. **Dependencies with markers** from `dune-project` or opam files:
   - `{with-doc}` - dependencies needed for documentation (e.g., odoc)
   - `{with-dev-setup}` - dependencies needed for development (e.g., ocaml-lsp-server)
   - `{with-test}` - dependencies needed for testing

These markers come from opam conventions and indicate *when* a dependency is needed,
not what kind of tool it is. The `dune tools install` command would:

1. Parse dependencies from `dune-project` package stanzas (or opam files)
2. Filter by marker flags (`--with-doc`, `--with-dev-setup`, etc.)
3. Filter to packages that provide binaries (not just libraries)
4. Combine with explicit `(tool)` stanzas
5. Lock and build all matching tools

**Example workflow**:

```lisp
; dune-project
(package
  (name mylib)
  (depends
    (odoc :with-doc)
    (ocaml-lsp-server :with-dev-setup)
    (ocamlformat :with-dev-setup)))
```

```bash
# Install all tools from stanzas + all marked dependencies that are tools
$ dune tools install
Locking odoc...
Locking ocaml-lsp-server...
Locking ocamlformat...
Building odoc@2.4.0...
Building ocaml-lsp-server@1.17.0...
Building ocamlformat@0.26.2...
Done. 3 tools installed.

# Install only dependencies marked :with-doc that are tools
$ dune tools install --with-doc

# Install only dependencies marked :with-dev-setup that are tools
$ dune tools install --with-dev-setup
```

**Implementation considerations**:

1. Reuse existing dependency parsing from `dune-project` / opam file handling
2. Determine if a package is a "tool" (provides binaries) - may need to check opam metadata
3. Handle overlap between explicit `(tool)` stanzas and marked dependencies
4. Lock and build tools (can parallelize)

This is analogous to:
- `npm install` (installs all devDependencies)
- `cargo bin --install` (installs all configured binaries)

---

## Comparison with Other Tool Managers

This section documents how other ecosystems handle tool management, informing our
design decisions.

### Overview of Approaches

| Aspect | **uv** (Python) | **cargo** (Rust) | **npm** (JS) | **cargo-run-bin** |
|--------|-----------------|------------------|--------------|-------------------|
| Storage | Global (`~/.local/share/uv/tools/`) | Global (`~/.cargo/bin/`) | Local (`node_modules/.bin/`) | Local (`.bin/`) |
| Isolation | Per-tool venv | Single bin dir | Per-project | Per-project |
| Config file | None (CLI) | None built-in | `package.json` | `Cargo.toml` metadata |
| Version pinning | CLI flag | CLI flag | `package.json` | `Cargo.toml` |
| Project-scoped | No | No | Yes | Yes |
| Ephemeral runs | `uvx` | No | `npx` | No |

### uv (Python)

**Source**: [docs.astral.sh/uv/concepts/tools](https://docs.astral.sh/uv/concepts/tools/)

uv distinguishes between ephemeral (`uvx`) and persistent (`uv tool install`) tool usage:

- **`uvx <tool>`**: Runs tool in temporary virtual environment, cached but disposable
- **`uv tool install <tool>`**: Persistent installation, executables added to PATH

**Key features**:
- Per-tool isolated virtual environments (no cross-tool conflicts)
- Version suffix syntax: `uvx ruff@0.3.0`, `uvx ruff@latest`
- Constraint preservation: installing `black>=23,<24` is respected by `uv tool upgrade`

**Gap**: No project-local tool declaration—tools are always user-global.

**What we can learn**:
- `@version` suffix syntax is intuitive
- Ephemeral vs persistent distinction is useful
- `upgrade` command that respects original constraints

### cargo (Rust)

**Source**: [doc.rust-lang.org/cargo/commands/cargo-install](https://doc.rust-lang.org/cargo/commands/cargo-install.html)

cargo's built-in tool support is minimal:

- All binaries installed to single `~/.cargo/bin/` directory
- No isolation between tools
- No multi-version support (new version overwrites old)
- No project-local tools

**Key features**:
- Version constraint syntax: `cargo install ripgrep@1.2.0`, `--version ~1.2`
- Smart reinstall: only rebuilds if version/features/profile changed
- `cargo install --list` shows all installed packages

**Gap**: No project-local tools, which is why cargo-run-bin exists.

### cargo-run-bin (Rust community tool)

**Source**: [github.com/dustinblackman/cargo-run-bin](https://github.com/dustinblackman/cargo-run-bin)

This third-party tool fills cargo's gaps and is the **closest analog to our design**:

```toml
[package.metadata.bin]
cargo-nextest = { version = "0.9.57", locked = true }
dprint = { version = "0.30.3" }
cargo-mobile2 = { version = "0.5.2", bins = ["cargo-android", "cargo-mobile"] }
```

**Key features**:
- Project-local `.bin/` cache directory
- Declarative config in `Cargo.toml` metadata section
- `bins` array for multi-binary packages
- `locked` flag for reproducible dependency resolution
- `cargo bin --install` to install all configured tools at once
- Automatic cargo alias creation

**What we can learn**:
- `bins` field for explicit binary listing (vs auto-discovery)
- `--locked` flag for reproducibility
- Batch install command (`dune tools install`)

### npm (JavaScript)

**Source**: [docs.npmjs.com](https://docs.npmjs.com/cli/v7/configuring-npm/package-json/)

npm's approach is the most mature for project-local tools:

- Tools declared in `devDependencies` in `package.json`
- Binaries linked to `node_modules/.bin/`
- `npx` runs binaries, preferring local over global
- npm scripts automatically get `node_modules/.bin` in PATH
- `package-lock.json` provides exact version pinning (like our lock dirs)

**What we can learn**:
- devDependencies pattern (tools as dev deps, committed to repo)
- Auto-PATH for scripts (tools available without explicit path)
- `npx` prefers local, falls back to fetch
- Lockfile for reproducibility

### pnpm (JavaScript)

**Source**: [pnpm.io](https://pnpm.io/)

pnpm adds interesting innovations over npm:

- **Content-addressable storage**: Packages stored once globally, hard-linked into projects
- **Strict isolation**: Each package sees only its declared dependencies
- **Faster installs**: Deduplication across projects

**What we could learn (future)**:
- Content-addressable storage could enable cross-project tool sharing
- Strict isolation model aligns well with our tool isolation goals

### Comparison: Our Design vs Others

| Feature | **Dune (ours)** | **uv** | **cargo** | **cargo-run-bin** | **npm** |
|---------|-----------------|--------|-----------|-------------------|---------|
| Project-local storage | ✅ `_build/.tools.lock/` | ❌ | ❌ | ✅ | ✅ |
| Multi-version support | ✅ `<pkg>/<ver>/` | ❌ | ❌ | ❌ | ❌ |
| Declarative config | ✅ `(tool)` stanza | ❌ | ❌ | ✅ | ✅ |
| Compiler matching | ✅ Automatic | N/A | N/A | ❌ | N/A |
| Binary discovery | ✅ Install cookie | ✅ | N/A | ✅ `bins` | ✅ |
| PATH fallback | ✅ System PATH | ❌ | ❌ | ❌ | ✅ |
| Build from source | ✅ Always | ❌ | ✅ | ✅/binstall | ❌ |
| Tool isolation | ✅ Separate solve | ✅ | ❌ | ✅ | ✅ |
| Ephemeral runs | 🔄 `run` locks-if-needed | ✅ `uvx` | ❌ | ❌ | ✅ `npx` |
| Batch install | ❌ | ❌ | ❌ | ✅ | ✅ |
| Dep marker integration | 🔄 Planned | ❌ | ❌ | ❌ | ✅ `devDeps` |

### Recommendations from Research

#### High Priority

1. **`pkg@version` syntax** (from uv) - **Currently uses `pkg.version`**
   ```bash
   # Current implementation uses dot separator:
   dune tools add ocamlformat.0.26.2
   dune tools run ocamlformat.0.26.2

   # Future: consider @ separator for clarity (like uv):
   dune tools add ocamlformat@0.26.2
   ```

2. **`dune tools install` batch command** (from cargo-run-bin, npm)
   ```bash
   # Install all tools from stanzas + dependency markers
   dune tools install

   # Install only doc tools (odoc, etc.)
   dune tools install --with-doc

   # Install only dev-setup tools (ocamllsp, ocamlformat, etc.)
   dune tools install --with-dev-setup
   ```
   Critical for CI and onboarding. Unique to dune: integration with
   `:with-doc` and `:with-dev-setup` dependency markers from `dune-project`.

#### Medium Priority

3. **`--locked` flag** (from cargo-run-bin)
   ```bash
   dune tools add ocamlformat --locked
   ```
   Ensures exact versions from solver, not ranges.

4. **`bins` field in stanza** (from cargo-run-bin)
   ```lisp
   (tool
     (package menhir)
     (bins menhir menhirSdk))
   ```
   More reproducible than auto-discovery.

#### Low Priority (Future Consideration)

5. **Ephemeral run mode** (from uv's `uvx`)
   - If tool locked → use locked version
   - If tool NOT locked → ephemeral solve, build in temp, run, discard

6. **System-wide linking** (from uv)
   ```bash
   dune tools link ocamlformat --global
   # Creates ~/.local/bin/ocamlformat symlink
   ```

### Key Insight

**Our design is more advanced than cargo's built-in tooling** and comparable to
cargo-run-bin. Our unique advantages:

1. **Multi-version support** - No other tool manager supports this
2. **Compiler matching** - OCaml-specific, handled automatically
3. **Build-directory storage** - Keeps source tree clean (addresses user complaints)

The main gap is **workspace-scoped** vs **project-scoped** tools (see Current
Limitations above).

---

## Current Status

### Working ✅

1. **Tool stanza parsing**: `(tool (package ocamlformat))` works in dune-workspace
2. **CLI commands**: `dune tools add <pkg>`, `dune tools run <pkg>`, `dune tools path <pkg>`, `dune tools list`, `dune tools remove <pkg>`
3. **Default list command**: `dune tools` (without args) shows all locked tools
4. **Versioned lock directories**: `.tools.lock/<package>/<version>/` structure implemented
5. **Compiler detection**: System OCaml version detected via `Sys_vars.poll.sys_ocaml_version`
6. **Fs_memo tracking**: Lock directory existence tracked properly for memo invalidation
7. **Checksum collection**: Tool lock dirs included in fetch rules checksum map
8. **`.pkg/` rules always generated**: No longer gated by `lock_dir_active`
9. **System OCaml preference**: Requires `ocaml-system` when system OCaml is available
10. **Build system isolation**: `compiler_package_opt()` reads from disk directly to avoid triggering builds
11. **Version selection**: 0 versions → error, 1 version → auto-select, N versions → error
12. **Binary discovery**: Auto-detect binaries from install cookie's `Section.Bin`
13. **Build dependency via cookie**: Depend on `target/cookie` to ensure package is built before accessing binaries
14. **`--bin` flag**: CLI flag for `dune tools run` and `dune tools path` to select specific binary
15. **format_rules integration**: Uses Tool_resolution, falls back to system PATH when no version specified
16. **Simple tool_env**: Just adds bin dir to PATH, avoids expensive closure computations
17. **Tool isolation**: Tools solved independently from project packages (no "outside workspace" errors)

### Completed Recently ✅

1. **Removed legacy `dune tools install`**: Use `dune tools add` instead to avoid confusion with legacy dev_tool path
2. **Fixed dependency cycle**: Simplified `tool_env` to avoid triggering closure computations during formatting
3. **System PATH fallback**: When `.ocamlformat` doesn't specify a version, uses system PATH directly

### Remaining Work 🔄

1. **Migration from legacy `.dev-tools.locks/`**: Need helper to migrate existing dev tool locks
2. **Remove legacy dev_tool infrastructure**: Once migration complete
3. **End-to-end testing**: Create cram tests for full workflow
4. **Documentation**: User-facing docs for `(tool)` stanza

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

### 11. Tool Isolation from Project Packages

**Problem**: When solving tools, if the solver sees both project local_packages and tool dependencies, external packages (like `base`) might depend on workspace packages (like `dune-configurator`), causing "packages outside workspace depending on packages in workspace" errors.

**Solution**: Tools are solved with only a synthetic wrapper package as `local_packages`, not the project's packages. This isolates tools from the project's package management.

```ocaml
(* In lock_tool.ml *)
let local_pkg = make_local_package_wrapping_tool ~package_name ~version ~extra_dependencies in
let local_packages = Package_name.Map.singleton local_pkg.name local_pkg in
(* Only the wrapper is passed - project packages are NOT included *)
solve ~package_name ~local_packages ~repository_names
```

### 12. Simple tool_env Avoids Cycles

**Problem**: Using `Pkg_rules.tool_env` for tool environment triggered `Resolve.resolve` which computes dependency closures. This caused cycles when formatting rules tried to build ocamlformat.

**Solution**: Tools just need their bin directory in PATH. Use a simple env instead of the full pkg_rules machinery:

```ocaml
(* BAD - triggers closure computation *)
let env = Pkg_rules.tool_env package_name ~version in

(* GOOD - simple PATH addition *)
let tool_env package_name ~version =
  let bin_dir = Path.build (exe_path ~package_name ~version ~executable:"")
                |> Path.parent_exn in
  Env_path.cons Env.empty ~dir:bin_dir |> Memo.return
```

---

## Architecture Decisions

### Directory Structure

Tools have three directory locations (this is complex but necessary):

| Type | Lock Dir (External) | Lock Dir (Build Copy) | Install Dir |
|------|---------------------|----------------------|-------------|
| Project | `dune.lock/` | `_build/default/.lock/dune.lock/` | `_build/_private/default/.pkg/` |
| Dev tools (legacy) | `_build/.dev-tools.locks/<pkg>/` | `_build/default/.dev-tool-locks/<pkg>/` | `_build/_private/default/.dev-tool/<pkg>/` |
| Generic tools | `_build/.tools.lock/<pkg>/<ver>/` | `_build/default/.tool-locks/<pkg>/<ver>/` | `_build/_private/default/.tools/<pkg>/<ver>/` |

**Flow**: Lock dir (external) → copied to lock dir (build) → built to install dir.

**Key paths**:
- Lock directories use `_build/.tools.lock/` (at build root, versioned)
- Install directories use `_build/_private/default/.tools/` (in private context)

### CLI Commands

#### `dune tools` / `dune tools list`

List all locked tools and their versions.

```bash
$ dune tools
ocamlformat (0.26.2)
odoc (3.1.0)
menhir (20230415, 20240715)
```

#### `dune tools add <package>...`

Lock one or more packages as tools. Always re-solves (like `dune pkg lock`).

```bash
# Lock latest version
$ dune tools add ocamlformat
Solution for _build/.tools.lock/.solving:
- ocamlformat.0.26.2
- ...
Locked ocamlformat

# Lock specific version
$ dune tools add ocamlformat.0.26.1

# Lock multiple packages
$ dune tools add menhir odoc ocp-indent
```

#### `dune tools run <package> [-- args]`

Run a tool, locking and building if needed.

```bash
# Run with auto-selected binary
$ dune tools run ocamlformat -- --help

# Run specific binary (for packages with multiple binaries)
$ dune tools run menhir --bin menhir -- --version
```

#### `dune tools path <package>`

Print the path to a tool's executable.

```bash
$ dune tools path ocamlformat
_build/default/.tools/ocamlformat/0.26.2/target/bin/ocamlformat

# For packages with multiple binaries
$ dune tools path menhir --bin menhir
```

#### `dune tools remove <package>[.version]`

Remove a tool's lock directory.

```bash
# Remove all versions
$ dune tools remove ocamlformat
Removed all versions of ocamlformat

# Remove specific version
$ dune tools remove ocamlformat.0.26.1
Removed ocamlformat@0.26.1
```

#### Legacy Commands

Legacy dev tool exec commands still work via `dune tools exec`:

```bash
dune tools exec ocamlformat -- file.ml
dune tools exec ocamllsp
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

**CLI**: `dune tools add <pkg>.<version>` passes constraint to solver (e.g., `dune tools add ocamlformat.0.26.2`)

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

1. **End-to-end testing**: Create cram tests for:
   - `dune tools add <pkg>` → creates versioned lock dir
   - `dune tools run <pkg>` → builds and runs
   - `dune tools path <pkg>` → shows path after build
   - `dune tools list` → shows all tools
   - `dune tools remove <pkg>` → removes tool
   - Multiple versions coexisting
   - Binary discovery (single and multiple)
   - `--bin` flag with multi-binary packages

2. **Test `dune fmt` integration**: Verify formatting works with new tool resolution
   - No version in .ocamlformat → uses system PATH
   - Specific version in .ocamlformat → uses locked version or system PATH

### Medium Priority

3. **Migration from dev tools**: Helper to migrate `.dev-tools.locks/` to `.tools.lock/`

4. **Test compiler matching**: Verify tools work when project has lock dir with specific compiler

5. **Remove legacy dev_tool code**: Once migration is complete

### Low Priority

6. **Performance**: Consider caching tool builds across projects

7. **Documentation**: User-facing docs for `(tool)` stanza

---

## Files Modified

### Core Changes

| File | Changes |
|------|---------|
| `bin/lock_tool.ml` | Versioned solve (temp→final), system OCaml detection, avoid build triggers |
| `bin/lock_tool.mli` | Added `lock_tool_if_needed` |
| `bin/tools/tools_common.ml` | CLI with version handling, cookie-based build targets, binary discovery, generic commands |
| `bin/tools/group.ml` | New CLI structure: add, run, path, list, remove; removed legacy install |
| `src/dune_rules/pkg_rules.ml` | `Package_universe.Tool` with version, `Install_cookie.files` exposed |
| `src/dune_rules/pkg_rules.mli` | Exposed `Install_cookie` module with `files` accessor |
| `src/dune_rules/fetch_rules.ml` | Scan versioned tool lock dirs for checksums |
| `src/dune_rules/lock_dir.ml` | Versioned paths, `tool_locked_versions` scanner |
| `src/dune_rules/lock_dir.mli` | Updated signatures for versioned paths |
| `src/dune_rules/lock_rules.ml` | Copy rules iterate over package/version pairs |
| `src/dune_rules/format_rules.ml` | Uses Tool_resolution, falls back to system PATH |

### New Modules

| File | Purpose |
|------|---------|
| `src/source/tool_stanza.ml` | `(tool)` stanza parsing |
| `src/dune_rules/tool_lock.ml` | Lock directory management with version support |
| `src/dune_rules/tool_build.ml` | Versioned build paths, simple env, cookie reading, binary selection |
| `src/dune_rules/tool_resolution.ml` | Unified resolution with version selection, formatting support |

---

## Next Steps

1. **Create cram tests**: Start with simple cases
   - Add a tool: `dune tools add hello`
   - Run a tool: `dune tools run hello`
   - Path to tool: `dune tools path hello`
   - List tools: `dune tools list`
   - Remove tool: `dune tools remove hello`
   - Test `--bin` flag with multi-binary package

2. **Test `dune fmt`**: Verify formatting works correctly
   - Without .ocamlformat version → system PATH
   - With .ocamlformat version → locked or system PATH

3. **Plan legacy dev_tool removal**: Once new system is stable
   - Migrate existing `.dev-tools.locks/` usage
   - Deprecate `dune tools exec <legacy-tool>` commands

---

## Document Review Notes

This section documents issues found during review and decisions made.

### Path Structure Clarification

The tool system uses three distinct directory types:

1. **Lock directory (external)**: `_build/.tools.lock/<pkg>/<ver>/`
   - Contains `lock.dune` and package metadata
   - Created by `dune tools add`
   - Versioned to allow multiple versions

2. **Lock directory (build copy)**: `_build/default/.tool-locks/<pkg>/<ver>/`
   - Internal copy for build rules
   - Generated by copy rules in `lock_rules.ml`

3. **Install directory**: `_build/_private/default/.tools/<pkg>/<ver>/`
   - Built package artifacts (binaries, libraries)
   - Inside `_private` context to avoid conflicts
   - Contains `target/cookie` when build completes

### Version Syntax Decision

Current implementation uses **dot separator** (`pkg.version`):
```bash
dune tools add ocamlformat.0.26.2
```

Rationale: Matches opam's `pkg.version` convention.

Alternative considered: **@ separator** (`pkg@version`) like uv/npm.
- Pro: Clearer visual separation
- Con: Different from opam conventions
- Decision: Keep dot for now, consider @ in future

### Ephemeral vs Persistent Runs

Our `dune tools run` is **semi-ephemeral**:
- Locks tool if not already locked (like `npx` first run)
- Builds if not built
- Keeps lock dir for subsequent runs (unlike true ephemeral)

True ephemeral mode (build in temp, discard) is a future consideration.

### Scope: Workspace vs Project

Current: Tools scoped to **workspace** (via `dune-workspace`).

Future: Allow `(tool)` stanzas in `dune-project` for per-project tools.

This was a deliberate simplification for initial implementation.
