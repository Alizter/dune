Benchmark traced vs untraced process execution times using hyperfine.

Setup a project with multiple compilation steps:

  $ cat > dune-project << EOF
  > (lang dune 3.0)
  > EOF

  $ mkdir lib

  $ cat > lib/dune << EOF
  > (library
  >  (name bench_lib))
  > EOF

Generate several modules to have enough data points:

  $ for i in $(seq 1 10); do
  >   cat > lib/m${i}.ml << MLEOF
  > let x${i} = ${i}
  > MLEOF
  >   cat > lib/m${i}.mli << MLIEOF
  > val x${i} : int
  > MLIEOF
  > done

Create directories for trace files:

  $ mkdir -p traces/untraced traces/traced

Create build scripts that save trace files using --trace-file with counter:

  $ cat > build_untraced.sh << 'EOF'
  > #!/bin/sh
  > COUNT_FILE=traces/untraced/.count
  > N=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
  > N=$((N + 1))
  > echo $N > "$COUNT_FILE"
  > rm -rf _build
  > unset DUNE_CONFIG__TRACE_FILE_OPENS
  > dune build --trace-file "traces/untraced/run_$N.trace" 2>/dev/null
  > EOF
  $ chmod +x build_untraced.sh

  $ cat > build_traced.sh << 'EOF'
  > #!/bin/sh
  > COUNT_FILE=traces/traced/.count
  > N=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
  > N=$((N + 1))
  > echo $N > "$COUNT_FILE"
  > rm -rf _build
  > export DUNE_CONFIG__TRACE_FILE_OPENS=enabled
  > dune build --trace-file "traces/traced/run_$N.trace" 2>/dev/null
  > EOF
  $ chmod +x build_traced.sh

Warmup - ensure everything is cached:

  $ ./build_untraced.sh
  $ ./build_traced.sh

Run hyperfine benchmark (3 runs each for speed):

  $ hyperfine --warmup 1 --runs 3 --export-json bench.json \
  >   './build_untraced.sh' \
  >   './build_traced.sh' >/dev/null 2>&1

Calculate overhead from hyperfine results:

  $ jq '
  >   (.results[0].mean * 1000 | round) as $untraced_ms |
  >   (.results[1].mean * 1000 | round) as $traced_ms |
  >   (.results[0].stddev * 1000 | round) as $untraced_std |
  >   (.results[1].stddev * 1000 | round) as $traced_std |
  >   (($traced_ms - $untraced_ms) / $untraced_ms * 100 | round) as $overhead_pct |
  >   {
  >     untraced_ms: $untraced_ms,
  >     untraced_stddev: $untraced_std,
  >     traced_ms: $traced_ms,
  >     traced_stddev: $traced_std,
  >     overhead_pct: $overhead_pct,
  >     overhead_ms: ($traced_ms - $untraced_ms)
  >   }
  > ' bench.json
  {
    "untraced_ms": 1309,
    "untraced_stddev": 67,
    "traced_ms": 1660,
    "traced_stddev": 65,
    "overhead_pct": 27,
    "overhead_ms": 351
  }

Analyze trace files - extract per-process timing stats:

  $ for f in traces/untraced/run_*.trace; do
  >   dune trace cat --trace-file "$f" 2>/dev/null | jq -s '
  >     [ .[] | select(.name == "finish" and .args.prog and (.args.prog | test("ocaml"))) | .dur ]
  >     | { total_s: (add // 0), count: length, avg_ms: (if length > 0 then (add / length * 1000) else 0 end) }
  >   '
  > done | jq -s '{
  >   runs: length,
  >   avg_total_s: (map(.total_s) | add / length),
  >   avg_per_process_ms: (map(.avg_ms) | add / length),
  >   process_count: .[0].count
  > }' > untraced_stats.json

  $ for f in traces/traced/run_*.trace; do
  >   dune trace cat --trace-file "$f" 2>/dev/null | jq -s '
  >     [ .[] | select(.name == "finish" and .args.prog and (.args.prog | test("ocaml"))) | .dur ]
  >     | { total_s: (add // 0), count: length, avg_ms: (if length > 0 then (add / length * 1000) else 0 end) }
  >   '
  > done | jq -s '{
  >   runs: length,
  >   avg_total_s: (map(.total_s) | add / length),
  >   avg_per_process_ms: (map(.avg_ms) | add / length),
  >   process_count: .[0].count
  > }' > traced_stats.json

Final comparison - process-level overhead from traces:

  $ jq -s '
  >   (.[0].avg_per_process_ms) as $untraced |
  >   (.[1].avg_per_process_ms) as $traced |
  >   (.[0].process_count) as $count |
  >   "Process overhead: \((($traced - $untraced) * 10 | round / 10))ms per ocaml invocation (\($count) invocations per build)"
  > ' untraced_stats.json traced_stats.json
  "Process overhead: 5.2ms per ocaml invocation (56 invocations per build)"
