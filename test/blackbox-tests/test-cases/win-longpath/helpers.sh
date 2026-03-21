long_path_arg="some/path/$(printf 'b%.0s' $(seq 1 270))"

sanitize_long_path_output() {
  dune_cmd subst '[A-Z]:\\.*\.exe' '<PROG>' \
    | dune_cmd subst 'path of [0-9]+' 'path of NNN' \
    | dune_cmd subst 'b{20,}' '<LONG_PATH>' \
    | dune_cmd subst '_build/\.sandbox/[0-9a-f]+' '_build/.sandbox/<HASH>'
}
