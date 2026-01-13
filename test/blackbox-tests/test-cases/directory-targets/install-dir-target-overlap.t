Installing multiple directories into the same location merges their contents.
Originally reported as https://github.com/ocaml/dune/issues/13307

  $ cat >dune-project <<EOF
  > (lang dune 3.20)
  > (using directory-targets 0.1)
  > (package (name shared_files))
  > EOF

Create two rules that create directories and an install stanza that
places the contents of both at the same location.

  $ cat >dune <<EOF
  > (rule
  >  (target
  >   (dir a))
  >  (action
  >   (progn
  >    (run mkdir -p a/share)
  >    (run touch a/share/readme_a.txt))))
  > 
  > (rule
  >  (target
  >   (dir b))
  >  (action
  >   (progn
  >    (run mkdir -p b/share)
  >    (run touch b/share/readme_b.txt))))
  > 
  > (install
  >  (section share_root)
  >  (dirs
  >   (b/share as .)
  >   (a/share as .)))
  > EOF

The merged directory contains files from both sources:

  $ dune build @install
  $ ls _build/install/default/share/
  readme_a.txt
  readme_b.txt

Test conflict detection when both directories contain a file with the same name:

  $ cat >dune <<EOF
  > (rule
  >  (target (dir a))
  >  (action
  >   (progn
  >    (run mkdir -p a/share)
  >    (run touch a/share/readme.txt))))
  > 
  > (rule
  >  (target (dir b))
  >  (action
  >   (progn
  >    (run mkdir -p b/share)
  >    (run touch b/share/readme.txt))))
  > 
  > (install
  >  (section share_root)
  >  (dirs
  >   (b/share as .)
  >   (a/share as .)))
  > EOF

  $ dune clean
  $ dune build @install 2>&1 | head -5
  File "dune", line 19, characters 3-10:
  19 |   (a/share as .)))
          ^^^^^^^
  Error: Conflict: file readme.txt would be installed from multiple
  directories:
  [1]
