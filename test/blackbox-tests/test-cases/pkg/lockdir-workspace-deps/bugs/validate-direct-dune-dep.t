A direct dependency on dune from a workspace package is intentionally absent
from the solver's lockdir.

  $ mkrepo
  $ mkpkg dune
  $ add_mock_repo_if_needed
  $ cat > dune-project <<EOF
  > (lang dune 3.24)
  > (package
  >  (name direct)
  >  (allow_empty)
  >  (depends dune))
  > EOF
  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  (no dependencies to lock)

Validation treats dune as though it were an ordinary locked package:

  $ dune pkg validate-lockdir
  Lockdir dune.lock does not contain a solution for local packages:
  File "dune-project", lines 2-5, characters 0-55:
  Error: The dependencies of local package "direct" could not be satisfied from
  the lockdir:
  Package "dune" is missing
  Hint: The lockdir no longer contains a solution for the local packages in
  this project. Regenerate the lockdir by running: 'dune pkg lock'
  Error: Some lockdirs do not contain solutions for local packages:
  - dune.lock
  [1]
