Two revisions with the same cram test but different implementations:
the test passes at the first rev and fails at the second. Verify
that [--rev <a> --rev <b> @runtest] fans the alias out across both
synthesised contexts AND that the failing rev surfaces its diff.

  $ git init --quiet

Initial commit: implementation prints "hello", cram test expects it.

  $ make_dune_project 3.25
  $ cat > test.t << 'EOF'
  >   $ cat greeting.txt
  >   hello
  > EOF
  $ echo "hello" > greeting.txt
  $ cat > dune << 'EOF'
  > (cram (deps greeting.txt))
  > EOF
  $ git add .
  $ git commit -q -m "initial"
  $ first=$(git rev-parse HEAD)

Second commit: implementation changes to "goodbye". This commit's
cram test will fail (since the .t file still expects "hello").

  $ echo "goodbye" > greeting.txt
  $ git add greeting.txt
  $ git commit -q -m "swap"
  $ second=$(git rev-parse HEAD)

  $ short() { git rev-parse "$1" | cut -c1-12; }

@runtest at the first rev: passes.

  $ dune build --rev "$first" @runtest
  $ echo "first-only exit $?"
  first-only exit 0

@runtest at the second rev: fails with the expected diff.

  $ dune build --rev "$second" @runtest 2>&1 \
  >   | sed -E 's/default-[0-9a-f]{12}/default-$SHA/g'
  File "test.t", line 1, characters 0-0:
  Context: default-$SHA
  --- test.t
  +++ test.t.corrected
  @@ -1,2 +1,2 @@
     $ cat greeting.txt
  -  hello
  +  goodbye
  [1]

@runtest against both revs in one invocation: the first rev passes,
the second fails, and dune prefixes the diff with the failing
context name. We redact the short SHA so the output is stable.

  $ dune build --rev "$first" --rev "$second" @runtest 2>&1 \
  >   | sed -E 's/default-[0-9a-f]{12}/default-$SHA/g'
  File "test.t", line 1, characters 0-0:
  Context: default-$SHA
  --- test.t
  +++ test.t.corrected
  @@ -1,2 +1,2 @@
     $ cat greeting.txt
  -  hello
  +  goodbye
  [1]
