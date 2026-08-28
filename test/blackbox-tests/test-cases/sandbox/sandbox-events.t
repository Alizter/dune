Demonstrate sandbox events:

  $ make_dune_project "3.22"

  $ touch dependency
  $ cat >dune <<EOF
  > (rule
  >  (alias foo)
  >  (deps dependency (sandbox always))
  >  (action (bash "true")))
  > EOF

  $ dune build @foo

  $ dune trace cat | jq_dune '
  >   select(.cat == "sandbox")
  > | del(.ts,.dur, .args.queued)
  > | censorDigestDir
  > '
  {
    "cat": "sandbox",
    "name": "materialize-dependencies",
    "args": {
      "loc": "dune:1",
      "dir": "_build/.sandbox/$DIGEST",
      "mode": "symlink",
      "dependencies": 1
    }
  }
  {
    "cat": "sandbox",
    "name": "create",
    "args": {
      "loc": "dune:1",
      "dir": "_build/.sandbox/$DIGEST"
    }
  }
  {
    "cat": "sandbox",
    "name": "extract",
    "args": {
      "loc": "dune:1",
      "dir": "_build/.sandbox/$DIGEST"
    }
  }
  {
    "cat": "sandbox",
    "name": "destroy",
    "args": {
      "loc": "dune:1",
      "dir": "_build/.sandbox/$DIGEST"
    }
  }
