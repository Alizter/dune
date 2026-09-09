Reproduce #10839.

Dune file in OCaml syntax and a files directory should work

  $ make_lockdir

  $ make_lockpkg base-bytes <<EOF
  > (version base)
  > 
  > (depends ocamlfind)
  > EOF

  $ make_lockpkg ocamlfind <<EOF
  > (version 1)
  > EOF

  $ make_dune_project 3.16

  $ cat >dune <<EOF
  > (* -*- tuareg -*- *)
  > let () = Jbuild_plugin.V1.send ""
  > EOF

  $ dune build

  $ mkdir ${default_lock_dir}/ocamlfind.files
  $ touch ${default_lock_dir}/ocamlfind.files/foo.patch

  $ dune build

A native dependency's OCaml-syntax Dune file must be evaluated with the locked
compiler. Loading that compiler's opaque installation must not require the
native Dune files to have been evaluated already.

  $ mkdir compiler-for-script
  $ cd compiler-for-script
  $ cat >dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name workspace) (allow_empty) (depends scripted))
  > EOF
  $ echo '(dirs :standard \ scripted-source)' >dune
  $ mkdir scripted-source
  $ cat >scripted-source/dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name scripted))
  > EOF
  $ cat >scripted-source/dune <<'EOF'
  > (* -*- tuareg -*- *)
  > let () = Jbuild_plugin.V1.send {|
  > (rule (target result) (action (write-file %{target} evaluated)))
  > (install (package scripted) (section share) (files result))
  > |}
  > EOF
  $ make_lockdir
  $ echo '(ocaml ocaml-base-compiler)' >>dune.lock/lock.dune
  $ make_lockpkg ocaml-base-compiler <<EOF
  > (version 1.0)
  > (install (run cp $(command -v ocamlc) %{bin}/ocamlc))
  > EOF
  $ make_lockpkg scripted <<EOF
  > (version 1.0)
  > (depends ocaml-base-compiler)
  > (source (copy $PWD/scripted-source))
  > EOF
  $ dune build @pkg-install
  $ find _build -path '*/pkg/scripted/result' -exec cat '{}' ';'
  evaluated

The workspace Dune file itself may also need the locked compiler. Its rules
must not be needed to materialize that compiler for the first time.

  $ mkdir ../workspace-script
  $ cd ../workspace-script
  $ make_dune_project 3.24
  $ cat >dune <<'EOF'
  > (* -*- tuareg -*- *)
  > let () = Jbuild_plugin.V1.send {|
  > (rule (target result) (action (write-file %{target} workspace-evaluated)))
  > |}
  > EOF
  $ make_lockdir
  $ echo '(ocaml ocaml-base-compiler)' >>dune.lock/lock.dune
  $ make_lockpkg ocaml-base-compiler <<EOF
  > (version 1.0)
  > (install (run cp $(command -v ocamlc) %{bin}/ocamlc))
  > EOF
  $ dune build result
  $ cat _build/default/result
  workspace-evaluated
