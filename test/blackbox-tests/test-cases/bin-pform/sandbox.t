%{bin:NAME} deps under sandboxing.

The generated .binaries PATH entry must be relocated into the sandbox,
where the declared tools have been copied.

  $ make_mypkg_bin_project

  $ cat >dune <<'EOF'
  > (rule
  >  (deps (sandbox always) %{bin:mybin})
  >  (action
  >   (with-stdout-to out
  >    (bash "pwd; command -v mybin; mybin"))))
  > EOF

Both the working directory and the resolved mybin path are sandboxed:

  $ dune build out --sandbox symlink 2>&1
  $ cat _build/default/out | censor
  $PWD/_build/.sandbox/$DIGEST1/default
  $PWD/_build/.sandbox/$DIGEST1/install/default/.binaries/$DIGEST2/mybin
  hello from mybin

The rule's deps include the build artifact and the .binaries
symlink. Both are paths under the un-sandboxed _build/:

  $ dune rules --format=json _build/default/out \
  >   | jq_dune '.[] | ruleDepFilePaths' \
  >   | grep mybin | censor
  "_build/default/src/mybin.bc"
  "_build/install/default/.binaries/$DIGEST/mybin"
