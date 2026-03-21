When a tool is invoked with a long path and LongPathsEnabled is not set,
dune should emit a registry warning with the reg add command.
With DUNE_LONG_PATH_ENABLED=true, the registry warning should not appear.

  $ cat > dune-project <<EOF
  > (lang dune 3.0)
  > EOF

  $ cat > tool.ml <<EOF
  > let () = Array.iter print_endline (Array.sub Sys.argv 1 (Array.length Sys.argv - 1))
  > EOF

  $ cat > dune <<EOF
  > (executable (name tool))
  > (rule
  >  (alias test-long-path)
  >  (deps (env_var DUNE_LONG_PATH_ENABLED))
  >  (action (run ./tool.exe "$long_path_arg")))
  > EOF

With DUNE_LONG_PATH_ENABLED=false, registry warning should appear:

  $ DUNE_LONG_PATH_ENABLED=false dune build @test-long-path 2>&1 | sanitize_long_path_output
  Warning: Path
  "some/path/<LONG_PATH>"
  exceeds the Windows MAX_PATH limit of 260 characters.
  The LongPathsEnabled registry key does not appear to be set.
  Enable it with:
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
  Warning: _build/default/tool.exe does not appear to support long paths, but
  dune is passing a path of NNN characters. The build may fail unless
  _build/default/tool.exe has a longPathAware manifest or LongPathsEnabled is
  set system-wide.
  some/path/<LONG_PATH>

Check that check_and_warn was called and saw the long arg:

  $ dune trace cat | jq -c 'select(.args.message? == "Long_path_check.check_and_warn")' | head -1 | jq '{nargs: .args.nargs, max_arg_len: .args.max_arg_len}'
  {
    "nargs": 1,
    "max_arg_len": 7
  }

With DUNE_LONG_PATH_ENABLED=true, no registry warning:

  $ DUNE_LONG_PATH_ENABLED=true dune build @test-long-path 2>&1 | sanitize_long_path_output
  Warning: _build/default/tool.exe does not appear to support long paths, but
  dune is passing a path of NNN characters. The build may fail unless
  _build/default/tool.exe has a longPathAware manifest or LongPathsEnabled is
  set system-wide.
  some/path/<LONG_PATH>
