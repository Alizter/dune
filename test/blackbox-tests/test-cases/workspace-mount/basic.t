A (mount ...) field in a context stanza spawns an additional internal
build context whose source tree is rooted at the given external path.

Set up the mount source outside the workspace so the only path by
which dune can reach it is the mount itself.

  $ mkdir other
  $ cat > other/dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > other/dune << EOF
  > (rule
  >  (target greeting)
  >  (action (with-stdout-to %{target} (echo "hello from mount"))))
  > EOF

The workspace lives in a sibling directory and declares the mount.

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../other)))
  > EOF

Both contexts materialise: the workspace's [default] and the mount's
[default.other].

  $ dune build
  $ ls _build | grep -E '^default' | sort
  default
  default.other

The mount's [dune] file is evaluated against the mount context, so its
rule is registered under [_build/default.other/].

  $ dune rules --format=json _build/default.other/greeting | jq
  [
    {
      "deps": [],
      "targets": {
        "files": [
          "_build/default.other/greeting"
        ],
        "directories": []
      },
      "context": "default.other",
      "action": [
        "chdir",
        "_build/default.other",
        [
          "with-stdout-to",
          "greeting",
          [
            "echo",
            "hello from mount"
          ]
        ]
      ]
    }
  ]

Building the mount-context target runs the rule and writes the
artefact under the mount context's build dir.

  $ dune build _build/default.other/greeting
  $ cat _build/default.other/greeting
  hello from mount

The workspace context does not see the mount's sources, so building
the same path under [_build/default] fails.

  $ dune build _build/default/greeting 2>&1 | head -1
  Error: Don't know how to build _build/default/greeting
  [1]
