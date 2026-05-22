Bash completion scripts fall back to filename completion when Dune has no
semantic completions to offer.

This test sources the generated bash completion script, asks bash which
completion it registered for dune, and exercises that completion registration.

  $ mkdir completions
  $ touch completions/bash.t completions/other-file
  $ bash <<'EOF'
  > enable complete compgen
  > source <(dune completion bash)
  > _get_comp_words_by_ref() {
  >   local words_var="${@: -2:1}"
  >   local cword_var="${@: -1}"
  >   eval "$words_var=(\"\${COMP_WORDS[@]}\")"
  >   printf -v "$cword_var" "%s" "$COMP_CWORD"
  > }
  > cd completions
  > COMP_WORDS=(dune runtest bas)
  > COMP_CWORD=2
  > completion=( $(complete -p dune) )
  > completion[0]=compgen
  > unset "completion[${#completion[@]}-1]"
  > "${completion[@]}" -- bas 2>stderr
  > sed '/compgen: warning: -F option may not work as you expect/d' stderr
  > EOF
  bash.t

Semantic directory candidates suppress Bash's default trailing-space behavior.
Use a synthetic completion response so this behavior is covered independently
of any command-specific semantic completer.

  $ bash <<'EOF'
  > enable complete compgen
  > source <(dune completion bash)
  > _get_comp_words_by_ref() {
  >   local words_var="${@: -2:1}"
  >   local cword_var="${@: -1}"
  >   eval "$words_var=(\"\${COMP_WORDS[@]}\")"
  >   printf -v "$cword_var" "%s" "$COMP_CWORD"
  > }
  > semantic_completion() {
  >   printf '%s\n' 1 item tests/ item-end
  > }
  > compopt() {
  >   printf '%s\n' "$*" >>compopt.log
  > }
  > : >compopt.log
  > COMP_WORDS=(semantic_completion tes)
  > COMP_CWORD=1
  > completion=( $(complete -p dune) )
  > completion[0]=compgen
  > unset "completion[${#completion[@]}-1]"
  > "${completion[@]}" -- tes 2>/dev/null
  > if test -s compopt.log; then cat compopt.log; else echo "trailing space"; fi
  > EOF
  tests/
  -o nospace

Semantic directory candidates keep completion active inside the directory.

  $ mkdir -p project/tests
  $ cat > project/dune-project <<'EOF'
  > (lang dune 3.21)
  > EOF
  $ cat > project/tests/example.t <<'EOF'
  >   $ true
  > EOF
  $ bash <<'EOF'
  > enable complete compgen
  > source <(dune completion bash)
  > _get_comp_words_by_ref() {
  >   local words_var="${@: -2:1}"
  >   local cword_var="${@: -1}"
  >   eval "$words_var=(\"\${COMP_WORDS[@]}\")"
  >   printf -v "$cword_var" "%s" "$COMP_CWORD"
  > }
  > compopt() {
  >   printf '%s\n' "$*" >>compopt.log
  > }
  > cd project
  > COMP_WORDS=(dune runtest tes)
  > COMP_CWORD=2
  > completion=( $(complete -p dune) )
  > completion[0]=compgen
  > unset "completion[${#completion[@]}-1]"
  > "${completion[@]}" -- tes 2>/dev/null
  > cat compopt.log
  > mkdir "tests with spaces"
  > cat > "tests with spaces/example.t" <<'INNER_EOF'
  >   $ true
  > INNER_EOF
  > : >compopt.log
  > COMP_WORDS=(dune runtest "tests w")
  > "${completion[@]}" -- "tests w" 2>/dev/null
  > cat compopt.log
  > cat > top.t <<'INNER_EOF'
  >   $ true
  > INNER_EOF
  > : >compopt.log
  > COMP_WORDS=(dune runtest t)
  > "${completion[@]}" -- t 2>/dev/null
  > test ! -s compopt.log
  > EOF
  tests/
  -o nospace
  tests with spaces/
  -o nospace
  tests with spaces/
  tests/
  top.t
