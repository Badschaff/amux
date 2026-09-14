# Ledger author and board mapping — AF-781

Owner AF-780 requires every active frustration to have a concrete issue on this
board, with originating-session agreement before Verified and retirement.

The published baseline had 141 entries, while the shared root draft held an old
84-entry population. Comparing both with the archive found no novel root-only
unarchived entry and three entries already archived. The shared root was untouched.
The additional structured-intake defect found during this work is entry 142,
AF-785, fixed and published at e7370c38 with live build 2812c9b6f3a9e09e.

103 specific issues were created, and 38 baseline entries retained relevant
existing issues (31 distinct cards). Historical card IDs are not globally reliable:
one reused historical ID covered 37 different entries. Repaired pointers retain
ORIGINAL_CARD; SESSION and all original symptom, cost, fix, date and status text
remain byte-for-byte unchanged. No entry was retired, and the archive is unchanged.

Author labels already existed for all 142 entries. Ambiguous historical labels
remain explicit, with publication provenance where available. A commit author is
not proof of the originating session. Current worker availability likewise does
not establish identity continuity. Original agreement is checked per exact entry;
existing real agreement can count, while a fixed label or card status cannot.

Validation artifacts: scratch/frustrations-validation-evidence/final-ledger-mapping.json,
mapping-preservation.json, created-cards.json, existing-link-readbacks.json,
and exact per-card HTTP readbacks under cards/. Each newly created issue retained
its full original entry, ownership and actionable criteria; persisted fields were
compared after creation and metadata patch. Reused cards retain previous evidence,
artifacts and owners. Discarded records needed by this new explicit request were
reactivated to backlog, without claiming their fixes are verified. Existing human
blockers and Done evidence remain in place for individual review.

Canonical `python3 scripts/frustrations_audit.py` exited 0 on the mapped file.
It retains advisory title-mismatch checks for broad existing issues and notes five
IDs shared by related entries; those IDs are not deletion keys. Exact entry titles
and original text are retained in each card and the mapping table.

This is mapping and policy work, not completion of the 142 fixes or their
verification gates. Full AF-780 remains open.

| Entry | Current issue | Originating SESSION (preserved) | Previous CARD |
| --- | --- | --- | --- |
| 1 | AF-782 | (agent, AMUX-2629) | AMUX-2629 |
| 2 | AF-783 | board-drive (AMUX-2637) | AMUX-2637 |
| 3 | AF-784 | amux (cloud rust image, AMUX-2619) | AMUX-2644 |
| 4 | AF-786 | rust-rebuild (RR-0109/0110 lane) | ARE-10 |
| 5 | AF-787 | (Claude Code in iTerm — not a fleet lane, hence no session stamp) | AMUX-2663 |
| 6 | AF-788 | amux-rust (AMUX-2647 lane) | AMUX-2647 |
| 7 | AF-789 | autofix (subagent) | AF-69 (investigation, signed off) + AMUX-3221 (the FIX, open) |
| 8 | AF-790 | storage-audit | AMUX-2701 |
| 9 | AF-791 | claude (AMUX-2619/2780 lane) | AMUX-2799 |
| 10 | AF-792 | amux | AMUX-2841 |
| 11 | AF-793 | amux | AMUX-3119 |
| 12 | AF-794 | amux (file-manager subagent) | AMUX-3249 |
| 13 | AF-795 | desktop | DESKT-10 |
| 14 | AF-654 | amux-errors-and-bugs | AEAB-11 |
| 15 | AF-656 | amux-errors-and-bugs | AEAB-28 |
| 16 | AF-657 | amux-errors-and-bugs | AEAB-36 |
| 17 | AF-658 | amux-errors-and-bugs | AEAB-40 |
| 18 | AF-796 | amux | AMUX-1315 |
| 19 | AF-659 | amux-errors-and-bugs | AEAB-47 |
| 20 | AF-797 | desktop | DESKT-21 |
| 21 | AF-798 | desktop | DESKT-22 |
| 22 | AF-799 | desktop | DESKT-22 |
| 23 | AF-183 | amux-frustrations | AF-183 |
| 24 | AF-800 | amux | AF-182 |
| 25 | AF-664 | amux-errors-and-bugs | AEAB-43 |
| 26 | AF-801 | amux (hit it, twice), amux-frustrations (verified the mechanism) | AF-214 (nudge skip, done) / AMUX-3668 (the `changes-requested` status, open) |
| 27 | AF-802 | 6527367a-8ff6-431a-ace9-e421554fb30d | none |
| 28 | AF-668 | amux | AMUX-48 |
| 29 | AF-669 | amux | AMUX-48 |
| 30 | AF-803 | amux | AMUX-3772 |
| 31 | AF-804 | amux | AMUX-3849 |
| 32 | AF-805 | amux | AF-342 |
| 33 | AF-336 | amux-frustrations | AF-336 |
| 34 | AF-806 | amux-frustrations | AMUX-3954 |
| 35 | AF-336 | amux-frustrations | AF-336 |
| 36 | AF-670 | amux | AMUX-99 |
| 37 | AF-807 | amux-testing-e2e | ATE-10 |
| 38 | AF-445 | amux-frustrations | AF-445 |
| 39 | AF-808 | amux | AMUX-4083 |
| 40 | AF-458 | amux-frustrations | AF-458 |
| 41 | AF-460 | gtm-engine | AF-460 |
| 42 | AF-809 | amux | AMUX-4142 |
| 43 | AF-810 | amux-codex | AC-416 |
| 44 | AF-811 | amux-codex | AC-416 |
| 45 | AF-812 | amux (Codex agent; no $AMUX_SESSION in env) | AMUX-3249 |
| 46 | AF-813 | mixpeek-ops-server | MOS-33 |
| 47 | AF-814 | amux | AMUX-4203 |
| 48 | AF-815 | amux | AMUX-4203 |
| 49 | AF-816 | amux | AMUX-4203 |
| 50 | AF-817 | amux | AMUX-4225 |
| 51 | AF-818 | mvs-research | MR-174 |
| 52 | AF-819 | amux-testing-e2e | ATE-128 |
| 53 | AF-820 | amux-testing-e2e | ATE-130 |
| 54 | AF-821 | amux-testing-e2e | AF-640 |
| 55 | AF-822 | codex-amux-lifecycle | AMUX-4362 |
| 56 | AF-823 | codex-server-sync | AMUX-4416 |
| 57 | AF-824 | codex-server-sync | AMUX-4416 |
| 58 | AF-825 | codex-server-sync | AMUX-4417 |
| 59 | AF-826 | codex-server-sync | AMUX-4417 |
| 60 | AF-827 | codex-server-sync | AMUX-4417 |
| 61 | AF-828 | codex-server-sync | AMUX-4417 |
| 62 | AF-829 | codex-server-sync | AMUX-4417 |
| 63 | AF-830 | codex-server-sync | AMUX-4417 |
| 64 | AF-831 | codex-server-sync | AMUX-4417 |
| 65 | AF-832 | codex-server-sync | AMUX-4417 |
| 66 | AF-833 | codex-server-sync | AMUX-4417 |
| 67 | AF-834 | codex-server-sync | AMUX-4417 |
| 68 | AF-835 | codex-server-sync | AMUX-4417 |
| 69 | AF-836 | codex-server-sync | AMUX-4417 |
| 70 | AF-837 | codex-server-sync | AMUX-4417 |
| 71 | AF-838 | codex-server-sync | AMUX-4417 |
| 72 | AF-839 | codex-server-sync | AMUX-4417 |
| 73 | AF-840 | codex-server-sync | AMUX-4417 |
| 74 | AF-841 | codex-server-sync | AMUX-4417 |
| 75 | AF-842 | codex | AMUX-4420 |
| 76 | AF-843 | codex | AMUX-4421 |
| 77 | AF-844 | codex | AMUX-4424 |
| 78 | AF-845 | codex-server-sync | AMUX-4417 |
| 79 | AF-846 | codex-server-sync | AMUX-4417 |
| 80 | AF-847 | codex-server-sync | AMUX-4417 |
| 81 | AF-848 | codex-server-sync | AMUX-4417 |
| 82 | AF-849 | codex-server-sync | AMUX-4417 |
| 83 | AF-850 | codex-server-sync | AMUX-4417 |
| 84 | AF-851 | codex-server-sync | AMUX-4417 |
| 85 | AF-852 | codex-server-sync | AMUX-4417 |
| 86 | AF-853 | codex-server-sync | AMUX-4417 |
| 87 | AF-854 | codex-server-sync | AMUX-4417 |
| 88 | AF-855 | codex-server-sync | AMUX-4417 |
| 89 | AF-856 | codex-server-sync | AMUX-4417 |
| 90 | AF-857 | codex-server-sync | AMUX-4417 |
| 91 | AF-858 | codex-server-sync | AMUX-4417 |
| 92 | AF-859 | codex-server-sync | AMUX-4417 |
| 93 | AF-860 | codex-server-sync | none — continuation of the user's isolated housekeeping request |
| 94 | AF-861 | codex-server-sync | none — live deployment verification for the user's housekeeping request |
| 95 | AF-862 | codex-server-sync | none — user requested isolated-worker consolidated lifecycle coverage |
| 96 | AF-863 | codex-server-sync | none — run-owned offline lifecycle fixture cards are deleted after verification |
| 97 | AF-864 | codex-server-sync | none — consolidated offline lifecycle acceptance |
| 98 | AF-865 | codex-server-sync | none — visual review of the consolidated offline lifecycle |
| 99 | AF-735 | amux-frustrations | AF-735 |
| 100 | AF-731 | amux-frustrations | AF-731 |
| 101 | AF-729 | amux-frustrations | AF-729 |
| 102 | AF-657 | amux-frustrations | AF-657 |
| 103 | AF-740 | amux-frustrations | AF-740 |
| 104 | AF-729 | amux-frustrations | AF-729 |
| 105 | AF-741 | amux-frustrations | AF-741 |
| 106 | AF-742 | amux-frustrations | AF-742 |
| 107 | AF-743 | amux-frustrations | AF-743 |
| 108 | AF-866 | codex-server-sync | AMUX-4417 |
| 109 | AF-867 | codex-server-sync | AMUX-4417 |
| 110 | AF-868 | amux-frustrations | AF-745 |
| 111 | AF-869 | amux-frustrations | AF-745 |
| 112 | AF-870 | amux-frustrations | AF-745 |
| 113 | AF-871 | amux-frustrations | AF-745 |
| 114 | AF-872 | amux-frustrations | AMUX-4460 |
| 115 | AF-873 | amux-frustrations | AMUX-4460 |
| 116 | AF-874 | amux-frustrations | AF-745 |
| 117 | AF-875 | codex-server-sync | AMUX-4417 |
| 118 | AF-750 | amux-frustrations | AF-750 |
| 119 | AF-876 | amux-frustrations | AF-746 |
| 120 | AF-877 | amux-frustrations | AF-746 |
| 121 | AF-878 | amux-frustrations | AMUX-4469 |
| 122 | AF-879 | amux-frustrations | AF-397 |
| 123 | AF-880 | amux-frustrations | AMUX-3757 |
| 124 | AF-881 | amux-frustrations | AMUX-4486 |
| 125 | AF-882 | amux-frustrations | AMUX-4486 |
| 126 | AF-883 | amux-frustrations | AMUX-4487 |
| 127 | AF-766 | amux-frustrations | AF-766 |
| 128 | AF-768 | amux-frustrations | AF-768 |
| 129 | AF-770 | amux-frustrations | AF-770 |
| 130 | AF-772 | amux-frustrations | AF-772 |
| 131 | AF-773 | amux-frustrations | AF-773 |
| 132 | AF-773 | amux-frustrations | AF-773 |
| 133 | AF-884 | codex-server-sync | AMUX-4417 |
| 134 | AF-885 | codex-server-sync | AMUX-4417 |
| 135 | AF-774 | amux-frustrations | AF-774 |
| 136 | AF-774 | amux-frustrations | AF-774 |
| 137 | AF-774 | amux-frustrations | AF-774 |
| 138 | AF-775 | amux-frustrations | AF-775 |
| 139 | AF-777 | amux-frustrations | AF-777 |
| 140 | AF-729 | amux-frustrations | AF-729 |
| 141 | AF-779 | amux-frustrations | AF-779 |
| 142 | AF-785 | amux-frustrations | AF-785 |
