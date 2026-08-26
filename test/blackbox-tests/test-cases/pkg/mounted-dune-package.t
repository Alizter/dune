A locked Dune project is loaded into the current process. Its fetched source and
compiled artifacts have distinct owners, source precedence is preserved, and no
nested Dune command is run.

  $ export DUNE_CACHE_ROOT="$PWD/.cache"
  $ cat > dune-workspace <<'EOF'
  > (lang dune 3.20)
  > (pkg enabled)
  > EOF

  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends foo))
  > EOF

  $ cat > dune <<'EOF'
  > (library
  >  (name consumer)
  >  (modules consumer)
  >  (libraries foo))
  > (executable
  >  (name main)
  >  (modules main)
  >  (libraries consumer))
  > (rule
  >  (target local.txt)
  >  (mode promote)
  >  (action (write-file %{target} "workspace-promotion")))
  > EOF

  $ cat > consumer.ml <<'EOF'
  > let message =
  >   Printf.sprintf
  >     "%s/%s/%s/%s"
  >     Foo.message
  >     Generated.message
  >     Fallback.message
  >     Project_root.message
  > EOF
  $ cat > main.ml <<'EOF'
  > let () = print_endline Consumer.message
  > EOF

  $ mkdir -p foo/src
  $ cat > foo/dune-project <<'EOF'
  > (lang dune 3.23)
  > (name foo)
  > (version source-version)
  > (package (name foo))
  > EOF
  $ cat > foo/dune <<'EOF'
  > (rule
  >  (target generated.ml)
  >  (mode promote)
  >  (action (write-file %{target} "let message = \"generated\"")))
  > (rule
  >  (target fallback.ml)
  >  (mode fallback)
  >  (action (write-file %{target} "let message = \"generated-fallback\"")))
  > (rule
  >  (target project_root.ml)
  >  (deps (source_tree %{project_root}/src))
  >  (action
  >   (with-stdout-to %{target}
  >    (run sh -c "test \"$DUNE_PROJECT_ROOT\" = \"$PWD\" && echo 'let message = \"project-root\"'"))))
  > (rule
  >  (alias runtest)
  >  (action (run false)))
  > (library
  >  (name foo)
  >  (public_name foo)
  >  (wrapped false)
  >  (modules foo generated fallback project_root))
  > EOF
  $ cat > foo/src/foo.ml <<'EOF'
  > let message = "symlink-source"
  > EOF
  $ ln -s src/foo.ml foo/foo.ml
  $ cat > foo/generated.ml <<'EOF'
  > let message = "source-generated"
  > EOF
  $ cat > foo/fallback.ml <<'EOF'
  > let message = "source-fallback"
  > EOF
  $ echo snapshot-only > foo/unused.txt
  $ tar cf foo.tar foo
  $ rm -rf foo

  $ make_lockdir
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source
  >  (fetch
  >   (url file://$PWD/foo.tar)
  >   (checksum md5=$(md5sum foo.tar | cut -f1 -d' '))))
  > (build
  >  (setenv ROUTE mounted
  >   (chdir .
  >    (run dune build @install))))
  > EOF

Put a failing `dune` first in `PATH`. The top-level command uses the path saved
beforehand, so a nested package command would fail the build and leave a marker.

  $ real_dune="$(command -v dune)"
  $ fake_bin="$TMPDIR/mounted-dune-package-bin"
  $ rm -rf "$fake_bin"
  $ mkdir "$fake_bin"
  $ cat > "$fake_bin/dune" <<EOF
  > #!/bin/sh
  > echo nested-dune > "$PWD/nested-dune"
  > exit 99
  > EOF
  $ chmod +x "$fake_bin/dune"
  $ DUNE_CACHE=disabled PATH="$fake_bin:$PATH" "$real_dune" build ./main.exe --display quiet --trace-file trace.csexp
  $ ./_build/default/main.exe
  symlink-source/generated/source-fallback/project-root
  $ test ! -e nested-dune && echo no-nested-dune
  no-nested-dune
  $ test "$("$real_dune" trace cat --trace-file trace.csexp | jq_dune -c 'processes' | wc -l)" -gt 0 && echo build-processes-recorded
  build-processes-recorded
  $ "$real_dune" trace cat --trace-file trace.csexp | jq_dune -c 'processes | .args.prog | split("/") | .[-1]' | grep -Ec '^(dune|main\.exe)$' || true
  0
  $ "$real_dune" trace cat --trace-file trace.csexp | grep -c '_private/default/\.pkg/foo' || true
  0

Mounted source transport must not introduce an opaque directory target into the
workspace executable's recursive rule graph.

  $ "$real_dune" rules --recursive --format=json ./main.exe |
  > jq_dune '[.[] | .targets.directories[] | select(contains("/.pkg-source/"))] | length'
  0

Dune language files are read from the immutable source snapshot. Selected
compilation inputs are materialized as ordinary file targets in the package
output root alongside generated artifacts; no unpacked source tree is a build
directory target.

  $ artifact_root=$(echo _build/_default+lockfile/pkg/foo.1.0-*)
  $ test -f "$artifact_root/foo.ml" && echo materialized-source-file
  materialized-source-file
  $ "$real_dune" rules --format=json "$artifact_root/foo.ml" |
  > jq_dune -c '[.[] | .targets | {files: (.files | length), directories: (.directories | length)}]'
  [{"files":1,"directories":0}]
  $ test ! -e "$artifact_root/unused.txt" && test ! -e "$artifact_root/dune-project" && echo selective-materialization
  selective-materialization
  $ test -f "$artifact_root/foo.cmxa" && echo artifact-root
  artifact-root
  $ test ! -e _build/_private/default/.pkg-source && echo no-directory-source-target
  no-directory-source-target
  $ test ! -d _build/_private/default/.pkg && echo no-old-package-rules
  no-old-package-rules
  $ "$real_dune" build @pkg-install --display quiet
  $ test ! -d _build/_private/default/.pkg && echo pkg-install-bypasses-old-rules
  pkg-install-bypasses-old-rules
  $ grep '^version' "$artifact_root/META.foo"
  version = "1.0"
  $ "$real_dune" runtest --display quiet
  $ snapshot_root=$(find "$DUNE_CACHE_ROOT/pkg-sources/v1" -type d -name root)
  $ test "$(cat "$snapshot_root/generated.ml")" = 'let message = "source-generated"' && echo snapshot-unchanged
  snapshot-unchanged
  $ test "$(cat "$artifact_root/generated.ml")" = 'let message = "generated"' && echo promotion-contained
  promotion-contained
  $ "$real_dune" trace commands --trace-file trace.csexp | grep 'foo.ml' | grep -- '-w -a' >/dev/null && echo vendored-flags
  vendored-flags

The artifact root is an addressable build path, not a source alias. After a
clean, requesting a rule by that exact path re-fetches the source and produces
the target there. A subsequent workspace build compiles the package module
exactly once, under the same artifact root.

  $ mounted_target="$artifact_root/project_root.ml"
  $ "$real_dune" clean
  $ "$real_dune" build "$mounted_target" --display quiet
  $ grep 'project-root' "$mounted_target"
  let message = "project-root"
  $ "$real_dune" build ./main.exe --display quiet
  $ foo_cmx=$(find _build -type f -name foo.cmx)
  $ test "$foo_cmx" = "$artifact_root/.foo.objs/native/foo.cmx" && echo mounted-build-path-only
  mounted-build-path-only
  $ ./_build/default/main.exe
  symlink-source/generated/source-fallback/project-root
  $ "$real_dune" build local.txt --display quiet
  $ cat local.txt
  workspace-promotion

A Dune source with any unconditional non-Dune executable step stays on the
legacy package route. It remains usable alongside the mounted package.

  $ mkdir legacy
  $ cat > legacy/dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name legacy)
  >  (depends foo))
  > EOF
  $ cat > legacy/dune <<'EOF'
  > (library
  >  (name legacy)
  >  (public_name legacy)
  >  (libraries foo))
  > EOF
  $ cat > legacy/legacy.ml <<'EOF'
  > let message = "legacy-" ^ Foo.message
  > EOF
  $ tar cf legacy.tar legacy
  $ rm -rf legacy

  $ make_lockpkg legacy <<EOF
  > (version 1.0)
  > (depends foo)
  > (source
  >  (fetch
  >   (url file://$PWD/legacy.tar)
  >   (checksum md5=$(md5sum legacy.tar | cut -f1 -d' '))))
  > (build
  >  (progn
  >   (run dune build --release --promote-install-file=true . @install)
  >   (run echo legacy-route)))
  > EOF

  $ cat > dune-project <<'EOF'
  > (lang dune 3.20)
  > (package
  >  (name main)
  >  (depends legacy))
  > EOF
  $ cat > dune <<'EOF'
  > (executable
  >  (name main)
  >  (libraries foo legacy))
  > EOF
  $ cat > main.ml <<'EOF'
  > let () =
  >   Printf.printf
  >     "%s/%s/%s/%s\n"
  >     Foo.message
  >     Generated.message
  >     Fallback.message
  >     Legacy.message
  > EOF

  $ "$real_dune" clean
  $ "$real_dune" build @pkg-install --display quiet
  legacy-route
  $ foo_artifact_root=$(echo _build/_default+lockfile/pkg/foo.1.0-*)
  $ foo_layout=$(echo _build/install/default/.packages/*/lib/foo)
  $ test -f "$foo_artifact_root/META.foo" && test -f "$foo_artifact_root/foo.dune-package" && echo artifact-metadata
  artifact-metadata
  $ test -L "$foo_layout/META" && test -L "$foo_layout/dune-package" && echo layout-metadata
  layout-metadata
  $ test -L "$foo_layout/META" && test -L "$foo_layout/dune-package" && test "$(realpath "$foo_layout/META")" = "$(realpath "$foo_artifact_root/META.foo")" && test "$(realpath "$foo_layout/dune-package")" = "$(realpath "$foo_artifact_root/foo.dune-package")" && echo metadata-from-artifact-root
  metadata-from-artifact-root
  $ test ! -e _build/_private/default/.pkg-source && echo snapshot-not-build-output
  snapshot-not-build-output
  $ "$real_dune" build ./main.exe --display quiet
  $ ./_build/default/main.exe
  symlink-source/generated/source-fallback/legacy-symlink-source
  $ legacy_root=$(echo _build/_private/default/.pkg/legacy.1.0-*)
  $ test -d "$legacy_root/target" && echo legacy-package-rules
  legacy-package-rules
  $ test ! -d _build/_default+lockfile/pkg/legacy.1.0-* && echo legacy-not-mounted
  legacy-not-mounted
