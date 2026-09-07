Test that solver vars in filters are replaced by their values in filter
expressions in lockfiles.

  $ mkrepo

Declare a package which refers to some variables:
  $ mkpkg a <<EOF
  > build: [
  >   ["dune" "subst"] {dev}
  >   [
  >     "dune"
  >     "build"
  >     "-p"
  >     name
  >     "-j"
  >     jobs
  >     "--foobar" { foo = "bar" }
  >     "@install"
  >     "@runtest" {with-test}
  >     "@doc" {with-doc}
  >   ]
  > ]
  > EOF

Solve the package using the default solver env:
  $ solve a
  Solution for dune.lock:
  - a.0.0.1
  $ cat ${default_lock_dir}/a.0.0.1.pkg
  (version 0.0.1)
  
  (build
   (all_platforms
    ((action
      (progn
       (when %{pkg-self:dev} (run dune subst))
       (run
        dune
        build
        -p
        %{pkg-self:name}
        -j
        %{jobs}
        (when (catch_undefined_var (= %{pkg-self:foo} bar) false) --foobar)
        @install))))))

Make a custom solver env:
  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (pkg enabled)
  > (lock_dir
  >  (path dune.lock)
  >  (repositories mock)
  >  (solver_env
  >   (dev false)
  >   (with-doc true)
  >   (foo bar)))
  > (context
  >  (default
  >   (name default)
  >   (lock_dir dune.lock)))
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > EOF

Run the solver using the new env:
  $ solve a
  Solution for dune.lock:
  - a.0.0.1
  $ cat ${default_lock_dir}/a.0.0.1.pkg
  (version 0.0.1)
  
  (build
   (all_platforms
    ((action
      (run dune build -p %{pkg-self:name} -j %{jobs} --foobar @install @doc)))))

A live workspace package is a development package, even when it has a version.
Its dev-only dependencies should be included without setting dev globally for
all repository packages.

  $ mkdir local-dev
  $ cd local-dev
  $ mkrepo
  $ create_mock_repo
  $ mkpkg development-only
  $ mkpkg regular <<'EOF'
  > depends: [ "missing-repository-dev-dependency" {dev} ]
  > EOF
  $ cat > dune-project <<'EOF'
  > (lang dune 3.24)
  > (package
  >  (name app)
  >  (version 1.0)
  >  (allow_empty)
  >  (depends regular (development-only :dev)))
  > EOF

BUG: dev is unbound for the workspace package, so development-only is omitted.
The nonexistent dev-only dependency of regular must remain excluded.

  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - regular.0.0.1
  $ dune pkg validate-lockdir

The same local binding must be used for packages described by opam files,
including both the unqualified dev variable and the explicit _:dev form.

  $ mkpkg self-development-only
  $ cat > dune-project <<'EOF'
  > (lang dune 3.24)
  > EOF
  $ cat > app.opam <<'EOF'
  > opam-version: "2.0"
  > version: "1.0"
  > depends: [
  >   "regular"
  >   "development-only" {dev}
  >   "self-development-only" {_:dev}
  > ]
  > EOF
  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - regular.0.0.1
  $ dune pkg validate-lockdir
