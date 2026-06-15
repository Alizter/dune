An action whose inputs are byte-identical across two revisions
should be cached once. We verify this with cache trace events
(workspace-local miss + cache hit) — the most direct evidence that
work was actually shared — plus hardlink counts.

**Current state**: the trace events show that the shared cache is
NOT hitting across revs — the action re-runs on every rev. Storage
deduplication still happens (same output content → same SHA →
hardlink to the existing cache entry, so [out]'s hardlink count
still grows). This test pins the current behaviour so a future fix
to the trace-digest computation can be observed via a diff. See
doc/dev/build-rev.md ("zero-cache-hit anomaly").

  $ export XDG_CACHE_HOME=$(dune_cmd native-path $PWD/.xdg-cache)
  $ setup_xdg_runtime_dir
  $ export DUNE_TRACE=cache

  $ cat > config << 'EOF'
  > (lang dune 3.0)
  > (cache enabled)
  > EOF

A small project producing a target [out] from an input file.

  $ git init --quiet
  $ make_dune_project 3.25
  $ cat > input.txt << 'EOF'
  > content
  > EOF
  $ cat > dune << 'EOF'
  > (rule
  >  (deps input.txt)
  >  (target out)
  >  (action (bash "tr a-z A-Z < input.txt > out")))
  > EOF
  $ git add .
  $ git commit -q -m "first"
  $ first=$(git rev-parse HEAD)

Second commit: change something unrelated. The rule's [input.txt]
dep is byte-identical to the first rev's.

  $ touch unrelated
  $ git add unrelated
  $ git commit -q -m "second"
  $ second=$(git rev-parse HEAD)

  $ short() { git rev-parse "$1" | cut -c1-12; }

Build at the first rev. Both [input.txt] (the source-copy target)
and [out] (the action target) are computed for the first time:
workspace-local and shared cache misses for both.

  $ dune build --config-file=config --rev "$first" out
  $ dune trace cat | jq_dune -s 'cacheMissesMatching("input.txt|out")' \
  >   | sed -E "s|default-[0-9a-f]+|default-\$SHA|g"
  {
    "name": "workspace_local_miss",
    "target": "_build/default-$SHA/input.txt",
    "reason": "never seen this target before"
  }
  {
    "name": "miss",
    "target": "_build/default-$SHA/input.txt",
    "reason": "not found in cache"
  }
  {
    "name": "workspace_local_miss",
    "target": "_build/default-$SHA/out",
    "reason": "never seen this target before"
  }
  {
    "name": "miss",
    "target": "_build/default-$SHA/out",
    "reason": "not found in cache"
  }

After the first build the targets are hardlinked into the shared
cache (hardlink count 2: cache entry + build-dir file).

  $ dune_cmd stat hardlinks "_build/default-$(short "$first")/out"
  2

Build at the second rev. The trace files persist across runs, so
clear it to read only the second build's events.

  $ rm -f _build/trace.csexp
  $ dune build --config-file=config --rev "$second" out

All cache events emitted by the second rev's build (paths
censored). Today every interesting target shows as a [miss], even
though the action's inputs are byte-identical to the first rev:
that's the bug. When it's fixed, the [miss] entries for [input.txt]
and [out] should turn into [hit] entries.

  $ dune trace cat | jq -c 'select(.cat == "cache") | {name, target: (.args.target // .args.head), reason: .args.reason}' \
  >   | sed -E "s|default-[0-9a-f]+|default-\$SHA|g" | sort
  {"name":"miss","target":"_build/default-$SHA/.dune/configurator","reason":"not found in cache"}
  {"name":"miss","target":"_build/default-$SHA/.dune/configurator.v2","reason":"not found in cache"}
  {"name":"miss","target":"_build/default-$SHA/input.txt","reason":"not found in cache"}
  {"name":"miss","target":"_build/default-$SHA/out","reason":"not found in cache"}
  {"name":"workspace_local_miss","target":"_build/default-$SHA/.dune/configurator","reason":"never seen this target before"}
  {"name":"workspace_local_miss","target":"_build/default-$SHA/.dune/configurator.v2","reason":"never seen this target before"}
  {"name":"workspace_local_miss","target":"_build/default-$SHA/input.txt","reason":"never seen this target before"}
  {"name":"workspace_local_miss","target":"_build/default-$SHA/out","reason":"never seen this target before"}

The second rev's [out] is hardlinked to the same cache entry as the
first rev's, so the hardlink counts grow to 3 (cache, first build,
second build).

  $ dune_cmd stat hardlinks "_build/default-$(short "$second")/out"
  3
  $ dune_cmd stat hardlinks "_build/default-$(short "$first")/out"
  3
