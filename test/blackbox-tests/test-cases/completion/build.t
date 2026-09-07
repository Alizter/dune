Test semantic shell completion for `dune build`.

Completion failures are not hidden by the protocol parser.

  $ DUNE_COMPLETE_BIN=false dune_complete build ""
  [1]

  $ make_directory_targets_project 3.21
  $ mkdir -p sub single/child empty source-only
  $ touch source.input source-only/input
  $ cat > dune <<'EOF'
  > (rule
  >  (targets generated.txt generated.log)
  >  (action
  >   (progn
  >    (write-file generated.txt txt)
  >    (write-file generated.log log))))
  > (rule
  >  (targets (dir generated-dir))
  >  (action (run mkdir generated-dir)))
  > (alias
  >  (name deploy))
  > EOF
  $ cat > sub/dune <<'EOF'
  > (rule
  >  (target nested.out)
  >  (action (write-file nested.out nested)))
  > (alias
  >  (name publish))
  > EOF
  $ cat > single/child/dune <<'EOF'
  > (rule
  >  (target only.output)
  >  (action (write-file only.output only)))
  > EOF

Completion evaluates candidates without creating the default trace file.

  $ dune_complete build "generated" >/dev/null
  $ test ! -e _build/trace.csexp

File and directory candidates come from the same rule listing used by `dune
show targets` and unknown-target hints. Source files are omitted unless `--all`
is passed to `dune show targets`.

  $ dune show targets 2>&1 | grep -E '^(generated|source)'
  generated-dir/
  generated.log
  generated.txt
  $ dune show targets --all 2>&1 | grep -E '^(generated|source)'
  generated-dir/
  generated.log
  generated.txt
  source.input
  $ dune build generated.tx
  Error: Don't know how to build generated.tx
  Hint: did you mean generated.txt?
  [1]
  $ dune_complete build "generated"
  generated-dir/
  generated.log
  generated.txt
  $ dune_complete build "source"

Source directories remain open so completion can inspect the targets within
them. Completion stops at a branch, but follows a uniquely matching chain of
single-child directories in full. Directories without generated targets are
omitted.

  $ dune_complete build "sub"
  sub/nested.out
  $ dune_complete build "sub/n"
  sub/nested.out
  $ (cd sub && dune_complete build --root .. "n")
  nested.out
  $ dune_complete build "sing"
  single/child/only.output
  $ dune_complete build "empty"
  $ dune_complete build "source-only"
  $ dune_complete build "does/not/exist/"

Aliases support both recursive (`@`) and non-recursive (`@@`) command-line
forms, including aliases in subdirectories.

  $ dune_complete build "@dep"
  @deploy
  $ dune_complete build "@@dep"
  @@deploy
  $ dune_complete build "@sub"
  @sub/
  $ dune_complete build "@sub/p"
  @sub/publish
  $ dune_complete build "@@sub/p"
  @@sub/publish

The equivalent alias options complete names without adding the positional
argument markers.

  $ dune_complete build --alias "dep"
  deploy
  $ dune_complete build --alias "sub/p"
  sub/publish
  $ dune_complete build --alias-rec "sub/p"
  sub/publish

Completion queries a running watch server when it owns the build directory.
The request also observes dune-file changes received by the server's file
watcher.

  $ start_dune
  $ dune_complete build "generated"
  generated-dir/
  generated.log
  generated.txt
  $ dune_complete build "@dep"
  @deploy
  $ cat >> dune <<'EOF'
  > (rule
  >  (target watched.out)
  >  (action (write-file watched.out watched)))
  > (alias
  >  (name watched-alias))
  > EOF
  $ dune_complete build "watched"
  watched.out
  $ dune_complete build "@watched"
  @watched-alias
  $ with_timeout dune rpc ping
  Server appears to be responding normally
  $ stop_dune_quiet
