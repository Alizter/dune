# AGENTS.md

This file provides guidance to AI agents (Claude Code, Codex, etc) when working with
the Dune codebase.

## Quick Reference

**Most Common Commands:**
```bash
dune build @check          # Quick build (recommended for development)
dune runtest dir/          # Run tests in specific directory
dune fmt                   # Auto-format code (always run before committing)
dune promote               # Accept test output changes (ask user first)
make dev                   # Full build (bootstraps automatically if needed)
```

**Special Operations (Ask User First):**
```bash
make bootstrap             # Rebuild entire toolchain from scratch
```

Note: `dune` refers to `./dune.exe` (the bootstrapped version).

## Project Overview

Dune is a self-hosting OCaml build system that uses itself to build itself.

**Key Concepts:**
- **Bootstrap**: Building dune from scratch using `make bootstrap` (ask user
  first)
- **Cram Tests**: `.t` files containing shell commands and expected outputs
- **Test Promotion**: Accepting new test outputs when behavior changes
- **Self-hosting**: Dune builds itself using a previously built version

## Architecture

**Directory Structure:**
- `bench` - performance benchmarks
- `bin` - dune's command line interface
- `boot` - bootstrap mechanism for building dune itself
- `doc` - user documentation
- `otherlibs` - public libraries
- `src` - internal libraries (see below)
- `test` - test suite
  - `test/blackbox-tests/test-cases` - cram tests (`.t` files)
  - `test/expect-tests` - expect tests (ppx_expect)
  - `test/unit-tests` - unit tests
- `vendor` - vendored third-party code

**Key `src/` Libraries:**
- `dune_rules` - build rule generation (main logic)
- `dune_engine` - action execution and build system core
- `dune_lang` - dune file parsing and project configuration
- `dune_pkg` - package management and lock files
- `dune_scheduler` - process scheduling and file watching
- `dune_cache` - shared build cache
- `dune_trace` - tracing and profiling (writes to `_build/trace.csexp`)
- `fiber` - structured concurrency
- `memo` - incremental memoized computations
- `dune_console` - console output and user messages
- `dune_sexp` - s-expression parsing
- `dune_vcs` - git/hg integration
- `dune_findlib` - findlib/META file support

**Key `otherlibs/` Libraries (public):**
- `dyn` - dynamic value representation for debug serialization
- `dune-build-info` - embed version info in executables
- `dune-configurator` - discover C compiler/library configuration
- `dune-site` - access installation paths at runtime
- `dune-rpc` - RPC protocol for tooling integration

**`stdune` - Dune's Standard Library:**
Use instead of OCaml's stdlib. Provides enhanced versions of common modules:
- Collections: `List`, `Array`, `Map`, `Set`, `Hashtbl`, `Table`, `Queue`,
  `Seq`, `Nonempty_list`, `Appendable_list`
- Types: `String`, `Option`, `Result`, `Either`, `Or_exn`, `Int`, `Float`,
  `Bool`, `Char`, `Bytes`, `Tuple`
- Errors: `Code_error` (internal), `User_error`, `User_message`, `User_warning`,
  `Exn`, `Exn_with_backtrace`
- Filesystem: `Path`, `Fpath`, `Filename`, `Io`, `Temp`, `Readdir`, `Flock`
- Environment: `Env`, `Proc`, `Pid`, `Platform`, `Signal`, `Sys`
- Printing: `Pp`, `Loc`, `Ansi_color`, `Format`, `Json`, `Sexp`
- Interfaces: `Monad`, `Applicative`, `Comparable`, `Monoid`, `Staged`
- Utilities: `Fdecl` (forward decls), `Univ_map`, `Id`, `State`, `Predicate`,
  `Top_closure`, `Time`, `Log`, `Debug`, `Metrics`

## Development Workflow

### Build Commands
```bash
dune build @check          # Quick build (recommended for development)
dune build @install        # Full build
dune fmt                   # Auto-format code (always run before committing)
```

### Bootstrap Process

**What it is:** Bootstrap solves Dune's circular dependency (Dune builds Dune)
using `boot/bootstrap.ml` - a mini-build system that creates `_boot/dune.exe`
without reading any dune files.

**When needed:**
- Fresh repository checkout (no `_boot/dune.exe` exists)
- Changes to core build system dependencies in `boot/libs.ml`
- After certain clean operations that remove `_boot/`

**Why ask user first:** Bootstrap rebuilds the entire toolchain from scratch
using a carefully orchestrated process. Most development uses the existing
`_boot/dune.exe`.

**When NOT to bootstrap:** For normal development work, use `dune build @check`
or `make dev`. Bootstrap is only needed for the specific circumstances above.

**Commands:**
- `make bootstrap` - Full bootstrap rebuild (ask user first)
- `make test-bootstrap` - Test bootstrap mechanism
- `make dev` - Automatically bootstraps only if necessary

### Test Commands
```bash
dune runtest dir/              # Run tests in a directory
dune runtest dir/test.t        # Run a cram test
dune runtest dir/test.ml       # Run an inline or expect test
```

**Output Handling:** Dune is generally silent when building and only outputs
errors. Avoid truncating output from `dune build` and `dune runtest`. If
`dune runtest` gives too much output, run something of smaller scope instead.

**Test Promotion:** When tests fail due to output changes, ask user before
running `dune promote` to accept changes.

**Experimentation:** Create cram tests (`.t` files) to experiment with how
things work. Don't run commands manually - run them through `dune runtest` to
capture and verify behavior.

**Printf Debugging:** When confused about behavior, use `Dune_console`
(commonly aliased as `Console`) for debugging:
```ocaml
Console.printf "something: %s" (Something.to_dyn something |> Dyn.to_string);
```
This output will appear in cram test diffs, making it easy to observe values.

**Trace Inspection:** Use `dune trace cat | jq` to inspect build traces. See
`doc/hacking.rst` for details on using jq with traces in cram tests.

### Development Guidelines
- Always verify changes build with `dune build @check`
- Run `dune fmt` to ensure code formatting (requires ocamlformat)
- Keep lines under 80 characters
- Only add comments for complex algorithms or when explicitly requested
- Don't disable warnings or tests unless prompted
- Use pattern-matching and functional programming idioms
- Avoid `assert false` and other unreachable code

## Code Conventions

### OCaml Patterns
- Every `.ml` file needs corresponding `.mli` (except type-only files)
- Use `Code_error.raise` instead of `assert false` for better error messages
- Qualify record construction: `{ Module.field = value }`
- Prefer destructuring over projection: `let { Module.field; _ } = record` not
  `record.Module.field`
- Pattern match exhaustively in `to_dyn` functions: `let to_dyn {a; b; c} = ...`

## Critical Constraints

**NEVER do these things:**
- NEVER create files unless absolutely necessary
- NEVER proactively create documentation files (*.md) or README files
- NEVER stage or commit changes unless explicitly requested
- NEVER run `dune clean`
- NEVER use the `--force` argument
- NEVER try to build dune manually to run a test

**ALWAYS do these things:**
- ALWAYS prefer editing existing files over creating new ones
- ALWAYS ask user before running `dune promote` or `make bootstrap`
