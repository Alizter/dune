We test how opam files with substs fields together with patches fields are translated into
the dune.lock file. Opam allows substitution to happen before the patches phase, so we
must do the same.

  $ mkrepo

Make a package with a substs and patches field field 
  $ mkpkg with-substs-and-patches <<EOF
  > substs: ["foo.patch"]
  > patches: ["foo.patch"]
  > build: [ "sh" "-c" "[ -e foo.ml ] && cat foo.ml" ]
  > EOF

  $ opam_repo=$mock_packages/with-substs-and-patches/with-substs-and-patches.0.0.1

  $ solve with-substs-and-patches
  Solution for dune.lock:
  - with-substs-and-patches.0.0.1
  $ append_to_lockpkg with-substs-and-patches.0.0.1 <<EOF
  > (source (copy $PWD/source))
  > EOF

The lockfile should contain the substitute and patch actions.

  $ cat ${default_lock_dir}/with-substs-and-patches.0.0.1.pkg 
  (version 0.0.1)
  
  (build
   (all_platforms
    ((action
      (progn
       (substitute foo.patch.in foo.patch)
       (patch foo.patch)
       (run sh -c "[ -e foo.ml ] && cat foo.ml"))))))
  (source (copy $TESTCASE_ROOT/source))

  $ mkdir source

  $ write_wrong_to_right_patch source/foo.patch.in

  $ cat > source/foo.ml <<EOF
  > This is wrong
  > EOF

The file foo.ml should have been built:

  $ build_pkg with-substs-and-patches
  This is right

For a native package, substitutions and patches affect the logical source view
before Dune-file classification. The substituted `dune` file selects the native
route, the patch changes a compiled module, and the remaining opaque recipe is
not executed.

  $ mkdir native-source
  $ cat > native-source/dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name native-transform))
  > EOF
  $ cat > native-source/dune.in <<'EOF'
  > (* -*- tuareg -*- *)
  > let () =
  >   Jbuild_plugin.V1.send
  >     {|
  > (rule
  >  (target generated.ml)
  >  (deps generated.sh)
  >  (action (with-stdout-to %{target} (run ./generated.sh))))
  > (library (name native_transform) (public_name native-transform))
  > |}
  > EOF
  $ cat > native-source/native_transform.ml <<'EOF'
  > let message = String.concat ":" [ "primary"; Created.suffix; Generated.suffix ]
  > EOF
  $ cat > native-source/old.ml <<'EOF'
  > let suffix = "renamed"
  > EOF
  $ cat > native-source/script-template <<'EOF'
  > #!/bin/sh
  > printf '%s\n' 'let suffix = "exec:%{version}%:%{metadata:version}%:%{switch}%"'
  > EOF
  $ chmod +x native-source/script-template
  $ ln -s script-template native-source/generated.sh.in
  $ cat > native-source/generated.sh <<'EOF'
  > #!/bin/sh
  > exit 1
  > EOF
  $ chmod +x native-source/generated.sh
  $ tar czf native-source.tar.gz native-source
  $ cat > source/native-extra.ml <<'EOF'
  > let message = String.concat ":" [ "extra"; Created.suffix; Generated.suffix ]
  > EOF

  $ source_lock_dir=native.lock
  $ make_lockdir
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.24)
  > (context (default (lock_dir native.lock)))
  > EOF
  $ make_lockpkg metadata <<'EOF'
  > (version 7)
  > EOF
  $ make_lockpkg native-transform <<EOF
  > (version 1)
  > (depends metadata)
  > (source (fetch (url file://$PWD/native-source.tar.gz)))
  > (extra_sources (native_transform.ml (copy $PWD/source/native-extra.ml)))
  > (build
  >  (progn
  >   (substitute generated.sh.in generated.sh)
  >   (substitute dune.in dune)
  >   (patch fix.patch)
  >   (when (= %{pkg-self:version} 2) (patch absent.patch))
  >   (when
  >    (and
  >     (= %{switch} dune)
  >     (= %{pkg-self:version} 1)
  >     %{pkg:metadata:installed})
  >    (patch topology.patch))
  >   (run false)))
  > EOF
  $ make_lockpkg_file native-transform native_transform.ml <<'EOF'
  > let message = String.concat ":" [ "lock"; Created.suffix; Generated.suffix ]
  > EOF
  $ make_lockpkg_file native-transform fix.patch <<'EOF'
  > diff --git a/native_transform.ml b/native_transform.ml
  > --- a/native_transform.ml
  > +++ b/native_transform.ml
  > @@ -1 +1 @@
  > -let message = String.concat ":" [ "extra"; Created.suffix; Generated.suffix ]
  > +let message = String.concat ":" [ "right"; Created.suffix; Generated.suffix ]
  > EOF
  $ make_lockpkg_file native-transform topology.patch <<'EOF'
  > diff --git a/old.ml b/created.ml
  > similarity index 100%
  > rename from old.ml
  > rename to created.ml
  > EOF

  $ cat > dune-project <<'EOF'
  > (lang dune 3.24)
  > (package (name app) (allow_empty) (depends native-transform))
  > EOF
  $ cat > dune <<'EOF'
  > (dirs :standard \ native-source \ source)
  > (executable (name main) (libraries native-transform))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Native_transform.message
  > EOF

  $ dune exec ./main.exe
  right:renamed:exec:1:7:dune
  $ dune build _build/_default+lockfile/pkg/native-transform/dune
  $ head -3 _build/_default+lockfile/pkg/native-transform/dune
  (* -*- tuareg -*- *)
  let () =
    Jbuild_plugin.V1.send
  $ cat _build/_default+lockfile/pkg/native-transform/native_transform.ml
  let message = String.concat ":" [ "right"; Created.suffix; Generated.suffix ]
  $ cat _build/_default+lockfile/pkg/native-transform/created.ml
  let suffix = "renamed"
  $ test ! -e _build/_default+lockfile/pkg/native-transform/old.ml
  $ test -x _build/_default+lockfile/pkg/native-transform/generated.sh
  $ cat _build/_default+lockfile/pkg/native-transform/generated.ml
  let suffix = "exec:1:7:dune"
  $ test ! -e _build/_default+lockfile/pkg/native-transform/.opam
  $ raw_ml=$(find _build/_fetch -path '*/dir/native_transform.ml')
  $ test -n "$raw_ml" && cat "$raw_ml"
  let message = String.concat ":" [ "primary"; Created.suffix; Generated.suffix ]
  $ test -e "$(dirname "$raw_ml")/old.ml"
  $ test ! -e "$(dirname "$raw_ml")/created.ml"
  $ tail -1 "$(dirname "$raw_ml")/generated.sh"
  exit 1
  $ test ! -e "$(dirname "$raw_ml")/dune"

Changing a transformation invalidates rules at the same package-name path
without modifying or reacquiring the primary source:

  $ sed -i 's/\[ "right";/[ "updated";/' native.lock/native-transform.files/fix.patch
  $ dune exec ./main.exe
  updated:renamed:exec:1:7:dune
  $ head -1 _build/_default+lockfile/pkg/native-transform/native_transform.ml
  let message = String.concat ":" [ "updated"; Created.suffix; Generated.suffix ]
  $ cat "$raw_ml"
  let message = String.concat ":" [ "primary"; Created.suffix; Generated.suffix ]
