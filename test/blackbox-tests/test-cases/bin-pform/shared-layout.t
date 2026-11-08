Two rules with the same set of %{bin:...} deps share a single
.binaries directory (keyed by the digest of the sorted unique bin
names).

  $ make_mypkg_bin_project

  $ cat >dune <<'EOF'
  > (rule
  >  (deps %{bin:mybin})
  >  (action
  >   (with-stdout-to out1
  >    (bash "echo $PATH"))))
  > (rule
  >  (deps %{bin:mybin})
  >  (action
  >   (with-stdout-to out2
  >    (bash "echo $PATH"))))
  > EOF

  $ dune build out1 out2

Each action has a sandbox-local copy of the same binary layout:

  $ one=$(env_added "$(cat _build/default/out1)" "$PATH")
  $ two=$(env_added "$(cat _build/default/out2)" "$PATH")
  $ echo "$one" | censor
  $PWD/_build/.sandbox/$DIGEST1/install/default/.binaries/$DIGEST2
  $ echo "$two" | censor
  $PWD/_build/.sandbox/$DIGEST1/install/default/.binaries/$DIGEST2
  $ test "${one##*/}" = "${two##*/}"
