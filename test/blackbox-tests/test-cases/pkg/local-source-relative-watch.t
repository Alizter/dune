Relative local package URLs keep tracking workspace filesystem events after
their backing has been represented as an absolute external package location.

  $ make_lockdir
  $ cat > dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name main) (dir .) (depends foo))
  > EOF
  $ echo '(executable (name main) (libraries foo))' > dune
  $ echo 'let () = print_endline Foo.message' > main.ml
  $ mkdir _source
  $ cat > _source/dune-project <<'EOF'
  > (lang dune 3.25)
  > (package (name foo))
  > EOF
  $ echo '(library (public_name foo))' > _source/dune
  $ echo 'let message = "original"' > _source/foo.ml
  $ make_lockpkg foo <<'EOF'
  > (version 1.0)
  > (source (fetch (url "file://_source")))
  > (build (run false))
  > EOF
  $ start_dune
  $ build main.exe
  Success
  $ _build/default/main.exe
  original

Edits, additions and deletions are visible in the same watch server.

  $ echo 'let message = "edited"' > _source/foo.ml
  $ with_timeout dune rpc flush-file-watcher --wait
  $ build main.exe
  Success
  $ _build/default/main.exe
  edited
  $ echo 'let message = "added"' > _source/extra.ml
  $ echo 'let message = Extra.message' > _source/foo.ml
  $ with_timeout dune rpc flush-file-watcher --wait
  $ build main.exe
  Success
  $ _build/default/main.exe
  added
  $ rm _source/extra.ml
  $ echo 'let message = "after deletion"' > _source/foo.ml
  $ with_timeout dune rpc flush-file-watcher --wait
  $ build main.exe
  Success
  $ _build/default/main.exe
  after deletion
  $ test ! -e _build/default/.pkg/foo/extra.ml
  $ stop_dune
  Success, waiting for filesystem changes...
  Success, waiting for filesystem changes...
  Success, waiting for filesystem changes...
  Success, waiting for filesystem changes...
