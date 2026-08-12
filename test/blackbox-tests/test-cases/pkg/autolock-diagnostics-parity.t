The autolock path must produce the same solver-conflict diagnostics as the
manual `dune pkg lock` path.

Note: the autolock path reports the raw solver error without the
requested-platform-set wrapper that the manual path adds. That wrapper is a
known remaining gap (the narrowing hint is implemented); this test pins the
diagnostic content that the two paths share.

  $ mkrepo
  $ add_mock_repo_if_needed

Make some packages that can't be coinstalled:
  $ mkpkg a <<EOF
  > depends: [
  >  "c" {= "0.1"}
  > ]
  > EOF

  $ mkpkg b <<EOF
  > depends: [
  >  "c" {= "0.2"}
  > ]
  > EOF

  $ mkpkg c "0.2"

  $ cat > dune-project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name foo)
  >  (depends a b))
  > EOF

  $ enable_pkg

Manual locking reports the solver conflict, wrapped with the requested
platform set:
  $ dune pkg lock
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  The dependency solver failed to find a solution for the following platforms:
  - arch = x86_64; os = linux
  - arch = arm64; os = linux
  - arch = x86_64; os = macos
  - arch = arm64; os = macos
  ...with this error:
  Couldn't solve the package dependency formula.
  Selected candidates: a.0.0.1 b.0.0.1 foo.dev
  - c -> (problem)
      a 0.0.1 requires = 0.1
      Rejected candidates:
        c.0.2: Incompatible with restriction: = 0.1
  [1]

Autolocking reports the same solver-conflict content:
  $ dune build @pkg-install 2>&1
  File "default/.lock/_unknown_", line 1, characters 0-0:
  Error: Couldn't solve the package dependency formula.
  Selected candidates: a.0.0.1 b.0.0.1 foo.dev
  - c -> (problem)
      a 0.0.1 requires = 0.1
      Rejected candidates:
        c.0.2: Incompatible with restriction: = 0.1
  [1]
