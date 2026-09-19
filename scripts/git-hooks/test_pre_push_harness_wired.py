#!/usr/bin/env python3
"""The pre-push refusal for an unwired test harness (AMUX-4823).

AF-346 requires every `scripts/test-*.sh` to be either wired into checks.yml or
recorded in scripts/fixtures/harness-wired-baseline.txt. Until this hook check
existed, nothing said so until CI — after the push, for everyone. Measured over
24h to 2026-09-18, 2 of the 3 harnesses that reached main were unwired, and
because `checks` aborts on its first failing step that verdict sat invisible
behind older breakage from 09-17 to 09-18.

THREE CASES, and the first is the one that makes the other two mean anything.
The fixture's own copy of test-harness-wired.sh exits non-zero regardless (its
baseline is a stub), so a push that is ALLOWED can only have been allowed
because the range selection skipped the check. Without that control, "refused"
proves nothing: a gate that blocks every push would pass the other two.

Run: python3 scripts/git-hooks/test_pre_push_harness_wired.py   (exit 0 = pass)
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HOOK = os.path.join(ROOT, "scripts", "git-hooks", "pre-push")
WIRED = os.path.join(ROOT, "scripts", "test-harness-wired.sh")

CHECKS_YML = (
    "name: checks\njobs:\n  checks:\n    steps:\n"
    "      - run: ./scripts/test-already-wired.sh\n"
    "      - run: ./scripts/test-harness-wired.sh\n"
)
STUB = '#!/bin/bash\nset -euo pipefail\necho "  ok"\necho "stub: 1 passed, 0 failed"\n'

passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        print("  ok    %-52s %s" % (label, got))
        passed += 1
    else:
        print("  FAIL  %-52s got %s want %s" % (label, got, want))
        failed += 1


def git(work, *args, env=None):
    e = dict(os.environ)
    e.update({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
              "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})
    if env:
        e.update(env)
    return subprocess.run(["git", "-C", work] + list(args),
                          capture_output=True, text=True, timeout=180, env=e)


def commit(work, msg, paths):
    git(work, "add", *paths, "--")
    git(work, "commit", "-qm", msg)


def main():
    tmp = tempfile.mkdtemp(prefix="prepush-wired-")
    try:
        origin = os.path.join(tmp, "origin.git")
        work = os.path.join(tmp, "work")
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", origin], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", work], check=True)
        git(work, "remote", "add", "origin", origin)

        os.makedirs(os.path.join(work, "scripts", "fixtures"))
        os.makedirs(os.path.join(work, ".github", "workflows"))
        shutil.copy(WIRED, os.path.join(work, "scripts", "test-harness-wired.sh"))
        open(os.path.join(work, ".github/workflows/checks.yml"), "w").write(CHECKS_YML)
        open(os.path.join(work, "scripts/fixtures/harness-wired-baseline.txt"), "w").write("# baseline\n")
        open(os.path.join(work, "scripts/test-already-wired.sh"), "w").write(STUB)
        for f in os.listdir(os.path.join(work, "scripts")):
            if f.endswith(".sh"):
                os.chmod(os.path.join(work, "scripts", f), 0o755)
        commit(work, "fixture", ["scripts", ".github"])
        shutil.copy(HOOK, os.path.join(work, ".git", "hooks", "pre-push"))
        os.chmod(os.path.join(work, ".git", "hooks", "pre-push"), 0o755)

        # Seed origin past the harness-adding commits, deliberately overriding,
        # so later pushes carry a range that does NOT contain them.
        git(work, "push", "-q", "origin", "main", env={"AMUX_SKIP_HARNESS_WIRED": "1"})

        # THE CONTROL. Touches no harness, no workflow, no baseline. The
        # fixture's wired-check still exits non-zero, so ALLOWED can only mean
        # the range selection skipped it.
        open(os.path.join(work, "README.md"), "w").write("hello\n")
        commit(work, "unrelated: touches no harness", ["README.md"])
        check("push touching no harness is allowed", git(work, "push", "origin", "main").returncode, 0)

        # THE REFUSAL.
        orphan = os.path.join(work, "scripts", "test-fresh-orphan.sh")
        open(orphan, "w").write(STUB)
        os.chmod(orphan, 0o755)
        commit(work, "adds an unwired harness", ["scripts"])
        r = git(work, "push", "origin", "main")
        check("push adding an unwired harness is refused", r.returncode != 0, True)
        out = r.stdout + r.stderr
        check("refusal names the wire remedy", "checks.yml" in out, True)
        check("refusal names the baseline remedy", "harness-wired-baseline.txt" in out, True)
        check("refusal names the override", "AMUX_SKIP_HARNESS_WIRED" in out, True)

        # THE ESCAPE, because a gate with no truthful way past it gets routed
        # around rather than satisfied (ethos rule 3).
        check("override lands it anyway",
              git(work, "push", "origin", "main",
                  env={"AMUX_SKIP_HARNESS_WIRED": "1"}).returncode, 0)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("\npre-push harness-wired: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
