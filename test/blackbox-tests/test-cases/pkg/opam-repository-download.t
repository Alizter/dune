Helper shell function that generates an opam file for a package:

  $ . ./helpers.sh
  $ mkrepo

Make a mock repo tarball that will get used by dune to download the package

  $ mkpkg foo <<EOF
  > EOF
  $ mkpkg bar <<EOF
  > depends: [ "foo" ]
  > EOF
  $ cd mock-opam-repository
  $ tar czf ../index.tar.gz *
  $ cd ..

Create a dune project with a minimal single-request HTTP server. This is built and used to
serve our opam-repository as a mock.

  $ cat > dune-project <<EOF
  > (lang dune 3.8)
  > (generate_opam_files true)
  > 
  > (package
  >   (name baz)
  >   (depends
  >     bar))
  > EOF
  $ cat > dune <<EOF
  > (executable
  >   (public_name server)
  >   (libraries stdune)
  >   ;; stdune is showing the unstable alert but since this is part of the
  >   ;; dune codebase, this test has to be adjusted in case the API changes
  >   (flags -alert -unstable))
  > EOF
  > cat > server.ml <<EOF
  > open Stdune
  > let serve_once ~filename ~port () =
  >   let host = Unix.inet_addr_loopback in
  >   let addr = Unix.ADDR_INET (host, port) in
  >   let sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  >   Unix.setsockopt sock Unix.SO_REUSEADDR true;
  >   Unix.bind sock addr;
  >   Unix.listen sock 5;
  >   (* signal we're done setting up *)
  >   let pid = open_out "server.pid" in
  >   close_out pid;
  >   let descr, _sockaddr = Unix.accept sock in
  >   let content = Io.String_path.read_file filename in
  >   let content_length = String.length content in
  >   let write_end = Unix.out_channel_of_descr descr in
  >   Printf.fprintf write_end {|HTTP/1.1 200 Ok
  > Content-Length: %d
  > 
  > %s|}
  >     content_length content;
  >   close_out write_end
  > 
  > let () =
  >   let port = int_of_string (Sys.argv.(1)) in
  >   serve_once ~filename:"index.tar.gz" ~port ()
  > EOF
  $ PORT=$(shuf -i 2048-65000 -n 1)
  $ dune exec -- ./server.exe $PORT &
  $ # wait for server to come up, this takes a bit
  $ while [ ! -f server.pid ]; do sleep 0.01; done
  $ rm server.pid

Run Dune and tell it to cache into our custom cache folder.

  $ mkdir fake-xdg-cache
  $ XDG_CACHE_HOME=$(pwd)/fake-xdg-cache dune pkg lock --opam-repository-url=http://localhost:$PORT/index.tar.gz
  Solution for dune.lock:
  bar.0.0.1
  foo.0.0.1
  

Our custom cache folder should be populated with the unpacked tarball
containing the repository:

  $ find fake-xdg-cache | sort
  fake-xdg-cache
  fake-xdg-cache/dune
  fake-xdg-cache/dune/opam-repository
  fake-xdg-cache/dune/opam-repository/packages
  fake-xdg-cache/dune/opam-repository/packages/bar
  fake-xdg-cache/dune/opam-repository/packages/bar/bar.0.0.1
  fake-xdg-cache/dune/opam-repository/packages/bar/bar.0.0.1/opam
  fake-xdg-cache/dune/opam-repository/packages/foo
  fake-xdg-cache/dune/opam-repository/packages/foo/foo.0.0.1
  fake-xdg-cache/dune/opam-repository/packages/foo/foo.0.0.1/opam
  fake-xdg-cache/dune/opam-repository/repo

Let's make sure this works with git repositories as well, by putting our repo in git.

  $ cd mock-opam-repository
  $ git init --quiet
  $ git add -A
  $ git commit -m "Initial commit" > /dev/null
  $ REPO_HASH=$(git rev-parse HEAD)
  $ cd ..

Automatically download the repo and make sure lock.dune contains the repo hash
(exit code 0 from grep, we don't care about the output as it is not
reproducible)

  $ rm -r dune.lock
  $ mkdir fake-xdg-cache-with-git
  $ XDG_CACHE_HOME=$(pwd)/fake-xdg-cache-with-git dune pkg lock --opam-repository-url=git+file://$(pwd)/mock-opam-repository
  Solution for dune.lock:
  bar.0.0.1
  foo.0.0.1
  

  $ grep "git_hash $REPO_HASH" dune.lock/lock.dune > /dev/null

Now try it with an existing cached dir, which given it is not reproducible should not be included

  $ rm -r dune.lock
  $ dune pkg lock --opam-repository-path=$(pwd)/fake-xdg-cache-with-git/dune/opam-repository
  Solution for dune.lock:
  bar.0.0.1
  foo.0.0.1
  

  $ grep "git_hash $REPO_HASH" dune.lock/lock.dune > /dev/null || echo "not found"
  not found


The repository can also be injected via the dune-workspace file

  $ cat > dune-workspace <<EOF
  > (lang dune 3.10)
  > (repository
  >   (name foo)
  >   (source "git+file://$(pwd)/mock-opam-repository"))
  > (context
  >   (default
  >     (name default)
  >     (solver_env
  >       (repositories foo))))
  > EOF
  $ mkdir dune-workspace-cache
  $ XDG_CACHE_HOME=$(pwd)/dune-workspace-cache dune pkg lock
  Solution for dune.lock:
  bar.0.0.1
  foo.0.0.1
  

  $ grep "git_hash $REPO_HASH" dune.lock/lock.dune > /dev/null
