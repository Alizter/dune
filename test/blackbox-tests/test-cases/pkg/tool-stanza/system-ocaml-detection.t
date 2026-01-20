Test that tools can be installed when using system OCaml (no project lockdir).

When a project uses system OCaml instead of package management, dune should
detect the system compiler and use it for tool constraints.

Set up a mock repository with a simple tool.

  $ mkrepo

Create a simple tool package with no dependencies:

  $ mkpkg my-tool <<EOF
  > build: [
  >   ["sh" "-c" "echo '#!/bin/sh\necho hello from my-tool' > my-tool && chmod +x my-tool"]
  > ]
  > install: [
  >   ["install" "my-tool" "%{bin}%/my-tool"]
  > ]
  > EOF

Set up a workspace that uses the mock repo. Configure the tool lock to use mock repo.

  $ cat > dune-workspace <<EOF
  > (lang dune 3.16)
  > (repository
  >  (name mock)
  >  (url file://$(pwd)/mock-opam-repository))
  > (lock_dir
  >  (path _build/.tools.lock/my-tool)
  >  (repositories mock))
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.16)
  > (package
  >  (name foo)
  >  (allow_empty))
  > EOF

  $ cat > dune <<EOF
  > EOF

Now try to install the tool:

  $ dune tools add my-tool 2>&1
  Solution for _build/.tools.lock/my-tool:
  - my-tool.0.0.1

The tool was locked and built successfully. The lock directory was created:

  $ cat _build/.tools.lock/my-tool/lock.dune | head -1
  (lang package 0.1)

  $ cat _build/.tools.lock/my-tool/my-tool.pkg | head -1
  (version 0.0.1)

Run the tool:

  $ dune tools run my-tool 2>&1
       Running 'my-tool'
  hello from my-tool
