Without an explicit solve_for_platforms field, dune pkg lock solves only for the
current platform reported by OS polling.

  $ mkrepo
  $ add_mock_repo_if_needed

  $ mkpkg linux-only <<'EOF'
  > available: os = "linux"
  > EOF
  $ mkpkg macos-only <<'EOF'
  > available: os = "macos"
  > EOF

  $ cat >dune-project <<'EOF'
  > (lang dune 3.18)
  > EOF
  $ cat >x.opam <<'EOF'
  > opam-version: "2.0"
  > depends: [
  >   "linux-only" {os = "linux"}
  >   "macos-only" {os = "macos"}
  > ]
  > EOF

  $ export DUNE_CONFIG__OS=linux DUNE_CONFIG__ARCH=x86_64
  $ export DUNE_CONFIG__OS_FAMILY=debian DUNE_CONFIG__OS_DISTRIBUTION=ubuntu
  $ export DUNE_CONFIG__OS_VERSION=24.11
  $ dune pkg lock >/dev/null 2>&1
  $ ls dune.lock/*.pkg
  dune.lock/linux-only.0.0.1.pkg

Automatic lock generation uses the same default.

  $ rm -rf dune.lock
  $ enable_pkg
  $ build_pkg linux-only

An explicit solve_for_platforms field is authoritative. The detected Linux
platform is not added to or merged into the requested macOS platform.

  $ cat >dune-workspace <<EOF
  > (lang dune 3.20)
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > (lock_dir
  >  (repositories mock)
  >  (solve_for_platforms
  >   ((arch arm64) (os macos))))
  > (pkg enabled)
  > EOF

  $ dune pkg lock >/dev/null 2>&1
  $ ls dune.lock/*.pkg
  dune.lock/macos-only.0.0.1.pkg

Automatic lock generation also preserves the explicit platform set.

  $ rm -rf dune.lock
  $ DUNE_CONFIG__OS=macos DUNE_CONFIG__ARCH=arm64 build_pkg macos-only
