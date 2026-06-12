End-to-end: a workspace executable links against a mount library.
[dune exec] runs the workspace binary, which calls into mount code.

  $ mkdir mount-src
  $ cat > mount-src/dune-project << EOF
  > (lang dune 3.25)
  > (package (name greeter))
  > EOF
  $ cat > mount-src/dune << EOF
  > (library
  >  (name greeter)
  >  (public_name greeter))
  > EOF
  $ cat > mount-src/greeter.ml << EOF
  > let say msg = print_endline ("greeter says: " ^ msg)
  > EOF

  $ mkdir wksp
  $ cd wksp
  $ cat > dune-project << EOF
  > (lang dune 3.25)
  > EOF
  $ cat > dune << EOF
  > (executable
  >  (name main)
  >  (libraries greeter))
  > EOF
  $ cat > main.ml << EOF
  > let () = Greeter.say "from workspace"
  > EOF
  $ cat > dune-workspace << EOF
  > (lang dune 3.25)
  > (context
  >  (default
  >   (mount $PWD/../mount-src)))
  > EOF

The workspace executable builds with the mount library linked in,
and running it invokes the cross-mount code.

  $ dune exec ./main.exe
  greeter says: from workspace
