When a junction targets a regular file, OCaml's Unix.lstat returns ENOENT.
Junctions are directory reparse points, so Windows cannot resolve one whose
target is a plain file. The readdir fallback in readdir.ml treats any lstat
failure as "file disappeared between readdir and lstat" and silently skips the
entry. The junction remains on disk but is invisible to dune. When rmdir is
called on the parent directory, it fails because the directory is not empty.

On Unix, lstat on a symlink always returns S_LNK regardless of target kind, so
this situation cannot arise.

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
  Error: failed to delete sandbox in
  _build/.sandbox/$DIGEST
  Reason:
  rmdir(_build/.sandbox/$DIGEST\default): Directory not empty
  -> required by _build/default/.cram.junction.t/cram.out
  -> required by alias junction
  -> required by alias runtest
  [1]
