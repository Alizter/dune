Test for packages with an extra-source file with the same name as a
file in the package's source.

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1)
  > (source
  >  (copy $PWD/foo-source))
  > (extra_sources
  >  (foo.txt
  >   (fetch
  >    (url file://$PWD/foo.txt))))
  > (build (run cat foo.txt))
  > EOF

  $ mkdir -p foo-source
  $ echo "from source" > foo-source/foo.txt

  $ echo "from extra source" > foo.txt

  $ cat > dune-project <<EOF
  > (lang dune 3.16)
  > (package
  >  (allow_empty)
  >  (name a)
  >  (depends foo))
  > EOF

The extra source overlays the immutable primary source inside the recipe's copy
sandbox:

  $ build_pkg foo
  from extra source

Native packages see the same overlay order before their projects are loaded:
primary source, then lock files, then ordered extra sources. Files added by an
overlay participate in module discovery, while the primary `_fetch` input stays
unchanged.

  $ mkdir overlay-source
  $ cat > overlay-source/dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name overlay))
  > EOF
  $ cat > overlay-source/dune <<'EOF'
  > (library (public_name overlay))
  > EOF
  $ cat > overlay-source/overlay.ml <<'EOF'
  > let message =
  >   String.concat ":" [ Extra.message; Lock_only.message; Added.message ]
  > EOF
  $ cat > overlay-source/extra.ml <<'EOF'
  > let message = "primary"
  > EOF
  $ cat > overlay-source/lock_only.ml <<'EOF'
  > let message = "primary"
  > EOF
  $ cat > extra.ml <<'EOF'
  > let message = "extra"
  > EOF

  $ make_lockpkg overlay <<EOF
  > (version 1)
  > (source (copy $PWD/overlay-source))
  > (extra_sources (extra.ml (copy $PWD/extra.ml)))
  > (build (run dune build -p overlay @install))
  > EOF
  $ make_lockpkg_file overlay extra.ml <<'EOF'
  > let message = "lock"
  > EOF
  $ make_lockpkg_file overlay lock_only.ml <<'EOF'
  > let message = "lock"
  > EOF
  $ make_lockpkg_file overlay added.ml <<'EOF'
  > let message = "added"
  > EOF

  $ cat > dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name app) (allow_empty) (depends overlay))
  > EOF
  $ cat > dune <<'EOF'
  > (dirs :standard \ overlay-source)
  > (executable (name main) (libraries overlay))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Overlay.message
  > EOF

  $ dune exec ./main.exe
  extra:lock:added

  $ cat _build/_default+lockfile/pkg/overlay/extra.ml
  let message = "extra"
  $ cat _build/_default+lockfile/pkg/overlay/lock_only.ml
  let message = "lock"
  $ cat _build/_default+lockfile/pkg/overlay/added.ml
  let message = "added"
  $ raw_extra=$(find _build/_fetch -path '*/dir/extra.ml')
  $ test -n "$raw_extra" && cat "$raw_extra"
  let message = "primary"
