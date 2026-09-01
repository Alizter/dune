A compilation error in a native locked package reports the location of the
materialized source in the mounted package context.

  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF

  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends broken))
  > EOF

  $ cat > dune <<'EOF'
  > (dirs :standard \ broken-source missing-library-source)
  > (executable
  >  (name main)
  >  (libraries broken))
  > EOF

  $ cat > main.ml <<'EOF'
  > let () = print_int Broken.value
  > EOF

  $ mkdir broken-source
  $ cat > broken-source/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name broken))
  > EOF

  $ cat > broken-source/dune <<'EOF'
  > (library
  >  (name broken)
  >  (public_name broken))
  > EOF

  $ cat > broken-source/broken.ml <<'EOF'
  > let value =
  > EOF

  $ make_lockdir
  $ make_lockpkg broken <<EOF
  > (version 1.0)
  > (source (copy $PWD/broken-source))
  > EOF

  $ dune build ./main.exe 2>&1 | sanitize_pkg_digest broken.1.0
  File "../_default+lockfile/pkg/broken.1.0-DIGEST_HASH/broken.ml", line 2, characters 0-0:
  Error: Syntax error
  [1]

A missing library is reported from the package's authored dune file.

  $ mkdir missing-library-source
  $ cat > missing-library-source/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package (name broken))
  > EOF

  $ cat > missing-library-source/dune <<'EOF'
  > (library
  >  (name broken)
  >  (public_name broken)
  >  (libraries does-not-exist))
  > EOF

  $ cat > missing-library-source/broken.ml <<'EOF'
  > let value = 42
  > EOF

  $ make_lockpkg broken <<EOF
  > (version 1.0)
  > (source (copy $PWD/missing-library-source))
  > EOF

  $ dune build ./main.exe 2>&1 | sanitize_pkg_digest broken.1.0 | censor
  File "_build/_fetch/url/$DIGEST/dir/dune", line 4, characters 12-26:
  4 |  (libraries does-not-exist))
                  ^^^^^^^^^^^^^^
  Error: Library "does-not-exist" not found.
  -> required by library "broken" in
     _build/_default+lockfile/pkg/broken.1.0-DIGEST_HASH
  -> required by executable main in dune:3
  -> required by _build/default/.main.eobjs/native/dune__exe__Main.cmx
  -> required by _build/default/main.exe
  [1]
