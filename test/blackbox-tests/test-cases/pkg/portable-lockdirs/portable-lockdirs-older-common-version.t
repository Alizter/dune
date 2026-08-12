When one platform can only use an older version of a package and another
platform prefers a newer one, the cross-platform version equality constraint
forces the older common version everywhere.

  $ mkrepo
  $ add_mock_repo_if_needed

Two versions of foo; foo.2 is only available on non-linux platforms:
  $ mkpkg foo 1 <<EOF
  > build: [
  >   ["mkdir" "-p" share "%{lib}%/%{name}%"]
  >   ["touch" "%{lib}%/%{name}%/META"] # needed for dune to recognize this as a library
  >   ["sh" "-c" "echo %{version}% > %{share}%/version"]
  > ]
  > EOF
  $ mkpkg foo 2 <<EOF
  > build: [
  >   ["mkdir" "-p" share "%{lib}%/%{name}%"]
  >   ["touch" "%{lib}%/%{name}%/META"] # needed for dune to recognize this as a library
  >   ["sh" "-c" "echo %{version}% > %{share}%/version"]
  > ]
  > available: os != "linux"
  > EOF

A package depending on foo without any version constraint:
  $ mkpkg bar <<EOF
  > depends: [
  >  "foo"
  > ]
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.18)
  > (package
  >  (name x)
  >  (depends bar))
  > EOF

  $ cat > x.ml <<EOF
  > let () = print_endline "Hello, World!"
  > EOF

  $ cat > dune <<EOF
  > (executable
  >  (public_name x)
  >  (libraries foo))
  > EOF

Linux can only take foo.1 while macOS prefers foo.2; the joint solve selects
foo.1 for every platform:
  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - bar.0.0.1
  - foo.1

Build as if we were on linux and confirm that version 1 of foo was built:
  $ export DUNE_CONFIG__OS=linux DUNE_CONFIG__ARCH=arm64 DUNE_CONFIG__OS_FAMILY=debian DUNE_CONFIG__OS_DISTRIBUTION=ubuntu DUNE_CONFIG__OS_VERSION=24.11
  $ dune build
  $ cat $pkg_root/$(dune pkg print-digest foo)/target/share/version
  1

  $ dune clean

Build as if we were on macos: foo.2 is available and preferred there, but the
cross-platform equality constraint selects the common version foo.1.
  $ export DUNE_CONFIG__OS=macos DUNE_CONFIG__ARCH=x86_64 DUNE_CONFIG__OS_FAMILY=homebrew DUNE_CONFIG__OS_DISTRIBUTION=homebrew DUNE_CONFIG__OS_VERSION=15.3.1
  $ dune build
  $ cat $pkg_root/$(dune pkg print-digest foo)/target/share/version
  1
