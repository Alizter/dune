If two revs contain a byte-identical OCaml module, building both
should share the compile artifacts via the shared cache — the
ocamlc/ocamlopt actions should hit on the second rev. Storage dedup
isn't enough: we want zero re-compilation of unchanged modules
across revs.

  $ export XDG_CACHE_HOME=$(dune_cmd native-path $PWD/.xdg-cache)
  $ setup_xdg_runtime_dir
  $ export DUNE_TRACE=cache

  $ cat > config << 'EOF'
  > (lang dune 3.0)
  > (cache enabled)
  > EOF

A small library at the first rev.

  $ git init --quiet
  $ make_dune_project 3.25
  $ cat > dune << 'EOF'
  > (library (name foo) (modes byte))
  > EOF
  $ cat > foo.ml << 'EOF'
  > let answer = 42
  > EOF
  $ git add .
  $ git commit -q -m "v1"
  $ first=$(git rev-parse HEAD)

Second commit: unrelated change (commit message only — different
git history but same source contents).

  $ touch unrelated
  $ git add unrelated
  $ git commit -q -m "v2"
  $ second=$(git rev-parse HEAD)

  $ short() { git rev-parse "$1" | cut -c1-12; }

Build at the first rev (cold cache).

  $ dune build --config-file=config --rev "$first" foo.cma

Build at the second rev. With byte-identical [foo.ml] across revs,
[foo.cma]'s ocamlc compile action should HIT the shared cache. We
look for hit events for the compile outputs (.cmi/.cmo/.cma).

  $ rm -f _build/trace.csexp
  $ dune build --config-file=config --rev "$second" foo.cma

  $ dune trace cat \
  >   | jq -c 'select(.cat == "cache") | {name, target: (.args.target // .args.head)}' \
  >   | sed -E "s|default-[0-9a-f]+|default-\$SHA|g" \
  >   | grep -E "foo\.(cmi|cmo|cma)" \
  >   | sort -u
  {"name":"miss","target":"_build/default-$SHA/.foo.objs/byte/foo.cmi"}
  {"name":"miss","target":"_build/default-$SHA/foo.cma"}
  {"name":"workspace_local_miss","target":"_build/default-$SHA/.foo.objs/byte/foo.cmi"}
  {"name":"workspace_local_miss","target":"_build/default-$SHA/foo.cma"}

Today every compile output is a [miss] on the second rev — the
ocamlc action re-runs even though [foo.ml] is byte-identical across
revs. When the trace-digest issue is fixed those misses should turn
into [hit] entries.
