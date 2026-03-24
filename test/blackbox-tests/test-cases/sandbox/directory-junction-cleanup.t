OCaml's Unix.lstat resolves directory junctions and returns S_DIR rather than
S_LNK. Without reparse point awareness in readdir, rm_rf would treat the
junction as a real directory, recurse into the target, and delete its contents.

We can observe the lstat behavior directly. On Unix this would print
"symbolic_link":

  $ trap 'cmd /c "rmdir /s /q _build" 2>/dev/null' EXIT

  $ mkdir real_dir
  $ cmd /c "mklink /j junc_to_dir real_dir" > /dev/null
  $ dune_cmd stat kind junc_to_dir
  directory
  $ cmd /c "rmdir junc_to_dir"
  $ rmdir real_dir

Dune's readdir detects reparse points via file attributes and reports them as
S_LNK, so rm_rf calls unlink rather than recursing. This test verifies that
sandbox cleanup removes the junction without following it into the target.

A dune rule with sandboxing creates a junction inside the sandbox pointing to
a precious directory outside the sandbox. After the build, the precious
directory's contents must survive cleanup.

  $ mkdir precious
  $ echo "must survive" > precious/important.txt
  $ test -f precious/important.txt && echo "file exists before build"
  file exists before build

  $ PRECIOUS_W=$(cygpath -w "$PWD/precious")

  $ cat > make_junction.sh <<EOF
  > #!/bin/bash
  > MSYS_NO_PATHCONV=1 cmd /c "mklink /j junc $PRECIOUS_W" > /dev/null
  > echo ok > output
  > EOF
  $ chmod +x make_junction.sh

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > EOF

  $ cat > dune <<'EOF'
  > (rule
  >  (target output)
  >  (deps make_junction.sh (sandbox always))
  >  (action (bash "./make_junction.sh")))
  > EOF

  $ dune build output 2>&1

  $ test -f precious/important.txt && echo "survived" || echo "DESTROYED by sandbox cleanup"
  survived
