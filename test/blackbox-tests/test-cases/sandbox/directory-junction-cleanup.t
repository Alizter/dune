When a junction targets a directory, OCaml's Unix.lstat can resolve it and
returns S_DIR — the target kind, not S_LNK. On Unix, lstat on a symlink always
returns S_LNK regardless of target kind.

We can observe this directly. On Unix this would print "symbolic_link":

  $ trap 'cmd /c "rmdir /s /q _build" 2>/dev/null' EXIT

  $ mkdir real_dir
  $ cmd /c "mklink /j junc_to_dir real_dir" > /dev/null
  $ dune_cmd stat kind junc_to_dir
  directory
  $ cmd /c "rmdir junc_to_dir"
  $ rmdir real_dir

Because lstat returns S_DIR, dune's rm_rf treats the junction as a real
directory: it recurses into the target and deletes its contents. On Unix,
lstat returns S_LNK for symlinks, so rm_rf calls unlink instead — removing
the link without following it.

To demonstrate this deterministically, we use a dune rule with sandboxing.
The rule creates a junction inside the sandbox pointing to a precious
directory outside the sandbox. When the sandbox is cleaned up, rm_rf follows
the junction and destroys the external directory's contents.

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
  DESTROYED by sandbox cleanup
