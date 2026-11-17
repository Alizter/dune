Which opaque locked packages a library lookup builds. A package built by its
recipe only reveals its libraries once it is installed, so looking in one
means building it. The lookup tries the package named like the library, then
the compiler's own libraries, and only then the other packages.

  $ make_lockdir
  $ (make_dune_project 3.25)
  $ lib() {
  >   cat <<EOF
  > (version 1.0)
  > (build
  >  (progn
  >   (run echo built $1)
  >   (write-file $2.ml "let v = \"$2\"")
  >   (run ocamlc -a -o $2.cma $2.ml)
  >   (run ocamlopt -a -o $2.cmxa $2.ml)
  >   (write-file META "archive(byte) = \"$2.cma\"\narchive(native) = \"$2.cmxa\"\n")
  >   (write-file $1.install "lib: [ \"META\" \"$2.cmi\" \"$2.cma\" \"$2.cmx\" \"$2.cmxa\" \"$2.a\" ]")))
  > EOF
  > }

[first] installs a library of its own name:

  $ lib first first | make_lockpkg first

[second] installs a library under another name, [mismatch]:

  $ make_lockpkg second <<'EOF'
  > (version 1.0)
  > (build
  >  (progn
  >   (run echo built second)
  >   (run mkdir mismatch)
  >   (write-file mismatch.ml "let v = \"mismatch\"")
  >   (run ocamlc -a -o mismatch.cma mismatch.ml)
  >   (run ocamlopt -a -o mismatch.cmxa mismatch.ml)
  >   (write-file META "archive(byte) = \"mismatch.cma\"\narchive(native) = \"mismatch.cmxa\"\n")
  >   (write-file second.install "lib_root: [ \"META\" {\"mismatch/META\"} \"mismatch.cmi\" {\"mismatch/mismatch.cmi\"} \"mismatch.cma\" {\"mismatch/mismatch.cma\"} \"mismatch.cmx\" {\"mismatch/mismatch.cmx\"} \"mismatch.cmxa\" {\"mismatch/mismatch.cmxa\"} \"mismatch.a\" {\"mismatch/mismatch.a\"} ]")))
  > EOF

[other] installs no library:

  $ make_lockpkg other <<'EOF'
  > (version 1.0)
  > (build (run echo built other))
  > EOF

  $ try() {
  >   rm -rf _build
  >   echo "(executable (name main) (libraries $1))" > dune
  >   dune build ./main.exe 2>&1 | sort
  > }

A library of the compiler:

  $ echo 'let _ = Unix.getpid' > main.ml
  $ try unix

A library named after its package:

  $ echo 'let _ = First.v' > main.ml
  $ try first
  built first

A library whose name differs from its package needs the scan:

  $ echo 'let _ = Mismatch.v' > main.ml
  $ try mismatch
  built first
  built other
  built second

So does a library that nothing provides:

  $ rm main.ml
  $ touch main.with.ml main.without.ml
  $ try '(select main.ml from (absent -> main.with.ml) (-> main.without.ml))'
  built first
  built other
  built second

A package-owned workspace requester currently falls back to undeclared opaque
providers. Record both a named lookup and a differently named provider before
the symmetric-discovery spike removes this fallback.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name app) (dir .))
  > EOF
  $ echo 'let () = print_endline "selected"' > main.with.ml
  $ echo 'let () = print_endline "fallback"' > main.without.ml
  $ try '(select main.ml from (first -> main.with.ml) (-> main.without.ml))'
  built first
  $ _build/default/main.exe
  selected
  $ test -e _build/default/.pkg/first/_install/cookie
  $ try '(select main.ml from (mismatch -> main.with.ml) (-> main.without.ml))'
  built first
  built other
  built second
  $ _build/default/main.exe
  selected
  $ test -e _build/default/.pkg/other/_install/cookie

An absolute findlib configuration must not provide a second route around the
requester's opaque eligibility, either cold or after explicit installation.

  $ touch findlib.conf
  $ export OCAMLFIND_CONF="$PWD/findlib.conf"
  $ try '(select main.ml from (first -> main.with.ml) (-> main.without.ml))'
  built first
  $ _build/default/main.exe
  selected
  $ test -e _build/default/.pkg/first/_install/cookie
  $ try '(select main.ml from (mismatch -> main.with.ml) (-> main.without.ml))'
  built second
  $ _build/default/main.exe
  selected
  $ test ! -e _build/default/.pkg/other/_install/cookie
  $ build_pkg first > warm-first.log 2>&1
  $ build_pkg second > warm-second.log 2>&1
  $ test -f _build/default/.pkg/first/_install/cookie
  $ test -f _build/default/.pkg/second/_install/cookie
  $ echo '(executable (name main) (libraries (select main.ml from (first -> main.with.ml) (-> main.without.ml))))' > dune
  $ dune build main.exe
  $ _build/default/main.exe
  selected
  $ echo '(executable (name main) (libraries (select main.ml from (mismatch -> main.with.ml) (-> main.without.ml))))' > dune
  $ dune build main.exe
  $ _build/default/main.exe
  selected

Compiler libraries remain available with the same findlib configuration.

  $ echo 'let _ = Unix.getpid' > main.ml
  $ try unix
  $ rm main.ml
  $ unset OCAMLFIND_CONF

A declared transitive dependency still permits the differently named provider.
The unrelated packages need not be built to discover it.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name app) (dir .) (depends bridge))
  > EOF
  $ make_lockpkg bridge <<'EOF'
  > (version 1.0)
  > (depends second)
  > (build (run echo built bridge))
  > EOF
  $ try '(select main.ml from (mismatch -> main.with.ml) (-> main.without.ml))'
  built bridge
  built second
  $ _build/default/main.exe
  selected
  $ test ! -e _build/default/.pkg/first/_install/cookie
  $ test ! -e _build/default/.pkg/other/_install/cookie

An opaque library's requirements use its provider's scope, not the consumer's.
The consumer declares both first and second, but first does not declare second.

  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name app) (dir .) (depends first second))
  > EOF
  $ make_lockpkg first <<'EOF'
  > (version 1.0)
  > (build
  >  (progn
  >   (run echo built first)
  >   (write-file first.ml "let v = \"first\"")
  >   (run ocamlc -a -o first.cma first.ml)
  >   (run ocamlopt -a -o first.cmxa first.ml)
  >   (write-file META "requires = \"mismatch\"\narchive(byte) = \"first.cma\"\narchive(native) = \"first.cmxa\"\n")
  >   (write-file first.install "lib: [ \"META\" \"first.cmi\" \"first.cma\" \"first.cmx\" \"first.cmxa\" \"first.a\" ]")))
  > EOF
  $ echo '(executable (name main) (libraries first))' > dune
  $ echo 'let () = print_endline First.v' > main.ml
  $ rm -rf _build
  $ dune build main.exe > provider.log 2>&1
  [1]
  $ grep '^Error: Library' provider.log
  Error: Library "mismatch" not found.
  $ test ! -e _build/default/main.exe
  $ test ! -e _build/default/.pkg/second/_install/cookie

Declaring the dependency on its provider repairs the lookup.

  $ cp dune.lock/first.pkg first.pkg
  $ { echo '(depends second)'; cat first.pkg; } > dune.lock/first.pkg
  $ dune build main.exe 2>&1 | sort
  built first
  built second
  $ _build/default/main.exe
  first
