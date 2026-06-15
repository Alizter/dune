When two revs share a byte-identical file, the Git backend should
issue exactly one [git cat-file blob <sha>] for that file across the
whole build — the blob's contents are read once and shared.

Setup: two commits where [shared.txt] is byte-identical and
[changed.txt] differs.

  $ git init --quiet
  $ make_dune_project 3.25
  $ echo "shared bytes" > shared.txt
  $ echo "v1" > changed.txt
  $ cat > dune << 'EOF'
  > (rule
  >  (target out)
  >  (deps shared.txt changed.txt)
  >  (action
  >   (with-stdout-to %{target} (bash "cat shared.txt changed.txt"))))
  > EOF
  $ git add .
  $ git commit -q -m "v1"
  $ first=$(git rev-parse HEAD)
  $ shared_sha=$(git ls-tree HEAD shared.txt | awk '{print $3}')

  $ echo "v2" > changed.txt
  $ git add changed.txt
  $ git commit -q -m "v2"
  $ second=$(git rev-parse HEAD)

Build both revs in one invocation.

  $ dune build --rev "$first" --rev "$second" out

Count the [git cat-file blob <sha>] calls per sha. With blob-sha
memoisation, every distinct blob should appear exactly once across
both contexts. The histogram is "<unique-sha-count> 1": every sha
fetched once. Without dedup we'd see "<sha-count> 2" for shared
blobs.

  $ dune trace cat \
  >   | jq -r 'select(.cat == "process" and .name == "start"
  >                   and .args.process_args[0] == "cat-file"
  >                   and .args.process_args[1] == "blob")
  >         | .args.process_args[2]' \
  >   | sort | uniq -c | awk '{print $1}' | sort | uniq -c
        5 1

Confirm that the specifically-shared [shared.txt] blob is fetched
only once across both rev contexts:

  $ dune trace cat \
  >   | jq -r --arg sha "$shared_sha" \
  >       'select(.cat == "process" and .name == "start"
  >               and .args.process_args[0] == "cat-file"
  >               and .args.process_args[1] == "blob"
  >               and .args.process_args[2] == $sha)
  >        | .args.process_args[2]' \
  >   | wc -l
  1
