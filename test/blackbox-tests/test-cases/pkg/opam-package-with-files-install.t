This test demonstrates a package where the .install file being created by the
file copying step rather than the build step.

  $ . ./helpers.sh

  $ make_lockdir
  $ mkdir -p ${source_lock_dir}/foo.files

  $ touch ${source_lock_dir}/foo.files/foo.install
  $ echo "(version 0.0.1)" > ${source_lock_dir}/foo.pkg

The foo.install file in files/ should have been copied over.
  $ build_pkg foo 2>&1
