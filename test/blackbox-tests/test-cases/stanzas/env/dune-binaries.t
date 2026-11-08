Adds custom binaries through the `env` stanza.

  $ make_dune_project 3.21

  $ cat >dune <<EOF
  > (env
  >  (_
  >   (binaries (test.sh as foobar))
  >   (flags :standard)))
  > 
  > (rule
  >  (target message.txt)
  >  (action (with-stdout-to %{target} (run foobar))))
  > EOF

  $ cat >test.sh <<EOF
  > #!/bin/sh
  > 
  > echo "This is only a test."
  > EOF

  $ chmod +x test.sh

  $ dune build ./message.txt

A sandboxed rule cannot use an undeclared binary, even after another rule has
built it. Its generated PATH entry refers only to the sandbox.

  $ cat >> dune <<'EOF'
  > (rule
  >  (target sandboxed.txt)
  >  (deps (sandbox always))
  >  (action
  >   (with-stdout-to %{target}
  >    (system
  >     "\| set -e
  >     "\| pwd
  >     "\| test ! -e .bin/foobar
  >     "\| if command -v foobar; then
  >     "\|   foobar
  >     "\| else
  >     "\|   echo unavailable
  >     "\| fi
  >   ))))
  > EOF
  $ dune build sandboxed.txt
  $ cat _build/default/sandboxed.txt | censor
  $PWD/_build/.sandbox/$DIGEST/default
  unavailable

A fresh build directory cannot find the undeclared binary.

  $ dune build sandboxed.txt --build-dir _build-cold
  $ cat _build-cold/default/sandboxed.txt | censor
  $PWD/_build-cold/.sandbox/$DIGEST/default
  unavailable

An action-local PATH override must not restore the leak. Declaring the dependency
makes the binding available inside the sandbox. An explicitly unsandboxed action
keeps using the real build directory.

  $ cat >> dune <<'EOF'
  > (rule
  >  (target setenv.txt)
  >  (deps (sandbox always))
  >  (action
  >   (with-stdout-to %{target}
  >    (setenv PATH %{env:PATH=}
  >     (system
  >      "\| set -e
  >      "\| test ! -e .bin/foobar
  >      "\| if command -v foobar; then
  >      "\|   foobar
  >      "\| else
  >      "\|   echo unavailable
  >      "\| fi
  >    )))))
  > (rule
  >  (target declared.txt)
  >  (deps (sandbox always) %{bin:foobar})
  >  (action
  >   (with-stdout-to %{target}
  >    (system "test -e .bin/foobar && command -v foobar && foobar"))))
  > (rule
  >  (target unsandboxed.txt)
  >  (deps (sandbox none))
  >  (action
  >   (with-stdout-to %{target}
  >    (system "command -v foobar && foobar"))))
  > (rule
  >  (target path-semantics.txt)
  >  (deps (sandbox always))
  >  (action
  >   (with-stdout-to %{target}
  >    (setenv PATH ":relative:/outside::%{env:PATH=}::"
  >     (system
  >      "\| case "$PATH" in
  >      "\|   :relative:/outside::*::) echo preserved ;;
  >      "\|   *) exit 1 ;;
  >      "\| esac
  >    )))))
  > EOF
  $ dune build setenv.txt declared.txt unsandboxed.txt path-semantics.txt
  $ cat _build/default/setenv.txt | censor
  unavailable
  $ cat _build/default/declared.txt | censor
  $PWD/_build/.sandbox/$DIGEST/default/.bin/foobar
  This is only a test.
  $ cat _build/default/unsandboxed.txt | censor
  $PWD/_build/default/.bin/foobar
  This is only a test.
  $ cat _build/default/path-semantics.txt
  preserved

External tools remain external even when installed underneath the build root.
Declaring such a tool must work both through PATH and through a direct run.

  $ mkdir -p _build/_bootinstall/bin
  $ cat > _build/_bootinstall/bin/external-tool <<'EOF'
  > #!/bin/sh
  > echo external tool
  > EOF
  $ chmod +x _build/_bootinstall/bin/external-tool
  $ cat >> dune <<'EOF'
  > (rule
  >  (target external-path.txt)
  >  (deps (sandbox always) %{bin:external-tool})
  >  (action
  >   (with-stdout-to %{target}
  >    (system
  >     "\| if command -v external-tool >/dev/null; then
  >     "\|   external-tool
  >     "\| else
  >     "\|   echo unavailable
  >     "\| fi
  >   ))))
  > (rule
  >  (target external-run.txt)
  >  (deps (sandbox always))
  >  (action (with-stdout-to %{target} (run external-tool))))
  > (rule
  >  (target literal-path.txt)
  >  (deps (sandbox always))
  >  (action
  >   (with-stdout-to %{target}
  >    (setenv PATH %{env:SPELLING_PATH=}
  >     (system
  >      "\| test "$PATH" = "$SPELLING_PATH" && echo preserved
  >    )))))
  > (rule
  >  (target inherited-path.txt)
  >  (deps (sandbox always))
  >  (action (write-file %{target} inherited)))
  > EOF
  $ PATH="$PWD/_build/_bootinstall/bin:$PATH" \
  >   dune build external-path.txt external-run.txt
  $ cat _build/default/external-path.txt _build/default/external-run.txt
  external tool
  external tool

Valid literal PATH spellings must not be interpreted as local build paths.

  $ for path in "" "$PWD/_build//default/.bin" "$PWD/_build/../tools/bin"; do
  >   if SPELLING_PATH="$path" dune build literal-path.txt > spelling.log 2>&1
  >   then cat _build/default/literal-path.txt
  >   else echo rejected
  >   fi
  > done
  preserved
  preserved
  preserved

An inherited PATH with an unusual spelling must not break an unrelated action.

  $ if PATH="$PWD/_build//default/.bin:$PATH" \
  >   dune build inherited-path.txt > inherited.log 2>&1
  > then cat _build/default/inherited-path.txt
  > else echo rejected
  > fi
  inherited

Job-slot commands should receive the same sandbox preparation as the action.
The command returns zero when its working directory or PATH is unprepared,
which makes Dune reject its job-slot count.

  $ make_dune_project 3.26
  $ mkdir slots-cwd
  $ cat > slots-cwd/dune <<'EOF'
  > (rule
  >  (target marker)
  >  (action (write-file %{target} built)))
  > EOF
  $ dune build slots-cwd/marker
  $ cat >> dune <<'EOF'
  > (rule
  >  (target job-slots.txt)
  >  (deps (sandbox always) %{bin:foobar} (env_var REAL_BUILD_DIR))
  >  (job_slots
  >   (chdir slots-cwd
  >    (setenv PATH %{env:PATH=}
  >     (system
  >      "\| if test "$PWD" = "$REAL_BUILD_DIR"; then
  >      "\|   echo 0; exit
  >      "\| fi
  >      "\| binary="${PWD%/slots-cwd}/.bin/foobar"
  >      "\| if test "$(command -v foobar)" = "$binary"; then
  >      "\|   echo 1
  >      "\| else
  >      "\|   echo 0
  >      "\| fi
  >   ))))
  >  (action (write-file %{target} prepared)))
  > EOF
  $ if REAL_BUILD_DIR="$PWD/_build/default/slots-cwd" \
  >   dune build job-slots.txt > job-slots.log 2>&1
  > then cat _build/default/job-slots.txt
  > else
  >   grep -q '"0"' job-slots.log || { cat job-slots.log; exit 1; }
  >   echo unprepared
  > fi
  prepared
