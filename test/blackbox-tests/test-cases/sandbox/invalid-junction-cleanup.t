When a junction targets a regular file, OCaml's Unix.lstat returns ENOENT.
Junctions are directory reparse points, so Windows cannot resolve one whose
target is a plain file. Without reparse point awareness in readdir, the lstat
fallback would silently skip the entry, leaving the junction invisible to dune
and causing rmdir to fail with "Directory not empty".

Dune's readdir detects reparse points via file attributes and reports them as
S_LNK regardless of target kind, so cleanup can remove the junction even when
lstat would fail.

  $ trap 'cmd /c "rmdir /s /q _build" 2>/dev/null' EXIT

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > (cram enable)
  > EOF

  $ cat > junction.t <<'EOF'
  >   $ echo hi > file
  >   $ cmd /c "mklink /j junction file" > /dev/null
  > EOF

  $ dune runtest 2>&1 | censor
  
