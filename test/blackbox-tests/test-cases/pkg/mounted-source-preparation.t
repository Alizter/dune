Each preparation scenario has its own project so that precedence, patch
ordering, condition evaluation and executable permissions are observed
independently.

  $ make_consumer() {
  >   make_lockdir
  >   make_named_package_project main 3.25 foo
  >   echo '(executable (name main) (libraries foo))' > dune
  >   echo 'let () = print_endline Foo.message' > main.ml
  >   mkdir _source
  > }
  $ patch_message() {
  >   make_lockpkg_file foo update.patch <<EOF
  > --- a/$1
  > +++ b/$1
  > @@ -1 +1 @@
  > -let message = "$2"
  > +let message = "$3"
  > EOF
  > }

Extra sources override lock files, which override the fetched snapshot.
Dune configuration supplied only by extra sources is discovered natively.

  $ mkdir _precedence
  $ cd _precedence
  $ make_consumer
  $ echo 'let message = Version.value' > _source/foo.ml
  $ echo 'let value = "source"' > _source/version.ml
  $ mkdir _overlay
  $ (cd _overlay && make_dune_project_with_package 3.25 foo)
  $ echo '(library (public_name foo))' > _overlay/dune
  $ echo 'let value = "extra"' > _overlay/version.ml
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (extra_sources
  >  (version.ml (copy $PWD/_overlay/version.ml))
  >  (dune-project (copy $PWD/_overlay/dune-project))
  >  (dune (copy $PWD/_overlay/dune)))
  > (build (run false))
  > EOF
  $ make_lockpkg_file foo version.ml <<'EOF'
  > let value = "lock file"
  > EOF
  $ dune build main.exe
  $ _build/default/main.exe
  extra
  $ cat _source/foo.ml _source/version.ml
  let message = Version.value
  let value = "source"
  $ test ! -e _source/dune-project
  $ test ! -e _build/default/.pkg/foo/dune-project

Changing an extra source invalidates the prepared view and native build.

  $ echo 'let value = "changed"' > _overlay/version.ml
  $ dune build main.exe
  $ _build/default/main.exe
  changed

Without the extra source at that path, the lock file wins over the snapshot.

  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (extra_sources
  >  (dune-project (copy $PWD/_overlay/dune-project))
  >  (dune (copy $PWD/_overlay/dune)))
  > (build (run false))
  > EOF
  $ dune build main.exe
  $ _build/default/main.exe
  lock file
  $ cd ..

Patches apply after the overlays, without mutating the source or extra source.

  $ mkdir _patch
  $ cd _patch
  $ make_consumer
  $ (cd _source && make_dune_project_with_package 3.25 foo)
  $ echo '(library (public_name foo))' > _source/dune
  $ echo 'let message = "original"' > _source/foo.ml
  $ mkdir _overlay
  $ echo 'let message = "extra"' > _overlay/foo.ml
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (extra_sources (foo.ml (copy $PWD/_overlay/foo.ml)))
  > (build (progn (patch update.patch) (run false)))
  > EOF
  $ make_lockpkg_file foo foo.ml <<'EOF'
  > let message = "lock file"
  > EOF

A stale hunk fails on the first demand, at the patch action in the lock file.

  $ patch_message foo.ml 'something else' patched
  $ dune build main.exe
  File "dune.lock/foo.pkg", line 4, characters 21-33:
  4 | (build (progn (patch update.patch) (run false)))
                           ^^^^^^^^^^^^
  Error: Patch could not be applied to "foo.ml": hunk does not match file
  contents
  [1]

The source and extra source are unchanged after failure.

  $ cat _source/foo.ml _overlay/foo.ml
  let message = "original"
  let message = "extra"

A patch for a missing file also fails before the consumer can build.

  $ patch_message absent.ml 'extra' patched
  $ dune build main.exe
  File "dune.lock/foo.pkg", line 4, characters 21-33:
  4 | (build (progn (patch update.patch) (run false)))
                           ^^^^^^^^^^^^
  Error: Cannot edit file "absent.ml": file does not exist
  [1]

Fixing the patch recovers the build using the overlaid input.

  $ patch_message foo.ml 'extra' patched
  $ dune build main.exe
  $ _build/default/main.exe
  patched
  $ cat _source/foo.ml _overlay/foo.ml
  let message = "original"
  let message = "extra"
  $ test ! -d _build/_fetch
  $ cd ..

Patch conditions use the package and dependency versions as metadata. The
dependency's recipe must not run, and a false condition must not read its
missing patch.

  $ mkdir _conditional
  $ cd _conditional
  $ make_consumer
  $ (cd _source && make_dune_project_with_package 3.25 foo)
  $ echo '(library (public_name foo))' > _source/dune
  $ echo 'let message = "original"' > _source/foo.ml
  $ make_lockpkg metadata <<'EOF'
  > (version 2.0)
  > (build (run false))
  > EOF
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (depends metadata)
  > (source (copy $PWD/_source))
  > (build
  >  (progn
  >   (when (= %{pkg:metadata:version} 2.0)
  >    (when (= %{pkg-self:version} 1.0) (patch update.patch)))
  >   (when (= %{pkg-self:version} 9.0) (patch missing.patch))
  >   (run false)))
  > EOF
  $ patch_message foo.ml 'original' conditional
  $ dune build main.exe
  $ dune trace cat | jq -rs '
  >   [.[] | select(.cat == "log") | .args
  >    | select(.message == "Package source candidates"
  >             or .message == "Package digest index"
  >             or (.message == "Prepare package sources" and .package == "foo"))]
  >   | group_by(.message) | .[] | "\(.[0].message) evaluated once: \(length == 1)"'
  Package digest index evaluated once: true
  Package source candidates evaluated once: true
  Prepare package sources evaluated once: true
  $ _build/default/main.exe
  conditional
  $ cd ..

Patching an executable source preserves its executable bit. A native rule
executes the patched script, while the original input stays unchanged.

  $ mkdir _executable
  $ cd _executable
  $ make_consumer
  $ (cd _source && make_dune_project_with_package 3.25 foo)
  $ echo 'let message = Script.value' > _source/foo.ml
  $ cat > _source/dune <<'EOF'
  > (library (public_name foo))
  > (rule
  >  (target script.ml)
  >  (deps tool)
  >  (action (with-stdout-to %{target} (run ./tool))))
  > EOF
  $ cat > _source/tool <<'EOF'
  > #!/bin/sh
  > echo 'let value = "original script"'
  > EOF
  $ chmod +x _source/tool
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (build (progn (patch update.patch) (run false)))
  > EOF
  $ make_lockpkg_file foo update.patch <<'EOF'
  > --- a/tool
  > +++ b/tool
  > @@ -1,2 +1,2 @@
  >  #!/bin/sh
  > -echo 'let value = "original script"'
  > +echo 'let value = "patched script"'
  > EOF
  $ dune build main.exe
  $ _build/default/main.exe
  patched script
  $ test -x _build/default/.pkg/foo/tool
  $ _source/tool
  let value = "original script"
  $ cd ..

The remaining scenarios use a fresh project rather than inheriting one of the
preparation fixtures.

  $ make_dune_project 3.25
  $ make_lockdir

OCaml configuration scripts read a physical prepared view, not the backing
snapshot. Their ordinary rules run natively without invoking the opaque recipe.

  $ mkdir _script
  $ printf '(lang dune 3.25)\n(package (name scripted))\n' > _script/dune-project
  $ echo original > _script/value
  $ cat > _script/dune <<'EOF'
  > (* -*- tuareg -*- *)
  > let () =
  >   let input = open_in "value" in
  >   let value = input_line input in
  >   close_in input;
  >   Jbuild_plugin.V1.send
  >     ("(rule (target answer) (action (write-file %{target} "
  >      ^ Printf.sprintf "%S" value ^ ")))"
  >      ^ "(install (section share) (files answer))")
  > EOF
  $ make_lockpkg scripted <<EOF
  > (version 1.0)
  > (source (copy $PWD/_script))
  > (build
  >  (progn
  >   (system "echo opaque-script-build")
  >   (system "cp value answer")
  >   (write-file scripted.install "share: [ \"answer\" ]")))
  > EOF
  $ make_lockpkg_file scripted value <<'EOF'
  > overlay
  > EOF
  $ cat >> dune <<'EOF'
  > (rule
  >  (target scripted-result)
  >  (action (with-stdout-to %{target} (cat %{pkg:scripted:share:answer}))))
  > EOF
  $ dune build scripted-result
  $ cat _build/default/scripted-result
  overlay
  $ test ! -e _build/default/.pkg/scripted/_install
  $ cat _script/value
  original

Changes to the overlay invalidate script evaluation and its generated rules.

  $ make_lockpkg_file scripted value <<'EOF'
  > changed overlay
  > EOF
  $ dune build scripted-result
  $ cat _build/default/scripted-result
  changed overlay

Nested scripts also see parent paths and inputs excluded from rule generation.
The snapshot includes patched executable permissions, deletions, and an
overlaid script.

  $ mkdir nested-script
  $ cd nested-script
  $ make_dune_project 3.25
  $ mkdir -p _source/tools/version _source/ignored
  $ (cd _source && make_dune_project_with_package 3.25 nested)
  $ cat > _source/dune <<'EOF'
  > (dirs :standard \ ignored)
  > (install (section share) (files (tools/version/answer as answer)))
  > EOF
  $ cat > _source/tools/version/dune <<'EOF'
  > (* -*- tuareg -*- *)
  > let () = failwith "unprepared script"
  > EOF
  $ echo excluded > _source/ignored/value
  $ echo remove-me > _source/removed
  $ cat > _source/ignored/tool <<'EOF'
  > #!/bin/sh
  > echo original
  > EOF
  $ chmod +x _source/ignored/tool
  $ cat > _script-overlay <<'EOF'
  > (* -*- tuareg -*- *)
  > let () =
  >   let input = open_in "../../ignored/value" in
  >   let value = input_line input in
  >   close_in input;
  >   let tool =
  >     Jbuild_plugin.V1.run_and_read_lines "../../ignored/tool" |> List.hd
  >   in
  >   let answer =
  >     Printf.sprintf "%s/%s/%b" value tool (Sys.file_exists "../../removed")
  >   in
  >   Jbuild_plugin.V1.send
  >     ("(rule (target answer) (action (write-file %{target} "
  >      ^ Printf.sprintf "%S" answer ^ ")))")
  > EOF
  $ make_lockdir
  $ make_lockpkg nested <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (extra_sources (tools/version/dune (copy $PWD/_script-overlay)))
  > (build
  >  (progn
  >   (patch prepare.patch)
  >   (run false)))
  > EOF
  $ make_lockpkg_file nested prepare.patch <<'EOF'
  > --- a/ignored/tool
  > +++ b/ignored/tool
  > @@ -1,2 +1,2 @@
  >  #!/bin/sh
  > -echo original
  > +echo patched
  > --- a/removed
  > +++ /dev/null
  > @@ -1 +0,0 @@
  > -remove-me
  > EOF
  $ cat > dune <<'EOF'
  > (rule
  >  (target result)
  >  (action (copy %{pkg:nested:share:answer} %{target})))
  > (rule (target standalone) (action (write-file %{target} ok)))
  > EOF
  $ dune build result
  $ cat _build/default/result
  excluded/patched/false
  $ cat _source/ignored/value _source/removed
  excluded
  remove-me
  $ _source/ignored/tool
  original

Changes to the original inputs invalidate evaluation too. Removing the patch
must restore the deleted file and executable from the original source view.

  $ echo updated > _source/ignored/value
  $ dune build result
  $ cat _build/default/result
  updated/patched/false
  $ make_lockpkg nested <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (extra_sources (tools/version/dune (copy $PWD/_script-overlay)))
  > (build (run false))
  > EOF
  $ dune build result
  $ cat _build/default/result
  updated/original/true
  $ rm _source/removed
  $ dune build result
  $ cat _build/default/result
  updated/original/false

Errors in generated stanzas are saved for demand, not used to select the opaque
recipe. Repairing the script makes the native rules available again.

  $ cp _script-overlay _valid-script
  $ cat > _script-overlay <<'EOF'
  > (* -*- tuareg -*- *)
  > let () = Jbuild_plugin.V1.send "(broken-stanza)"
  > EOF
  $ dune build standalone
  $ dune build result
  File "_build/.dune/default/.pkg/nested/tools/version/dune", line 1, characters 1-14:
  1 | (broken-stanza)
       ^^^^^^^^^^^^^
  Error: Unknown constructor broken-stanza
  [1]
  $ cp _valid-script _script-overlay
  $ dune build result
  $ cat _build/default/result
  updated/original/false

Doubling a large prepared snapshot should not quadruple allocation. These are
excluded inputs read through the script snapshot, not individual rule targets.
We compare allocated words, not wall-clock timings, with room for linear work.

  $ mkdir _source/ignored/bulk
  $ i=0; while [ "$i" -lt 4096 ]; do
  >   echo payload > _source/ignored/bulk/file$i
  >   i=$((i + 1))
  > done
  $ dune build result
  $ dune trace cat | jq '
  >   select(.cat == "config" and .name == "exit") | .args.gc
  >   | .minor_words + .major_words - .promoted_words' > small-alloc
  $ while [ "$i" -lt 8192 ]; do
  >   echo payload > _source/ignored/bulk/file$i
  >   i=$((i + 1))
  > done
  $ dune build result
  $ dune trace cat | jq --slurpfile small small-alloc '
  >   select(.cat == "config" and .name == "exit") | .args.gc
  >   | (.minor_words + .major_words - .promoted_words) < 3 * $small[0]'
  true
  $ cat _build/default/result
  updated/original/false
