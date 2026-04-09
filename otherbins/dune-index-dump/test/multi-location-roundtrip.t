The binary must faithfully dump all locations per UID.
Verify by encoding to csexp, decoding, and re-encoding to sexp — the
output should be identical to the direct sexp dump.

  $ cat > dune-project <<EOF
  > (lang dune 3.23)
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (name mylib)
  >  (modules mylib helper consumer))
  > EOF

  $ cat > helper.ml <<EOF
  > let f x = x + 1
  > EOF

  $ cat > helper.mli <<EOF
  > val f : int -> int
  > EOF

consumer.ml uses Helper.f on a different line:

  $ cat > consumer.ml <<EOF
  > (* padding *)
  > (* more padding *)
  > (* even more *)
  > let result = Helper.f 42
  > EOF

  $ cat > consumer.mli <<EOF
  > val result : int
  > EOF

  $ cat > mylib.ml <<EOF
  > let _ = Consumer.result
  > EOF

  $ cat > mylib.mli <<EOF
  > EOF

  $ dune build @ocaml-index

Direct sexp dump:

  $ dune-index-dump --sexp _build/default/.mylib.objs/cctx.ocaml-index > direct.sexp

Round-trip: encode to csexp, decode back to sexp:

  $ dune-index-dump _build/default/.mylib.objs/cctx.ocaml-index | dune-index-dump --decode > roundtrip.sexp

They should be identical:

  $ diff direct.sexp roundtrip.sexp
