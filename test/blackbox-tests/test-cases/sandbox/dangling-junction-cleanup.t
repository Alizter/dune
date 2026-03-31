When a junction's target is deleted after the junction is created, the junction
becomes dangling. OCaml's Unix.lstat returns ENOENT for dangling junctions
regardless of whether the original target was a file or directory, because
Windows cannot resolve a reparse point whose target no longer exists. This
makes the junction invisible to dune's sandbox cleanup, causing "Directory not
empty".

On Unix, lstat on a dangling symlink still returns S_LNK, so unlink can remove
it. Dangling links do not cause cleanup failures on Unix.

  $ trap 'cmd /c "rmdir /s /q _build" 2>/dev/null' EXIT

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > (cram enable)
  > EOF

  $ cat > dangling.t <<'EOF'
  >   $ mkdir target
  >   $ cmd /c "mklink /j junction target" > /dev/null
  >   $ rmdir target
  > EOF

  $ dune runtest 2>&1 | censor
  Error: failed to delete sandbox in
  _build/.sandbox/$DIGEST
  Reason:
  rmdir(_build/.sandbox/$DIGEST\default): Directory not empty
  -> required by _build/default/.cram.dangling.t/cram.out
  -> required by alias dangling
  -> required by alias runtest
  [1]
