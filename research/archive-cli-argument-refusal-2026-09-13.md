# Archive CLI argument refusal — AF-729

During the AF-748 drain, four valid archival decisions used the wrong CLI flag, `--outcome-stdin`. The archive parser recognized only `--authorized-by` and `--archive-outcome`; its fallback `break` discarded the remaining argv and sent PATCH archived=true anyway. All four commands returned success without recording the supplied reason. This is separate from AF-729's already-landed API outcome/coercion correction.

The archive/unarchive parser now consumes all arguments or refuses before PATCH. Unsupported flags, trailing positional text, empty/missing/flag-shaped values, and archive outcomes on unarchive exit 2 with a precise supported-flag hint. Valid archive flags remain order independent and plain unarchive remains available. No new stdin alias is added.

Refusal posts `cli-argument-refused` to the existing client-debug surface, bounded by 1s connect / 2s total timeout. The payload contains the operation, validated card ID, fixed reason, measured:true and n_considered:1. It excludes argument values and outcome text. Diagnostic transport failure cannot turn refusal into success or permit a board PATCH. stderr also states no board change was sent.

Verification:

- Expanded real Bash CLI/mock HTTP regression on parent9ec1e58f: 13 assertions passed, 46 failed. It demonstrates successful PATCHes despite invalid argv, and missing refusal diagnostics.
- Corrected `bash scripts/test-board-archive-outcome.sh`: 66 passed, 0 failed. Five valid command controls, eleven rejection cases, zero PATCH checks, exact exit2, diagnostic target, private-sentinel exclusion and unavailable-diagnostic transport covered. The fixture isolates CC_HOME and tmux and cleans its temporary files.
- `bash scripts/test-cli-offset-safe.sh`: PASS, wrapper and terminal exit/brace intact.
- `bash -n amux`: exit0.
- Candidate CLI against the real live diagnostic endpoint, invalid archive of AMUX-4013: exit2; card rev6 and archived state unchanged; GET /api/client-debug?kind=cli-argument-refused matched1 with exact item/operation/reason and measuredtrue/n1. Private stdin sentinel absent. Stable server9ec1e58f/build08c498987f19983b. This tested the candidate script, not an installed-client update.
- Four earlier archive operations were corrected using supported unarchive then archive --archive-outcome. Exact supplied reasons are now in the attributed card logs; original descriptions and evidence are unchanged. No PR/issue was closed.

Raw evidence: scratch/af748-board-drain/resumed-verification/archive-argv-red.log, test-board-archive-outcome-final.log, test-cli-offset-safe-final.log and archive-argv-live-diagnostic.json. Prior API correction and this CLI correction require separate scope-aware review. Full browser CI remains red; no full release/Verified claim.
