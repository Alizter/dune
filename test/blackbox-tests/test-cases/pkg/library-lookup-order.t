Which opaque locked packages a library lookup builds. A package built by its
recipe only reveals its libraries once it is installed, so looking in one
means building it. The lookup tries the package named like the library, then
the compiler's own libraries, and only then the other packages.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > EOF
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
