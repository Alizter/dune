Test that non-ASCII characters in version strings produce a clear error.

Helper to test invalid version strings:

  $ test_invalid_version() {
  >   cat > dune-project <<EOF
  > (lang dune $1)
  > EOF
  >   dune build 2>&1 | sed 's/3\.[0-9][0-9]/3.XX/g'
  > }

Test with various non-ASCII characters:

  $ test_invalid_version "Ali"
  File "dune-project", line 1, characters 11-14:
  1 | (lang dune Ali)
                 ^^^
  Error: Invalid version. Version must be two numbers separated by a dot.
  Hint: (lang dune 3.XX)

  $ test_invalid_version "è"
  File "dune-project", line 1, characters 11-13:
  1 | (lang dune è)
                 ^^
  Error: Invalid version. Version must contain only ASCII characters and be two
  numbers separated by a dot.
  Hint: (lang dune 3.XX)

  $ test_invalid_version "π3.14"
  File "dune-project", line 1, characters 11-17:
  1 | (lang dune π3.XX)
                 ^^^^^^
  Error: Invalid version. Version must contain only ASCII characters and be two
  numbers separated by a dot.
  Hint: (lang dune 3.XX)

  $ test_invalid_version "α"
  File "dune-project", line 1, characters 11-13:
  1 | (lang dune α)
                 ^^
  Error: Invalid version. Version must contain only ASCII characters and be two
  numbers separated by a dot.
  Hint: (lang dune 3.XX)

  $ test_invalid_version "😀"
  File "dune-project", line 1, characters 11-15:
  1 | (lang dune 😀)
                 ^^^^
  Error: Invalid version. Version must contain only ASCII characters and be two
  numbers separated by a dot.
  Hint: (lang dune 3.XX)

  $ test_invalid_version "中3.16文"
  File "dune-project", line 1, characters 11-21:
  1 | (lang dune 中3.XX文)
                 ^^^^^^^^^^
  Error: Invalid version. Version must contain only ASCII characters and be two
  numbers separated by a dot.
  Hint: (lang dune 3.XX)

  $ test_invalid_version "-1.2"
  File "dune-project", line 1, characters 11-15:
  1 | (lang dune -1.2)
                 ^^^^
  Error: Invalid version. Version must be two numbers separated by a dot.
  Hint: (lang dune 3.XX)
