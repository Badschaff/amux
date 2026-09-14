#!/usr/bin/env python3
"""Record or verify the two private installer artifacts; never read shared build outputs."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
from datetime import datetime, timezone

NAMES = ('amux-server', 'amux-rs')

def log(event, **fields):
    line = json.dumps({'time': datetime.now(timezone.utc).isoformat(), 'event': event, **fields}, sort_keys=True)
    print(line, file=sys.stderr)
    try:
        folder = Path(os.environ.get('AMUX_HOME', str(Path.home() / '.amux'))) / 'logs'
        folder.mkdir(parents=True, exist_ok=True)
        with (folder / 'server-install.log').open('a') as stream:
            stream.write(line + '\n')
    except OSError:
        print('WARN installer_artifact_audit_unavailable: verdict retained on stderr', file=sys.stderr)

def identity(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not info.st_mode & stat.S_IXUSR or info.st_size == 0:
        raise ValueError('artifact must be a nonempty regular executable')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return {'sha256': digest.hexdigest(), 'bytes': info.st_size}

def main():
    if len(sys.argv) not in (4, 5) or sys.argv[1] not in ('record', 'verify', 'publish'):
        raise ValueError('usage: record DIR COMMIT | verify DIR MANIFEST | publish DIR MANIFEST BIN_DIR')
    mode, directory, operand = sys.argv[1:4]
    if len(sys.argv) != (5 if mode == 'publish' else 4):
        raise ValueError('incorrect operand count')
    directory = Path(directory)
    if mode == 'record':
        if not re.fullmatch(r'[0-9a-f]{40}', operand):
            raise ValueError('full committed source identity required')
        manifest = {'commit': operand, 'artifacts': {name: identity(directory / name) for name in NAMES}}
        with (directory / 'manifest.json').open('x') as stream:
            json.dump(manifest, stream, sort_keys=True)
        log('installer_artifacts_recorded', measured=True, n_considered=2, **manifest)
        return
    manifest = json.loads(Path(operand).read_text())
    if not re.fullmatch(r'[0-9a-f]{40}', manifest.get('commit', '')) or set(manifest.get('artifacts', {})) != set(NAMES):
        raise ValueError('manifest must name the pinned commit and both artifacts')
    for name in NAMES:
        actual = identity(directory / name)
        expected = manifest['artifacts'][name]
        if actual != expected:
            log('installer_artifact_mismatch', measured=True, n_considered=2, artifact=name,
                commit=manifest['commit'], expected=expected, actual=actual)
            raise SystemExit(1)
    log('installer_artifacts_verified', measured=True, n_considered=2, commit=manifest['commit'])
    if mode == 'publish':
        destination = Path(sys.argv[4])
        pairs = [('amux-server', 'amux-server-rs'), ('amux-rs', 'amux-rs')]
        for _, name in pairs:
            if (destination / name).is_dir():
                raise ValueError('publication destination is a directory')
        published = []
        try:
            for original, name in pairs:
                os.replace(directory / original, destination / name)
                published.append(name)
        except OSError as error:
            log('installer_publication_failed', measured=True, n_considered=2,
                commit=manifest['commit'], published=published, reason=type(error).__name__)
            raise SystemExit(1) from error
        log('installer_artifacts_published', measured=True, n_considered=2, **manifest)

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError) as error:
        log('installer_artifact_refused', measured=False, n_considered=0, reason=type(error).__name__)
        raise SystemExit(1) from error
