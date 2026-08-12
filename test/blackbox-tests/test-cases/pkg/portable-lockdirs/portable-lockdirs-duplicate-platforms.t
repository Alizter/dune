Duplicate platforms in `solve_for_platforms` are deduplicated before solving:
the lock directory lists each platform once and the SAT engine runs exactly
once for the requested platform set.

  $ mkrepo
  $ add_mock_repo_if_needed

  $ mkpkg foo <<EOF
  > build: [
  >   ["mkdir" "-p" share "%{lib}%/%{name}%"]
  >   ["touch" "%{lib}%/%{name}%/META"] # needed for dune to recognize this as a library
  > ]
  > EOF

Solve for the same platform twice:
  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > (lock_dir
  >  (repositories mock)
  >  (solve_for_platforms
  >   ((arch x86_64) (os openbsd))
  >   ((arch x86_64) (os openbsd))))
  > (pkg enabled)
  > EOF

  $ make_portable_lockdirs_project

  $ DUNE_TRACE=+sat dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - foo.0.0.1

The platform is listed once in the lock directory:
  $ cat ${default_lock_dir}/lock.dune
  (lang package 0.1)
  
  (dependency_hash 36e640fbcda71963e7e2f689f6c96c3e)
  
  (repositories
   (complete false)
   (used))
  
  (solved_for_platforms
   ((arch x86_64)
    (os openbsd)))

And exactly one SAT solve happens for the deduplicated platform set:
  $ dune trace cat \
  > | jq -s 'include "dune"; [ .[] | satSolveEvents | .args ]'
  [
    {
      "num_variables": 4,
      "num_clauses": 4,
      "num_decisions": 0,
      "num_conflicts": 0
    }
  ]
