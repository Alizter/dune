# @unused dead code analyser — TODO

## Architecture

Binary (`dune-index-dump`) faithfully dumps all UIDs with all per-lid locations.
Shared `dune_index_format` lib provides types + encoder/decoder using `Loc.t`.
Dune rules (`dead_code_rules.ml`) do all analysis: cross-cctx merging via
reverse deps, own-module filtering, visibility filtering, unused detection.

Solution is architecturally correct. Cross-cctx merge via reverse deps properly
detects workspace-wide usage. Known performance concern (N+1 binary invocations
per stanza) but not incorrect.

## Open Issues

### Constructor/field handling
Constructors and record fields have [intf] UIDs but no `related_uids` entry
(`impl_id = None`, `related_group_size = 0`). Current code treats `None` as
"unused" → false positives for used constructors/fields (Red, x, y).

Options:
1. `None -> false`: skip without impl_id. Loses detection of genuinely unused
   constructors (Green, Blue, Foo, Bar) but parent type still reported if unused.
2. Fall back to same-id lookup: when impl_id is None, use e.id directly.
   For constructors/fields, intf and impl UIDs share the same id. Correctly
   detects Red as used and Green as unused. Need to verify this id-sharing
   property is guaranteed by the compiler.
3. Only report at type level, skip individual constructors/fields entirely.

`unused-type-exports.t` currently fails due to this. Needs decision and fix.

### Location resolution
`defining_loc` picks first .mli from locs list. For own-module [intf] UIDs
this works because they only have locations in their own .mli (confirmed
empirically — could not reproduce a case where own-module [intf] UIDs have
locations in multiple .mli files). Dependency [intf] UIDs are filtered out
by `is_own_module` before location is needed. May still be worth using
comp_unit → module → source path mapping from Modules.t for robustness.

### Other
- [ ] Diamond deps test: single-module private libs produce silent output
- [ ] Unwrapped libraries: skipped entirely, may want partial analysis
- [ ] Virtual libraries: skipped entirely
- [ ] Performance: N+1 binary invocations per stanza via reverse deps
