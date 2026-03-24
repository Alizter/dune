When a junction's target is deleted after the junction is created, the junction
becomes dangling. OCaml's Unix.lstat returns ENOENT for dangling junctions
because Windows cannot resolve a reparse point whose target no longer exists.
Without reparse point awareness in readdir, the entry would be silently skipped
and cleanup would fail with "Directory not empty".

Dune's readdir detects reparse points via file attributes and reports them as
S_LNK, so cleanup can remove dangling junctions. On Unix, lstat on a dangling
symlink also returns S_LNK, so this case works naturally.

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
  
