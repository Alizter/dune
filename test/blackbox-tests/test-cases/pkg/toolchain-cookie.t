Test that compiler cookies are stored in the toolchain directory and persist
across _build deletions. Uses a fake local compiler package.

--------------------------------------------------------------------------------
* Fake compiler setup

  $ export DUNE_CACHE_ROOT="$PWD/cache"
  $ export DUNE_CONFIG__TOOLCHAINS=enabled
  $ mkdir project && cd project

Create lockdir with ocaml-base-compiler as the toolchain:

  $ make_lockdir
  $ cat >> dune.lock/lock.dune << EOF
  > (ocaml ocaml-base-compiler)
  > EOF

  $ make_lockpkg ocaml-base-compiler << 'EOF'
  > (version 5.2.0)
  > (install
  >  (progn
  >   (run env TOOLCHAIN_INSTALL=1 true)
  >   (run mkdir -p %{prefix}/bin)
  >   (run cp ocamlc %{prefix}/bin/ocamlc)
  >   (run cp ocamlopt %{prefix}/bin/ocamlopt)
  >   (run cp ocamldep %{prefix}/bin/ocamldep)))
  > EOF

  $ mkdir -p dune.lock/ocaml-base-compiler.files
  $ for tool in ocamlc ocamlopt ocamldep; do
  >   real_tool=$(command -v $tool)
  >   cat > dune.lock/ocaml-base-compiler.files/$tool << EOF
  > #!/bin/sh
  > env FAKE_$tool=1 true
  > exec $real_tool "\$@"
  > EOF
  >   chmod +x dune.lock/ocaml-base-compiler.files/$tool
  > done

  $ cat > dune-project << EOF
  > (lang dune 3.22)
  > EOF

  $ cat > dune << EOF
  > (executable
  >  (name foo))
  > EOF

  $ cat > foo.ml << EOF
  > print_endline "Hello, World!"
  > EOF

Helper to check if toolchain installation was run (by looking for
TOOLCHAIN_INSTALL in trace):

  $ toolchain_installation_was_run() {
  >   trace=$(dune trace cat) \
  >     || { echo "dune trace cat failed" >&2; return 1; }
  >   args=$(echo "$trace" | jq -r 'select(.cat == "process") | .args.process_args[]') \
  >     || { echo "jq parsing failed" >&2; return 1; }
  >   count=$(echo "$args" | grep TOOLCHAIN_INSTALL | wc -l)
  >   echo $count
  > }

Helper to verify foo.exe runs and was compiled using the toolchain compiler:

  $ check_foo() {
  >   dune exec ./foo.exe \
  >     || { echo "foo.exe failed to run" >&2; return 1; }
  >   dune trace cat \
  >     | jq -r 'select(.cat == "process") | .args.prog' \
  >     | grep -q toolchains \
  >     || { echo "expected toolchain compiler in trace" >&2; return 1; }
  > }

Helper to find the external cookie path, verifying it belongs to the unique
toolchain existing in cache:

  $ get_external_cookie() {
  >   cookie=$(echo ../cache/toolchains/ocaml-base-compiler.*/cookie)
  >   test $(echo $cookie | wc -w) -eq 1 \
  >     || { echo "expected unique toolchain in cache" >&2; return 1; }
  >   test -f $cookie \
  >     || { echo "external cookie not found" >&2; return 1; }
  >   echo $cookie
  > }

Helper to check both the internal and external cookies exist in both _build and
cache respectively, and are identical:

  $ check_cookies() {
  >   external=$(get_external_cookie) \
  >     || return 1
  >   internal=$(echo _build/_private/default/.pkg/ocaml-base-compiler.*/target/cookie)
  >   test $(echo $internal | wc -w) -eq 1 \
  >     || { echo "expected unique toolchain in _build" >&2; return 1; }
  >   cmp $external $internal \
  >     || { echo "cookies differ" >&2; return 1; }
  > }

--------------------------------------------------------------------------------
* Initial build

  $ dune build @pkg-install
  $ toolchain_installation_was_run
  1
  $ check_cookies

--------------------------------------------------------------------------------
* Restore from cache

Delete _build and rebuild (should restore from cache, not rebuild):

  $ rm -rf _build
  $ dune build @pkg-install

Toolchain was not reinstalled, cookies exist and match:

  $ toolchain_installation_was_run
  0
  $ check_cookies

--------------------------------------------------------------------------------
* Sabotage 1: delete the external target but keep the cookie

Should rebuild from source.

  $ rm -rf ../cache/toolchains/ocaml-base-compiler.*/target
  $ rm -rf _build
  $ dune build @pkg-install
  $ toolchain_installation_was_run
  1
  $ check_cookies
  $ check_foo
  Hello, World!

--------------------------------------------------------------------------------
* Sabotage 2: delete the external cookie but keep the target

Should rebuild from source.

  $ rm -f $(get_external_cookie)
  $ rm -rf _build
  $ dune build @pkg-install
  $ toolchain_installation_was_run
  1
  $ check_cookies
  $ check_foo
  Hello, World!

--------------------------------------------------------------------------------
* Sabotage 3: delete both external cookie and target

Should rebuild from source.

  $ rm -rf ../cache/toolchains/ocaml-base-compiler.*/target
  $ rm -f $(get_external_cookie)
  $ rm -rf _build
  $ dune build @pkg-install
  $ toolchain_installation_was_run
  1
  $ check_cookies
  $ check_foo
  Hello, World!

--------------------------------------------------------------------------------
* Sabotage 4: corrupt the external cookie with garbage

# CR-someday alizter: The error message "unable to load" is not helpful. We
# should detect cookie corruption earlier and provide a better message
# indicating which cookie file is corrupted and suggesting to delete it or
# rebuild.

Cookie exists but is malformed. The restore action copies it successfully.
The error surfaces when dune tries to read the cookie for toolchain setup.

  $ echo "garbage" > $(get_external_cookie)
  $ rm -rf _build
  $ dune build @pkg-install 2>&1 | grep -o "Error:.*"
  Error: unable to load

The internal cookie got the garbage (corruption propagated), so check_cookies
passes:

  $ check_cookies

But the cookies are both invalid, causing the build of foo to fail:

  $ check_foo 2>&1 | grep -o "Error:.*"
  Error: unable to load

Removing only the external cookie is enough to trigger a rebuild, which
overwrites the corrupted internal cookie in _build. This demonstrates the
we can safely recover from this situation:

  $ rm -f $(get_external_cookie)
  $ dune build @pkg-install
  $ check_cookies
  $ check_foo
  Hello, World!

