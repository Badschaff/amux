#!/usr/bin/env python3
"""AF-926. A reproducible count of the "shared-index" frustration class, so a
post-rollout re-run can be compared against THIS run rather than against the
2026-09-04 AF-191 figure (28%, 21 of 75) whose exact classification method
was never written down and cannot be replayed.

WHAT THIS COUNTS, and what it does not. `AREA: attribution`/`AREA:
instruments` (frustrations_audit.py's own clustering) is the candidate pool
-- those two areas are where shared-checkout-shaped entries land, but neither
area is shared-checkout-shaped BY DEFINITION: `instruments` also holds
unrelated diagnostic-measurement bugs (a duplicate-delivery probe, a
timestamp-format guard), and a keyword match inside that pool is a PROXY, not
a verdict. Spot-checked live on 2026-09-18: "cross-lane" matched an entry
about upload-storage paths being mistaken for repeated instructions ACROSS
REPOS -- a real bug, not a shared-checkout one. A manual title read of the
same run found roughly 4-5 of 18 keyword hits were the same shape of false
positive (browser-dashboard impersonation, a board-discard misattribution, a
test-wrapper exit-code masking bug, the cross-repo case above).

So this script reports the KEYWORD COUNT plainly labeled as a proxy, not a
verdict, and its own docstring is where the false-positive rate lives so the
next run does not have to rediscover it by hand. Tightening the keyword list
or replacing it with a manual read is a legitimate next step; silently
treating the proxy as the true count is the mistake this note exists to
prevent (ethos rule 4: say what a count actually measures).
"""
import re
import sys
from pathlib import Path

FRUST = Path(__file__).resolve().parent.parent / "frustrations.md"

CANDIDATE_AREAS = ("attribution", "instruments")

KEYWORDS = [
    "shared checkout", "shared index", "shared tree", "shared-checkout",
    "shared-index", "worktree", "peer's uncommitted", "peer's wip",
    "swept", "misattribut", "cross-lane", "another lane", "graft-base",
    "graft base", "dirty tree", "git add -a", "staged-guard", "contended",
    "concurrent", "one git index", "one working tree",
]


def parse(text):
    body = text.split("\n---\n", 1)
    text = body[1] if len(body) > 1 else text
    out = []
    for blk in re.findall(r"(?ms)^## .*?(?=\n## |\Z)", text):
        title = blk.split("\n", 1)[0][3:].strip()
        area_m = re.search(r"(?m)^AREA:\s*(.*)$", blk)
        status_m = re.search(r"(?m)^STATUS:\s*(.*)$", blk)
        card_m = re.search(r"(?m)^CARD:\s*(.*)$", blk)
        out.append({
            "title": title,
            "area": (area_m.group(1).strip() if area_m else ""),
            "status": (status_m.group(1).strip() if status_m else ""),
            "card": (card_m.group(1).strip() if card_m else ""),
            "raw": blk,
        })
    return out


def shaped(entry):
    t = entry["raw"].lower()
    return any(k in t for k in KEYWORDS)


def main():
    raw = FRUST.read_text()
    entries = parse(raw)
    candidates = [e for e in entries if e["area"] in CANDIDATE_AREAS]
    shaped_all = [e for e in candidates if shaped(e)]
    shaped_open = [e for e in shaped_all if e["status"].startswith("open")]

    print(f"n_considered (total ledger entries): {len(entries)}")
    print(f"candidate pool (AREA in {CANDIDATE_AREAS}): {len(candidates)}")
    print(f"keyword-proxy shared-index-shaped (any status): {len(shaped_all)}")
    print(f"keyword-proxy shared-index-shaped AND open: {len(shaped_open)}")
    print()
    print("PROXY, NOT A VERDICT -- see this script's own docstring for the")
    print("measured false-positive rate (~4-5 of 18 on the 2026-09-18 run).")
    print()
    for e in shaped_open:
        print(f"  OPEN  {e['card'] or '(no card)':<10} {e['title'][:85]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
