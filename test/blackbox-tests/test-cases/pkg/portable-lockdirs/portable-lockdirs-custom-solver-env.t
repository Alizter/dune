Exercise solving with a custom non-platform variable in the lock stanza's
solver environment.

  $ mkrepo
  $ add_mock_repo_if_needed

Create a workspace that enables with-doc without changing the platform selected
from OS polling:
  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (pkg enabled)
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > (lock_dir
  >  (path dune.lock)
  >  (repositories mock)
  >  (solver_env
  >   (with-doc true)))
  > EOF

Create a package with a build action guarded by with-doc:
  $ mkpkg foo <<EOF
  > build: [
  >   ["mkdir" "-p" share "%{lib}%/%{name}%"]
  >   ["touch" "%{lib}%/%{name}%/META"] # needed for dune to recognize this as a library
  >   ["sh" "-c" "echo enabled > %{share}%/with-doc"] { with-doc }
  > ]
  > EOF

Set up a project that depends on the package:
  $ make_portable_lockdirs_project

Solve the project:
  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - foo.0.0.1

Confirming that the build action creates the conditional file:
  $ cat ${default_lock_dir}/foo.0.0.1.pkg
  (version 0.0.1)
  
  (build
   (all_platforms
    ((action
      (progn
       (run mkdir -p %{share} %{lib}/%{pkg-self:name})
       (run touch %{lib}/%{pkg-self:name}/META)
       (run sh -c "echo enabled > %{share}/with-doc"))))))

The selected action remains available when the package is built:
  $ dune build
  $ cat _build/_private/default/.pkg/$(dune pkg print-digest foo)/target/share/with-doc
  enabled
