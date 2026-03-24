WSL symlinks (IO_REPARSE_TAG_LX_SYMLINK, 0xa000001d) are created by Cygwin's
default ln -s and by MSYS2's ln -s when MSYS=winsymlinks:native is set.
OCaml's Unix.lstat returns ENOENT for WSL symlinks regardless of target kind,
because Windows does not recognize the reparse tag. Without reparse point
awareness in readdir, these entries would be silently skipped and cleanup would
fail with "Directory not empty".

Dune's readdir detects reparse points via file attributes and reports them as
S_LNK, bypassing lstat entirely. This allows cleanup to remove WSL symlinks
even though lstat cannot resolve them.

This is the most practically relevant case because users writing ln -s in
build scripts or cram tests may not realize MSYS2/Cygwin is creating WSL
reparse points rather than POSIX symlinks.

  $ trap 'cmd /c "rmdir /s /q _build" 2>/dev/null' EXIT

Verify that MSYS=winsymlinks:native creates reparse points that are invisible
to OCaml's lstat, for both file and directory targets:

  $ echo hello > target_file
  $ mkdir target_dir
  $ MSYS=winsymlinks:native ln -s target_file wsl_link_to_file
  $ MSYS=winsymlinks:native ln -s target_dir wsl_link_to_dir

  $ dune_cmd stat kind wsl_link_to_file 2>&1 | dune_cmd subst '"[A-Z]:\\\\[^"]*"' '$PATH'
  Fatal error: exception Unix.Unix_error(Unix.ENOENT, "lstat", $PATH)
  [2]

  $ dune_cmd stat kind wsl_link_to_dir 2>&1 | dune_cmd subst '"[A-Z]:\\\\[^"]*"' '$PATH'
  Fatal error: exception Unix.Unix_error(Unix.ENOENT, "lstat", $PATH)
  [2]

  $ rm wsl_link_to_file wsl_link_to_dir target_file
  $ rmdir target_dir

Verify that sandbox cleanup succeeds despite lstat's inability to resolve them:

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > (cram enable)
  > EOF

  $ cat > wsl-link.t <<'EOF'
  >   $ echo hi > file
  >   $ MSYS=winsymlinks:native ln -s file link
  > EOF

  $ dune runtest 2>&1 | censor
  
