#!/usr/bin/env python3
"""Exercise the real installer through both binary publications, in disposable Git fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = Path(os.environ.get('AMUX_INSTALLER_SOURCE_ROOT', ROOT))
passed = failed = 0

def check(ok, name):
    global passed, failed
    if ok:
        passed += 1
        print('PASS ' + name)
    else:
        failed += 1
        print('FAIL ' + name)

def run(args, cwd, **kwargs):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=45, **kwargs)

(ROOT / 'scratch').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='install-source-', dir=ROOT / 'scratch') as td:
    base = Path(td)
    for mode in ('dirty', 'clean', 'advance', 'relative-target', 'unmerged', 'no-git', 'build-failed', 'target-replaced', 'mixed-pair', 'artifact-tampered', 'handoff-replaced'):
        area = base / mode
        repo = area / 'source with spaces'
        fakebin = area / 'bin'
        repo.mkdir(parents=True)
        fakebin.mkdir()
        (repo / 'scripts').mkdir()
        shutil.copy2(Path(os.environ.get('AMUX_INSTALLER_UNDER_TEST', SOURCE_ROOT / 'install.sh')), repo / 'install.sh')
        for name in ('build-install-from-head.sh', 'install-artifact-manifest.py'):
            helper = SOURCE_ROOT / 'scripts' / name
            if helper.exists():
                shutil.copy2(helper, repo / 'scripts' / helper.name)
        (repo / 'feature.txt').write_text('COMMITTED\n')
        (repo / 'cli.txt').write_text('CLI-COMMITTED\n')
        installed = area / 'installed'
        installed.mkdir()
        (installed / 'amux-server-rs').write_text('OLD-SERVER\n')
        (installed / 'amux-rs').write_text('OLD-CLI\n')
        cli_install = repo / 'scripts/install-cli.sh'
        cli_install.write_text('#!/bin/sh\ntouch "$FIXTURE_AREA/publication-complete"\nexit 91\n')
        cli_install.chmod(0o755)
        cargo = repo / 'scripts/safe-cargo.sh'
        cargo.write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$PWD" > "$FIXTURE_AREA/build-cwd"
if [[ "${FIXTURE_ADVANCE:-}" == 1 && ! -f "$FIXTURE_AREA/advanced" ]]; then
  printf 'NEW-HEAD\\n' > "$FIXTURE_SOURCE/feature.txt"
  git -C "$FIXTURE_SOURCE" add feature.txt
  git -C "$FIXTURE_SOURCE" -c core.hooksPath=/dev/null commit -qm advanced
  touch "$FIXTURE_AREA/advanced"
fi
if [[ "${FIXTURE_FAIL:-}" == 1 ]]; then exit 19; fi
artifact=; bin=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin) bin="$2"; shift ;;
    --emit=link=*) artifact="${1#--emit=link=}" ;;
  esac
  shift
done
if [[ -n "$artifact" ]]; then
  if [[ "$bin" == amux-server ]]; then cat feature.txt > "$artifact"; else cat cli.txt > "$artifact"; fi
  chmod +x "$artifact"
else
  mkdir -p "$CARGO_TARGET_DIR/release"
  cat feature.txt > "$CARGO_TARGET_DIR/release/amux-server"
  cat cli.txt > "$CARGO_TARGET_DIR/release/amux-rs"
  chmod +x "$CARGO_TARGET_DIR/release/amux-server" "$CARGO_TARGET_DIR/release/amux-rs"
  if [[ -e untracked.rs ]]; then printf 'UNTRACKED\\n' >> "$CARGO_TARGET_DIR/release/amux-server"; fi
fi
if [[ "$FIXTURE_MODE" == handoff-replaced ]]; then
  mkdir -p "$FIXTURE_TARGET/release"
  printf 'PEER-SHARED-SERVER\\n' > "$FIXTURE_TARGET/release/amux-server"
  printf 'PEER-SHARED-CLI\\n' > "$FIXTURE_TARGET/release/amux-rs"
  touch "$FIXTURE_AREA/handoff-injected"
fi
''')
        cargo.chmod(0o755)
        install = fakebin / 'install'
        install.write_text('''#!/usr/bin/env python3
import os, pathlib, shutil, sys
area = pathlib.Path(os.environ['FIXTURE_AREA'])
source, destination = pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
target = pathlib.Path(os.environ['FIXTURE_TARGET']) / 'release'
mode = os.environ['FIXTURE_MODE']
first = not (area / 'install-called').exists()
if first and mode == 'target-replaced':
    target.mkdir(parents=True, exist_ok=True)
    (target / 'amux-server').write_text('PEER-UNCOMMITTED-BUILD\\n')
shutil.copyfile(source, destination)
os.chmod(destination, 0o755)
(area / 'install-called').touch()
if first and mode == 'mixed-pair':
    target.mkdir(parents=True, exist_ok=True)
    (target / 'amux-rs').write_text('PEER-CLI\\n')
if first and mode == 'artifact-tampered':
    source.with_name('amux-rs').write_text('TAMPERED-CLI\\n')
''')
        install.chmod(0o755)
        env = dict(os.environ, AMUX_HOME=str(area / 'data'), AMUX_INSTALL_BIN=str(area / 'installed'),
                   AMUX_NO_CARGO_CONFIG='1', AMUX_ALLOW_NO_TMUX='1', AMUX_NO_BUILDER='1',
                   CARGO_TARGET_DIR=str(area / 'target'), PATH=str(fakebin) + os.pathsep + os.environ['PATH'],
                   FIXTURE_AREA=str(area), FIXTURE_SOURCE=str(repo), FIXTURE_MODE=mode, FIXTURE_TARGET=str(area / 'target'), TMPDIR=str(area),
                   GIT_CEILING_DIRECTORIES=str(base))
        # Never inherit a caller's index, worktree, or Git directory into fixtures.
        for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'):
            env.pop(key, None)
        if mode != 'no-git':
            assert run(['git', 'init', '-q'], repo, env=env).returncode == 0
            for key, value in [('user.name', 'Installer fixture'), ('user.email', 'fixture@example.invalid'), ('core.hooksPath', '/dev/null')]:
                assert run(['git', 'config', key, value], repo, env=env).returncode == 0
            assert run(['git', 'add', '.'], repo, env=env).returncode == 0
            assert run(['git', 'commit', '-qm', 'committed specimen'], repo, env=env).returncode == 0
            sha = run(['git', 'rev-parse', 'HEAD'], repo, env=env).stdout.strip()
        if mode == 'relative-target':
            env['CARGO_TARGET_DIR'] = 'relative-target'
            env['FIXTURE_TARGET'] = str(repo / 'relative-target')
        if mode == 'unmerged':
            blob = run(['git', 'rev-parse', 'HEAD:feature.txt'], repo, env=env).stdout.strip()
            stages = '0 ' + ('0' * 40) + '\tfeature.txt\n' + ''.join(f'100644 {blob} {stage}\tfeature.txt\n' for stage in (1, 2, 3))
            assert run(['git', 'update-index', '--index-info'], repo, env=env, input=stages).returncode == 0
        if mode == 'dirty':
            (repo / 'feature.txt').write_text('DIRTY-PEER-DRAFT\n')
            (repo / 'untracked.rs').write_text('UNCOMMITTED-MIGRATION\n')
        if mode == 'advance':
            env['FIXTURE_ADVANCE'] = '1'
        if mode == 'build-failed':
            env['FIXTURE_FAIL'] = '1'
            stale = area / 'target/release'
            stale.mkdir(parents=True)
            for name in ('amux-server', 'amux-rs'):
                (stale / name).write_text('STALE\n')
                (stale / name).chmod(0o755)
        result = run(['bash', 'install.sh'], repo, env=env)
        audit = area / 'data/logs/server-install.log'
        audit_text = audit.read_text() if audit.exists() else ''
        publication = installed / 'amux-server-rs'
        cli_publication = installed / 'amux-rs'
        if mode in ('no-git', 'build-failed', 'unmerged', 'artifact-tampered'):
            check(result.returncode not in (0, 91) and publication.read_text() == 'OLD-SERVER\n' and cli_publication.read_text() == 'OLD-CLI\n', mode + ': refuses before binary publication')
            check(('installer_artifact_mismatch' if mode == 'artifact-tampered' else 'installer_source_failed') in audit_text, mode + ': durable failure diagnostic')
            if mode in ('no-git', 'unmerged'):
                check(not (area / 'build-cwd').exists(), mode + ': never invokes compiler')
        else:
            check(result.returncode == 91, mode + ': reaches controlled post-binary boundary')
            check(publication.exists() and publication.read_text() == 'COMMITTED\n', mode + ': only committed binary bytes reach install')
            check(cli_publication.read_text() == 'CLI-COMMITTED\n', mode + ': matching committed CLI bytes reach install')
            check((area / 'build-cwd').exists() and Path((area / 'build-cwd').read_text().strip()) != repo, mode + ': compiler reads private snapshot')
            check('installer_source_selected' in audit_text and ('commit=' + sha) in audit_text, mode + ': durable exact source diagnostic')
            check('installer_artifacts_published' in audit_text, mode + ': published pair has durable identity')
            if mode == 'target-replaced':
                check((Path(env['FIXTURE_TARGET']) / 'release/amux-server').read_text() == 'PEER-UNCOMMITTED-BUILD\n', 'target replacement actually changed shared server')
            if mode == 'mixed-pair':
                check((Path(env['FIXTURE_TARGET']) / 'release/amux-rs').read_text() == 'PEER-CLI\n', 'mixed pair actually changed shared CLI')
            if mode == 'handoff-replaced':
                check((area / 'handoff-injected').exists(), 'handoff: shared outputs were actually replaced')
            if mode == 'dirty':
                check('uncommitted_source_excluded=true' in audit_text, 'dirty: excluded work self-announces')
                check((repo / 'feature.txt').read_text() == 'DIRTY-PEER-DRAFT\n' and (repo / 'untracked.rs').exists(), 'dirty: peer files untouched')
            if mode == 'advance':
                check(run(['git', 'rev-parse', 'HEAD'], repo, env=env).stdout.strip() != sha, 'advance: positive control actually changed source HEAD')
        check(not list(installed.glob('.amux-rust-install.*')), mode + ': private publication stage cleaned')
        if mode != 'no-git':
            worktrees = run(['git', 'worktree', 'list', '--porcelain'], repo, env=env).stdout
            check(worktrees.count('worktree ') == 1, mode + ': temporary worktree cleaned')
print(f'install committed source: {passed} passed, {failed} failed')
raise SystemExit(bool(failed))
