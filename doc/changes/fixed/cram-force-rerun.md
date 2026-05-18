- Restore the pre-3.21 behaviour of `dune runtest --force` for cram tests:
  passing `--force` now re-executes the cram script. This regressed in #11994
  when the cram rules were split into a chain of file-target rules; the
  script generation and run rules then became non-alias-attached and ignored
  `--force`. The fix converts them back into a chain of alias-attached
  anonymous actions, communicating via stdout, while preserving the
  no-re-run-after-promote behaviour from #11994. (@Alizter)
