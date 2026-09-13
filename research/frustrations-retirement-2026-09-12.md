# Frustrations retirement review — AF-746

This batch retires 15 objectively resolved findings by their originating worker,
`amux-frustrations`. The committed ledger had 133 entries; 118 remain. This is a
review of the retirement decisions, not completion of the full ledger or board drain.
Every retired entry retains its original text in `frustrations-archive.md`, an actual
verifier and command/result evidence. The linked cards retain each symptom and cost.

## Retired findings

| Card | Entries | Proof of the scoped fix |
| --- | ---: | --- |
| AF-754 | 3 | Primary button contrast in both themes, native Safari select height, and dialog/confirmation paint order. Browser positive controls deliberately break contrast, height and confirmation layers. Actual live iOS guide accepts native input, scrolls away from bottom and closes above the keyboard. |
| AF-732 | 6 | Native input changes the intended page; keyboard dismissal precedes page taps; explicit Go recovers proven expired sessions without replay; hidden tabs refuse input; requested URL metadata precedes stale contexts; twelve repeated Go calls preserve the tab list. |
| AF-749 | 6 | Long dialogs keep Close reachable; connection/journal/team surfaces follow the theme; video Close stays outside fading playback controls; proxy forms activate; calendar status reads are bounded with immediate Close; scope cancellation preserves drafts through the shared confirmation. |

The archive names the individual tests and cases for each entry. Card status was
not used as proof. No card was moved to Verified by this batch: the group gate
requires a different amux worker to verify the work independently.

## Evidence

- Clean final UI commit `9b186f85ce809cde2bbf96ddc9c3d683b7d6d6a8`:
  guide/modal/header Playwright matrix **33 passed (1.0m)**; state suite **27 passed,
  0 failed**; SPA lint **0 errors, 48 existing warnings**; workspace/all-target
  Clippy **exit 0**. Scripts and exact commands are retained in
  `scratch/ios-simulator-review/ui-guide-evidence.txt`.
- Native Simulator recovery at `ff8077072508`, build `2d3d72ebb67df78b`:
  **5 passed**; focused adapter tests **10 passed, 0 failed**. The adapter source
  is unchanged in the final UI commit. Logs retain `native_tab_reused`,
  `hidden_native_tab`, `expired_session_released` and keyboard refusal/recovery.
- Native modal inventory on app `0.9.931`: **54 considered, 53 initial passes**,
  with one retained calendar calibration failure and a separate passing calendar
  correction. The upgrade case covers presentation/navigation only. This is not
  an all-destructive-submit test or a 54-case claim for app `0.9.933`.
- Current app `0.9.933`: three native candidate cases passed; one additional native
  case on the actual live origin passed. The latter used no preview proxy or
  version-reload suppression. Fourteen shared controls had no measured issues;
  native scroll escaped the bottom, input changed and Close dismissed the guide.
- Live source `9b186f85ce80`, build `d31572e4a42df479`: **5/5 served assets match**
  the clean snapshot, with the same build before and after the native live case.
  Native and browser screenshots were opened and inspected, including limited
  workers, journal configuration, persistent video Close and the live keyboard view.
- `python3 scratch/ios-simulator-review/retire-af746/verify-moves.py`:
  **PASS, 15 considered; all original entry text preserved; all other entries
  unchanged; symptom/cost read back on AF-732, AF-749 and AF-754**.
- `python3 scripts/frustrations_audit.py`: **118 entries, no structural errors**.
  Existing card-title mismatches remain informational and are not evidence that a
  similarly numbered card owns an old finding.

Detailed local receipts are in `scratch/ios-simulator-review/retire-af746/`.
Screenshots remain outside public source because they can contain workspace data.
The earlier missing-journal native invocation and unpinned header-preference test
failure remain in their logs; corrected results do not erase failed specimens.

## Remaining work and review request

Review the 15 archive moves against their named evidence and check that no claim
was retired at a broader scope than its test. In particular, preserve the distinction
between a working native gesture, a committed server command, and a complete lifecycle.

The remaining 118 entries have not all been reverified. They stay in the live ledger.
The next bounded candidates are:

1. **AMUX-2644:** dead tmux panes still appearing running. The current pure predicate
   test passed; the recent live inventory had 52 sessions and no all-dead specimen.
   Use the actual pane/session target mapping and an isolated positive specimen
   before treating an empty live population as proof. Its historical builder-down
   note is stale; that alone does not establish the positive case.
2. **AMUX-3772 / AMUX-3849:** misleading latency attribution and autofix duplicate
   refiling. Inspect current fault identity, open-card suppression and discard/fold
   behavior; the ledger describes mechanisms, not interchangeable duplicate titles.
3. **Remaining own mobile/CLI findings:** reconcile exact current implementations,
   test artifacts and live identity one entry at a time. Several cards still have
   obsolete deployment notes; update those notes without inventing peer verification.
4. **Older cross-worker findings:** confirm the linked card actually matches the
   entry before acting. Apply AF-352's evidence-based retirement permission only to
   objective claims; subjective author decisions remain separate.

AF-747 and AF-748 track the separate scoped worker-board drains. This report does
not certify those boards, close unresolved entries, or assert that all UI components
and all lifecycle behavior are consistent.
