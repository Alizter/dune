Testing the documentation of dune rpc

  $ dune rpc --help=plain
  NAME
         dune-rpc - Dune's RPC mechanism. Experimental.
  
  SYNOPSIS
         dune rpc COMMAND …
  
  DESCRIPTION
         This is experimental. Do not use.
  
  COMMANDS
         build [OPTION]… [TARGET]…
             Build a given target. (Requires Dune to be running in passive
             watching mode).
  
         ping [OPTION]…
             Ping the build server running in the current directory.
  
         status [OPTION]…
             Show active RPC connections.
  
  COMMON OPTIONS
         --help[=FMT] (default=auto)
             Show this help in format FMT. The value FMT must be one of auto,
             pager, groff or plain. With auto, the format is pager or plain
             whenever the TERM env var is dumb or undefined.
  
         --version
             Show version information.
  
  EXIT STATUS
         rpc exits with the following status:
  
         0   on success.
  
         123 on indiscriminate errors reported on standard error.
  
         124 on command line parsing errors.
  
         125 on unexpected internal errors (bugs).
  
  SEE ALSO
         dune(1)
  
  $ dune rpc ping --help=plain
  NAME
         dune-rpc-ping - Ping the build server running in the current
         directory.
  
  SYNOPSIS
         dune rpc ping [OPTION]…
  
  OPTIONS
         --action-stderr-on-success=VAL
             Same as --action-stdout-on-success but for the standard output for
             error messages. A good default for large mono-repositories is
             --action-stdout-on-success=swallow
             --action-stderr-on-success=must-be-empty. This ensures that a
             successful build has a "clean" empty output.
  
         --action-stdout-on-success=VAL
             Specify how to deal with the standard output of actions when they
             succeed. Possible values are: print to just print it to Dune's
             output, swallow to completely ignore it and must-be-empty to
             enforce that the action printed nothing. With must-be-empty, Dune
             will consider that the action failed if it printed something to
             its standard output. The default is print.
  
         --build-info
             Show build information.
  
         --error-reporting=VAL (absent=deterministic)
             Controls when the build errors are reported. early - report errors
             as soon as they are discovered. deterministic - report errors at
             the end of the build in a deterministic order. twice - report each
             error twice: once as soon as the error is discovered and then
             again at the end of the build, in a deterministic order.
  
         -f, --force
             Force actions associated to aliases to be re-executed even if
             their dependencies haven't changed.
  
         --file-watcher=VAL (absent=automatic)
             Mechanism to detect changes in the source. Automatic to make dune
             run an external program to detect changes. Manual to notify dune
             that files have changed manually."
  
         --passive-watch-mode
             Similar to [--watch], but only start a build when instructed
             externally by an RPC.
  
         --react-to-insignificant-changes
             react to insignificant file system changes; this is only useful
             for benchmarking dune
  
         --sandbox=VAL (absent DUNE_SANDBOX env)
             Sandboxing mode to use by default. Some actions require a certain
             sandboxing mode, so they will ignore this setting. The allowed
             values are: none, symlink, copy, hardlink.
  
         -w, --watch
             Instead of terminating build after completion, wait continuously
             for file changes.
  
         --wait-for-filesystem-clock
             Dune digest file contents for better incrementally. These digests
             are themselves cached. In some cases, Dune needs to drop some
             digest cache entries in order for things to be reliable. This
             option makes Dune wait for the file system clock to advance so
             that it doesn't need to drop anything. You should probably not
             care about this option; it is mostly useful for Dune developers to
             make Dune tests of the digest cache more reproducible.
  
  COMMON OPTIONS
         --always-show-command-line
             Always show the full command lines of programs executed by dune
  
         --auto-promote
             Automatically promote files. This is similar to running dune
             promote after the build.
  
         --build-dir=FILE (absent DUNE_BUILD_DIR env)
             Specified build directory. _build if unspecified
  
         --cache=VAL (absent DUNE_CACHE env)
             Enable or disable Dune cache (either enabled or disabled). Default
             is `disabled'.
  
         --cache-check-probability=VAL (absent DUNE_CACHE_CHECK_PROBABILITY
         env)
             Check build reproducibility by re-executing randomly chosen rules
             and comparing their results with those stored in Dune cache. Note:
             by increasing the probability of such checks you slow down the
             build. The default probability is zero, i.e. no rules are checked.
  
         --cache-storage-mode=VAL (absent DUNE_CACHE_STORAGE_MODE env)
             Dune cache storage mode (one of auto, hardlink or copy). Default
             is `auto'.
  
         --config-file=FILE
             Load this configuration file instead of the default one.
  
         --debug-artifact-substitution
             Print debugging info about artifact substitution
  
         --debug-backtraces
             Always print exception backtraces.
  
         --debug-cache=VAL
             Show debug messages on cache misses for the given cache layers.
             Value is a comma-separated list of cache layer names. All
             available cache layers: shared,workspace-local,fs.
  
         --debug-dependency-path
             In case of error, print the dependency path from the targets on
             the command line to the rule that failed. 
  
         --debug-digests
             Explain why Dune decides to re-digest some files
  
         --debug-findlib
             Debug the findlib sub-system.
  
         --debug-load-dir
             Print debugging info about directory loading
  
         --debug-store-digest-preimage
             Store digest preimage for all computed digests, so that it's
             possible to reverse them later, for debugging. The digests are
             stored in the shared cache (see --cache flag) as values, even if
             cache is otherwise disabled. This should be used only for
             debugging, since it's slow and it litters the shared cache.
  
         --default-target=TARGET (absent=@@default)
             Set the default target that when none is specified to dune build.
  
         --diff-command=VAL (absent DUNE_DIFF_COMMAND env)
             Shell command to use to diff files. Use - to disable printing the
             diff.
  
         --disable-promotion (absent DUNE_DISABLE_PROMOTION env)
             Disable all promotion rules
  
         --display=MODE
             Control the display mode of Dune. See dune-config(5) for more
             details.
  
         --dump-memo-graph=FILE
             Dumps the dependency graph to a file after the build is complete
  
         --dump-memo-graph-format=FORMAT (absent=gexf)
             File format to be used when dumping dependency graph
  
         --dump-memo-graph-with-timing
             With --dump-memo-graph, will re-run each cached node in the Memo
             graph after building and include the runtime in the output. Since
             all nodes contain a cached value, this will measure just the
             runtime of each node
  
         --help[=FMT] (default=auto)
             Show this help in format FMT. The value FMT must be one of auto,
             pager, groff or plain. With auto, the format is pager or plain
             whenever the TERM env var is dumb or undefined.
  
         --ignore-promoted-rules
             Ignore rules with (mode promote), except ones with (only ...). The
             variable %{ignoring_promoted_rules} in dune files reflects whether
             this option was passed or not.
  
         --instrument-with=BACKENDS (absent DUNE_INSTRUMENT_WITH env)
             "Enable instrumentation by BACKENDS. BACKENDS is a comma-separated
             list of library names, each one of which must declare an
             instrumentation backend.
  
         -j JOBS
             Run no more than JOBS commands simultaneously.
  
         --no-buffer
             Do not buffer the output of commands executed by dune. By default
             dune buffers the output of subcommands, in order to prevent
             interleaving when multiple commands are executed in parallel.
             However, this can be an issue when debugging long running tests.
             With --no-buffer, commands have direct access to the terminal.
             Note that as a result their output won't be captured in the log
             file. You should use this option in conjunction with -j 1, to
             avoid interleaving. Additionally you should use --verbose as well,
             to make sure that commands are printed before they are being
             executed.
  
         --no-config
             Do not load the configuration file
  
         --no-print-directory
             Suppress "Entering directory" messages
  
         --only-packages=PACKAGES
             Ignore stanzas referring to a package that is not in PACKAGES.
             PACKAGES is a comma-separated list of package names. Note that
             this has the same effect as deleting the relevant stanzas from
             dune files. It is mostly meant for releases. During development,
             it is likely that what you want instead is to build a particular
             <package>.install target.
  
         -p PACKAGES, --for-release-of-packages=PACKAGES (required)
             Shorthand for --release --only-packages PACKAGE. You must use this
             option in your <package>.opam files, in order to build only what's
             necessary when your project contains multiple packages as well as
             getting reproducible builds.
  
         --print-metrics
             Print out various performance metrics after every build
  
         --profile=VAL (absent DUNE_PROFILE env)
             Select the build profile, for instance dev or release. The default
             is dev.
  
         --promote-install-files[=VAL] (default=true)
             Promote the generated <package>.install files to the source tree
  
         --release
             Put dune into a reproducible release mode. This is in fact a
             shorthand for --root . --ignore-promoted-rules --no-config
             --profile release --always-show-command-line
             --promote-install-files --default-target @install
             --require-dune-project-file. You should use this option for
             release builds. For instance, you must use this option in your
             <package>.opam files. Except if you already use -p, as -p implies
             this option.
  
         --require-dune-project-file[=VAL] (default=true)
             Fail if a dune-project file is missing.
  
         --root=DIR
             Use this directory as workspace root instead of guessing it. Note
             that this option doesn't change the interpretation of targets
             given on the command line. It is only intended for scripts.
  
         --store-orig-source-dir (absent DUNE_STORE_ORIG_SOURCE_DIR env)
             Store original source location in dune-package metadata
  
         --terminal-persistence=MODE
             Changes how the log of build results are displayed to the console
             between rebuilds while in --watch mode. Supported modes: preserve,
             clear-on-rebuild, clear-on-rebuild-and-flush-history.
  
         --trace-file=FILE
             Output trace data in catapult format (compatible with
             chrome://tracing)
  
         --verbose
             Same as --display verbose
  
         --version
             Show version information.
  
         --workspace=FILE (absent DUNE_WORKSPACE env)
             Use this specific workspace file instead of looking it up.
  
         -x VAL
             Cross-compile using this toolchain.
  
  EXIT STATUS
         ping exits with the following status:
  
         0   on success.
  
         123 on indiscriminate errors reported on standard error.
  
         124 on command line parsing errors.
  
         125 on unexpected internal errors (bugs).
  
  ENVIRONMENT
         These environment variables affect the execution of ping:
  
         DUNE_BUILD_DIR
             Specified build directory. _build if unspecified
  
         DUNE_CACHE
             Enable or disable Dune cache (either enabled or disabled). Default
             is `disabled'.
  
         DUNE_CACHE_CHECK_PROBABILITY
             Check build reproducibility by re-executing randomly chosen rules
             and comparing their results with those stored in Dune cache. Note:
             by increasing the probability of such checks you slow down the
             build. The default probability is zero, i.e. no rules are checked.
  
         DUNE_CACHE_STORAGE_MODE
             Dune cache storage mode (one of auto, hardlink or copy). Default
             is `auto'.
  
         DUNE_DIFF_COMMAND
             Shell command to use to diff files. Use - to disable printing the
             diff.
  
         DUNE_DISABLE_PROMOTION
             Disable all promotion rules
  
         DUNE_INSTRUMENT_WITH
             "Enable instrumentation by BACKENDS. BACKENDS is a comma-separated
             list of library names, each one of which must declare an
             instrumentation backend.
  
         DUNE_PROFILE
             Build profile. dev if unspecified or release if -p is set.
  
         DUNE_SANDBOX
             Sandboxing mode to use by default. (see --sandbox)
  
         DUNE_STORE_ORIG_SOURCE_DIR
             Store original source location in dune-package metadata
  
         DUNE_WORKSPACE
             Use this specific workspace file instead of looking it up.
  
  SEE ALSO
         dune(1)
  
  $ dune rpc status --help=plain
  NAME
         dune-rpc-status - Show active RPC connections.
  
  SYNOPSIS
         dune rpc status [OPTION]…
  
  OPTIONS
         --action-stderr-on-success=VAL
             Same as --action-stdout-on-success but for the standard output for
             error messages. A good default for large mono-repositories is
             --action-stdout-on-success=swallow
             --action-stderr-on-success=must-be-empty. This ensures that a
             successful build has a "clean" empty output.
  
         --action-stdout-on-success=VAL
             Specify how to deal with the standard output of actions when they
             succeed. Possible values are: print to just print it to Dune's
             output, swallow to completely ignore it and must-be-empty to
             enforce that the action printed nothing. With must-be-empty, Dune
             will consider that the action failed if it printed something to
             its standard output. The default is print.
  
         --build-info
             Show build information.
  
         --error-reporting=VAL (absent=deterministic)
             Controls when the build errors are reported. early - report errors
             as soon as they are discovered. deterministic - report errors at
             the end of the build in a deterministic order. twice - report each
             error twice: once as soon as the error is discovered and then
             again at the end of the build, in a deterministic order.
  
         -f, --force
             Force actions associated to aliases to be re-executed even if
             their dependencies haven't changed.
  
         --file-watcher=VAL (absent=automatic)
             Mechanism to detect changes in the source. Automatic to make dune
             run an external program to detect changes. Manual to notify dune
             that files have changed manually."
  
         --passive-watch-mode
             Similar to [--watch], but only start a build when instructed
             externally by an RPC.
  
         --react-to-insignificant-changes
             react to insignificant file system changes; this is only useful
             for benchmarking dune
  
         --sandbox=VAL (absent DUNE_SANDBOX env)
             Sandboxing mode to use by default. Some actions require a certain
             sandboxing mode, so they will ignore this setting. The allowed
             values are: none, symlink, copy, hardlink.
  
         -w, --watch
             Instead of terminating build after completion, wait continuously
             for file changes.
  
         --wait-for-filesystem-clock
             Dune digest file contents for better incrementally. These digests
             are themselves cached. In some cases, Dune needs to drop some
             digest cache entries in order for things to be reliable. This
             option makes Dune wait for the file system clock to advance so
             that it doesn't need to drop anything. You should probably not
             care about this option; it is mostly useful for Dune developers to
             make Dune tests of the digest cache more reproducible.
  
  COMMON OPTIONS
         --always-show-command-line
             Always show the full command lines of programs executed by dune
  
         --auto-promote
             Automatically promote files. This is similar to running dune
             promote after the build.
  
         --build-dir=FILE (absent DUNE_BUILD_DIR env)
             Specified build directory. _build if unspecified
  
         --cache=VAL (absent DUNE_CACHE env)
             Enable or disable Dune cache (either enabled or disabled). Default
             is `disabled'.
  
         --cache-check-probability=VAL (absent DUNE_CACHE_CHECK_PROBABILITY
         env)
             Check build reproducibility by re-executing randomly chosen rules
             and comparing their results with those stored in Dune cache. Note:
             by increasing the probability of such checks you slow down the
             build. The default probability is zero, i.e. no rules are checked.
  
         --cache-storage-mode=VAL (absent DUNE_CACHE_STORAGE_MODE env)
             Dune cache storage mode (one of auto, hardlink or copy). Default
             is `auto'.
  
         --config-file=FILE
             Load this configuration file instead of the default one.
  
         --debug-artifact-substitution
             Print debugging info about artifact substitution
  
         --debug-backtraces
             Always print exception backtraces.
  
         --debug-cache=VAL
             Show debug messages on cache misses for the given cache layers.
             Value is a comma-separated list of cache layer names. All
             available cache layers: shared,workspace-local,fs.
  
         --debug-dependency-path
             In case of error, print the dependency path from the targets on
             the command line to the rule that failed. 
  
         --debug-digests
             Explain why Dune decides to re-digest some files
  
         --debug-findlib
             Debug the findlib sub-system.
  
         --debug-load-dir
             Print debugging info about directory loading
  
         --debug-store-digest-preimage
             Store digest preimage for all computed digests, so that it's
             possible to reverse them later, for debugging. The digests are
             stored in the shared cache (see --cache flag) as values, even if
             cache is otherwise disabled. This should be used only for
             debugging, since it's slow and it litters the shared cache.
  
         --default-target=TARGET (absent=@@default)
             Set the default target that when none is specified to dune build.
  
         --diff-command=VAL (absent DUNE_DIFF_COMMAND env)
             Shell command to use to diff files. Use - to disable printing the
             diff.
  
         --disable-promotion (absent DUNE_DISABLE_PROMOTION env)
             Disable all promotion rules
  
         --display=MODE
             Control the display mode of Dune. See dune-config(5) for more
             details.
  
         --dump-memo-graph=FILE
             Dumps the dependency graph to a file after the build is complete
  
         --dump-memo-graph-format=FORMAT (absent=gexf)
             File format to be used when dumping dependency graph
  
         --dump-memo-graph-with-timing
             With --dump-memo-graph, will re-run each cached node in the Memo
             graph after building and include the runtime in the output. Since
             all nodes contain a cached value, this will measure just the
             runtime of each node
  
         --help[=FMT] (default=auto)
             Show this help in format FMT. The value FMT must be one of auto,
             pager, groff or plain. With auto, the format is pager or plain
             whenever the TERM env var is dumb or undefined.
  
         --ignore-promoted-rules
             Ignore rules with (mode promote), except ones with (only ...). The
             variable %{ignoring_promoted_rules} in dune files reflects whether
             this option was passed or not.
  
         --instrument-with=BACKENDS (absent DUNE_INSTRUMENT_WITH env)
             "Enable instrumentation by BACKENDS. BACKENDS is a comma-separated
             list of library names, each one of which must declare an
             instrumentation backend.
  
         -j JOBS
             Run no more than JOBS commands simultaneously.
  
         --no-buffer
             Do not buffer the output of commands executed by dune. By default
             dune buffers the output of subcommands, in order to prevent
             interleaving when multiple commands are executed in parallel.
             However, this can be an issue when debugging long running tests.
             With --no-buffer, commands have direct access to the terminal.
             Note that as a result their output won't be captured in the log
             file. You should use this option in conjunction with -j 1, to
             avoid interleaving. Additionally you should use --verbose as well,
             to make sure that commands are printed before they are being
             executed.
  
         --no-config
             Do not load the configuration file
  
         --no-print-directory
             Suppress "Entering directory" messages
  
         --only-packages=PACKAGES
             Ignore stanzas referring to a package that is not in PACKAGES.
             PACKAGES is a comma-separated list of package names. Note that
             this has the same effect as deleting the relevant stanzas from
             dune files. It is mostly meant for releases. During development,
             it is likely that what you want instead is to build a particular
             <package>.install target.
  
         -p PACKAGES, --for-release-of-packages=PACKAGES (required)
             Shorthand for --release --only-packages PACKAGE. You must use this
             option in your <package>.opam files, in order to build only what's
             necessary when your project contains multiple packages as well as
             getting reproducible builds.
  
         --print-metrics
             Print out various performance metrics after every build
  
         --profile=VAL (absent DUNE_PROFILE env)
             Select the build profile, for instance dev or release. The default
             is dev.
  
         --promote-install-files[=VAL] (default=true)
             Promote the generated <package>.install files to the source tree
  
         --release
             Put dune into a reproducible release mode. This is in fact a
             shorthand for --root . --ignore-promoted-rules --no-config
             --profile release --always-show-command-line
             --promote-install-files --default-target @install
             --require-dune-project-file. You should use this option for
             release builds. For instance, you must use this option in your
             <package>.opam files. Except if you already use -p, as -p implies
             this option.
  
         --require-dune-project-file[=VAL] (default=true)
             Fail if a dune-project file is missing.
  
         --root=DIR
             Use this directory as workspace root instead of guessing it. Note
             that this option doesn't change the interpretation of targets
             given on the command line. It is only intended for scripts.
  
         --store-orig-source-dir (absent DUNE_STORE_ORIG_SOURCE_DIR env)
             Store original source location in dune-package metadata
  
         --terminal-persistence=MODE
             Changes how the log of build results are displayed to the console
             between rebuilds while in --watch mode. Supported modes: preserve,
             clear-on-rebuild, clear-on-rebuild-and-flush-history.
  
         --trace-file=FILE
             Output trace data in catapult format (compatible with
             chrome://tracing)
  
         --verbose
             Same as --display verbose
  
         --version
             Show version information.
  
         --workspace=FILE (absent DUNE_WORKSPACE env)
             Use this specific workspace file instead of looking it up.
  
         -x VAL
             Cross-compile using this toolchain.
  
  EXIT STATUS
         status exits with the following status:
  
         0   on success.
  
         123 on indiscriminate errors reported on standard error.
  
         124 on command line parsing errors.
  
         125 on unexpected internal errors (bugs).
  
  ENVIRONMENT
         These environment variables affect the execution of status:
  
         DUNE_BUILD_DIR
             Specified build directory. _build if unspecified
  
         DUNE_CACHE
             Enable or disable Dune cache (either enabled or disabled). Default
             is `disabled'.
  
         DUNE_CACHE_CHECK_PROBABILITY
             Check build reproducibility by re-executing randomly chosen rules
             and comparing their results with those stored in Dune cache. Note:
             by increasing the probability of such checks you slow down the
             build. The default probability is zero, i.e. no rules are checked.
  
         DUNE_CACHE_STORAGE_MODE
             Dune cache storage mode (one of auto, hardlink or copy). Default
             is `auto'.
  
         DUNE_DIFF_COMMAND
             Shell command to use to diff files. Use - to disable printing the
             diff.
  
         DUNE_DISABLE_PROMOTION
             Disable all promotion rules
  
         DUNE_INSTRUMENT_WITH
             "Enable instrumentation by BACKENDS. BACKENDS is a comma-separated
             list of library names, each one of which must declare an
             instrumentation backend.
  
         DUNE_PROFILE
             Build profile. dev if unspecified or release if -p is set.
  
         DUNE_SANDBOX
             Sandboxing mode to use by default. (see --sandbox)
  
         DUNE_STORE_ORIG_SOURCE_DIR
             Store original source location in dune-package metadata
  
         DUNE_WORKSPACE
             Use this specific workspace file instead of looking it up.
  
  SEE ALSO
         dune(1)
  

  $ dune rpc build --help=plain
  NAME
         dune-rpc-build - Build a given target. (Requires Dune to be running in
         passive watching mode).
  
  SYNOPSIS
         dune rpc build [OPTION]… [TARGET]…
  
  OPTIONS
         --action-stderr-on-success=VAL
             Same as --action-stdout-on-success but for the standard output for
             error messages. A good default for large mono-repositories is
             --action-stdout-on-success=swallow
             --action-stderr-on-success=must-be-empty. This ensures that a
             successful build has a "clean" empty output.
  
         --action-stdout-on-success=VAL
             Specify how to deal with the standard output of actions when they
             succeed. Possible values are: print to just print it to Dune's
             output, swallow to completely ignore it and must-be-empty to
             enforce that the action printed nothing. With must-be-empty, Dune
             will consider that the action failed if it printed something to
             its standard output. The default is print.
  
         --build-info
             Show build information.
  
         --error-reporting=VAL (absent=deterministic)
             Controls when the build errors are reported. early - report errors
             as soon as they are discovered. deterministic - report errors at
             the end of the build in a deterministic order. twice - report each
             error twice: once as soon as the error is discovered and then
             again at the end of the build, in a deterministic order.
  
         -f, --force
             Force actions associated to aliases to be re-executed even if
             their dependencies haven't changed.
  
         --file-watcher=VAL (absent=automatic)
             Mechanism to detect changes in the source. Automatic to make dune
             run an external program to detect changes. Manual to notify dune
             that files have changed manually."
  
         --passive-watch-mode
             Similar to [--watch], but only start a build when instructed
             externally by an RPC.
  
         --react-to-insignificant-changes
             react to insignificant file system changes; this is only useful
             for benchmarking dune
  
         --sandbox=VAL (absent DUNE_SANDBOX env)
             Sandboxing mode to use by default. Some actions require a certain
             sandboxing mode, so they will ignore this setting. The allowed
             values are: none, symlink, copy, hardlink.
  
         -w, --watch
             Instead of terminating build after completion, wait continuously
             for file changes.
  
         --wait
             Poll until server starts listening and then establish connection.
  
         --wait-for-filesystem-clock
             Dune digest file contents for better incrementally. These digests
             are themselves cached. In some cases, Dune needs to drop some
             digest cache entries in order for things to be reliable. This
             option makes Dune wait for the file system clock to advance so
             that it doesn't need to drop anything. You should probably not
             care about this option; it is mostly useful for Dune developers to
             make Dune tests of the digest cache more reproducible.
  
  COMMON OPTIONS
         --always-show-command-line
             Always show the full command lines of programs executed by dune
  
         --auto-promote
             Automatically promote files. This is similar to running dune
             promote after the build.
  
         --build-dir=FILE (absent DUNE_BUILD_DIR env)
             Specified build directory. _build if unspecified
  
         --cache=VAL (absent DUNE_CACHE env)
             Enable or disable Dune cache (either enabled or disabled). Default
             is `disabled'.
  
         --cache-check-probability=VAL (absent DUNE_CACHE_CHECK_PROBABILITY
         env)
             Check build reproducibility by re-executing randomly chosen rules
             and comparing their results with those stored in Dune cache. Note:
             by increasing the probability of such checks you slow down the
             build. The default probability is zero, i.e. no rules are checked.
  
         --cache-storage-mode=VAL (absent DUNE_CACHE_STORAGE_MODE env)
             Dune cache storage mode (one of auto, hardlink or copy). Default
             is `auto'.
  
         --config-file=FILE
             Load this configuration file instead of the default one.
  
         --debug-artifact-substitution
             Print debugging info about artifact substitution
  
         --debug-backtraces
             Always print exception backtraces.
  
         --debug-cache=VAL
             Show debug messages on cache misses for the given cache layers.
             Value is a comma-separated list of cache layer names. All
             available cache layers: shared,workspace-local,fs.
  
         --debug-dependency-path
             In case of error, print the dependency path from the targets on
             the command line to the rule that failed. 
  
         --debug-digests
             Explain why Dune decides to re-digest some files
  
         --debug-findlib
             Debug the findlib sub-system.
  
         --debug-load-dir
             Print debugging info about directory loading
  
         --debug-store-digest-preimage
             Store digest preimage for all computed digests, so that it's
             possible to reverse them later, for debugging. The digests are
             stored in the shared cache (see --cache flag) as values, even if
             cache is otherwise disabled. This should be used only for
             debugging, since it's slow and it litters the shared cache.
  
         --default-target=TARGET (absent=@@default)
             Set the default target that when none is specified to dune build.
  
         --diff-command=VAL (absent DUNE_DIFF_COMMAND env)
             Shell command to use to diff files. Use - to disable printing the
             diff.
  
         --disable-promotion (absent DUNE_DISABLE_PROMOTION env)
             Disable all promotion rules
  
         --display=MODE
             Control the display mode of Dune. See dune-config(5) for more
             details.
  
         --dump-memo-graph=FILE
             Dumps the dependency graph to a file after the build is complete
  
         --dump-memo-graph-format=FORMAT (absent=gexf)
             File format to be used when dumping dependency graph
  
         --dump-memo-graph-with-timing
             With --dump-memo-graph, will re-run each cached node in the Memo
             graph after building and include the runtime in the output. Since
             all nodes contain a cached value, this will measure just the
             runtime of each node
  
         --help[=FMT] (default=auto)
             Show this help in format FMT. The value FMT must be one of auto,
             pager, groff or plain. With auto, the format is pager or plain
             whenever the TERM env var is dumb or undefined.
  
         --ignore-promoted-rules
             Ignore rules with (mode promote), except ones with (only ...). The
             variable %{ignoring_promoted_rules} in dune files reflects whether
             this option was passed or not.
  
         --instrument-with=BACKENDS (absent DUNE_INSTRUMENT_WITH env)
             "Enable instrumentation by BACKENDS. BACKENDS is a comma-separated
             list of library names, each one of which must declare an
             instrumentation backend.
  
         -j JOBS
             Run no more than JOBS commands simultaneously.
  
         --no-buffer
             Do not buffer the output of commands executed by dune. By default
             dune buffers the output of subcommands, in order to prevent
             interleaving when multiple commands are executed in parallel.
             However, this can be an issue when debugging long running tests.
             With --no-buffer, commands have direct access to the terminal.
             Note that as a result their output won't be captured in the log
             file. You should use this option in conjunction with -j 1, to
             avoid interleaving. Additionally you should use --verbose as well,
             to make sure that commands are printed before they are being
             executed.
  
         --no-config
             Do not load the configuration file
  
         --no-print-directory
             Suppress "Entering directory" messages
  
         --only-packages=PACKAGES
             Ignore stanzas referring to a package that is not in PACKAGES.
             PACKAGES is a comma-separated list of package names. Note that
             this has the same effect as deleting the relevant stanzas from
             dune files. It is mostly meant for releases. During development,
             it is likely that what you want instead is to build a particular
             <package>.install target.
  
         -p PACKAGES, --for-release-of-packages=PACKAGES (required)
             Shorthand for --release --only-packages PACKAGE. You must use this
             option in your <package>.opam files, in order to build only what's
             necessary when your project contains multiple packages as well as
             getting reproducible builds.
  
         --print-metrics
             Print out various performance metrics after every build
  
         --profile=VAL (absent DUNE_PROFILE env)
             Select the build profile, for instance dev or release. The default
             is dev.
  
         --promote-install-files[=VAL] (default=true)
             Promote the generated <package>.install files to the source tree
  
         --release
             Put dune into a reproducible release mode. This is in fact a
             shorthand for --root . --ignore-promoted-rules --no-config
             --profile release --always-show-command-line
             --promote-install-files --default-target @install
             --require-dune-project-file. You should use this option for
             release builds. For instance, you must use this option in your
             <package>.opam files. Except if you already use -p, as -p implies
             this option.
  
         --require-dune-project-file[=VAL] (default=true)
             Fail if a dune-project file is missing.
  
         --root=DIR
             Use this directory as workspace root instead of guessing it. Note
             that this option doesn't change the interpretation of targets
             given on the command line. It is only intended for scripts.
  
         --store-orig-source-dir (absent DUNE_STORE_ORIG_SOURCE_DIR env)
             Store original source location in dune-package metadata
  
         --terminal-persistence=MODE
             Changes how the log of build results are displayed to the console
             between rebuilds while in --watch mode. Supported modes: preserve,
             clear-on-rebuild, clear-on-rebuild-and-flush-history.
  
         --trace-file=FILE
             Output trace data in catapult format (compatible with
             chrome://tracing)
  
         --verbose
             Same as --display verbose
  
         --version
             Show version information.
  
         --workspace=FILE (absent DUNE_WORKSPACE env)
             Use this specific workspace file instead of looking it up.
  
         -x VAL
             Cross-compile using this toolchain.
  
  EXIT STATUS
         build exits with the following status:
  
         0   on success.
  
         123 on indiscriminate errors reported on standard error.
  
         124 on command line parsing errors.
  
         125 on unexpected internal errors (bugs).
  
  ENVIRONMENT
         These environment variables affect the execution of build:
  
         DUNE_BUILD_DIR
             Specified build directory. _build if unspecified
  
         DUNE_CACHE
             Enable or disable Dune cache (either enabled or disabled). Default
             is `disabled'.
  
         DUNE_CACHE_CHECK_PROBABILITY
             Check build reproducibility by re-executing randomly chosen rules
             and comparing their results with those stored in Dune cache. Note:
             by increasing the probability of such checks you slow down the
             build. The default probability is zero, i.e. no rules are checked.
  
         DUNE_CACHE_STORAGE_MODE
             Dune cache storage mode (one of auto, hardlink or copy). Default
             is `auto'.
  
         DUNE_DIFF_COMMAND
             Shell command to use to diff files. Use - to disable printing the
             diff.
  
         DUNE_DISABLE_PROMOTION
             Disable all promotion rules
  
         DUNE_INSTRUMENT_WITH
             "Enable instrumentation by BACKENDS. BACKENDS is a comma-separated
             list of library names, each one of which must declare an
             instrumentation backend.
  
         DUNE_PROFILE
             Build profile. dev if unspecified or release if -p is set.
  
         DUNE_SANDBOX
             Sandboxing mode to use by default. (see --sandbox)
  
         DUNE_STORE_ORIG_SOURCE_DIR
             Store original source location in dune-package metadata
  
         DUNE_WORKSPACE
             Use this specific workspace file instead of looking it up.
  
  SEE ALSO
         dune(1)
  
