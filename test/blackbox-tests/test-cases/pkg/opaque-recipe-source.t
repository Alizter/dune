An opaque recipe starts from the package's source with the lock directory's
files and the extra sources laid over it; an extra source wins over a lock
directory file at the same path. Patches are not applied beforehand; the recipe
applies them itself.

  $ make_lockdir
  $ mkdir _source _extra
  $ echo 'source' > _source/both
  $ echo 'source' > _source/patched
  $ echo 'extra' > _extra/both
  $ make_lockpkg foo <<EOF
  > (version 1.0)
  > (source (copy $PWD/_source))
  > (extra_sources
  >  (both (copy $PWD/_extra/both)))
  > (build
  >  (progn
  >   (run sh -c "for f in both patched; do echo \$f: \$(cat \$f); done")
  >   (patch change.patch)
  >   (run sh -c "echo after the patch: \$(cat patched)")))
  > EOF
  $ make_lockpkg_file foo both <<'EOF'
  > lock
  > EOF
  $ make_lockpkg_file foo change.patch <<'EOF'
  > --- a/patched
  > +++ b/patched
  > @@ -1 +1 @@
  > -source
  > +patched
  > EOF

  $ build_pkg foo
  both: extra
  patched: source
  after the patch: patched

The inputs are not modified.

  $ cat _source/patched _source/both _extra/both
  source
  source
  extra
