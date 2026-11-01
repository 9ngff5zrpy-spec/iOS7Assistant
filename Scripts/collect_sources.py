#!/usr/bin/env python3
"""Developer-only source/license collection. Not called by the application."""
from pathlib import Path
import concurrent.futures
import hashlib
import io
import json
import re
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'Resources/Licenses/SourceArchives'
SOURCES.mkdir(parents=True, exist_ok=True)
NOTICES = SOURCES.parent
manifest = []

def download(name, url, expected=None):
    target = SOURCES / (name + ('.tar.xz' if url.endswith('.tar.xz') else '.tar.gz' if 'tar.gz' in url or 'codeload' in url else '.tar.bz2'))
    data = target.read_bytes() if target.exists() else urllib.request.urlopen(url, timeout=90).read()
    sha = hashlib.sha256(data).hexdigest()
    if expected and sha != expected: raise RuntimeError('Source hash mismatch: ' + name)
    target.write_bytes(data)
    # Extract license/notice texts, never executables or archive paths.
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for entry in archive.getmembers():
            base = Path(entry.name).name
            if entry.isfile() and entry.size < 200000 and re.match(r'^(LICENSE|COPYING|NOTICE|AUTHORS)(\..*|-[A-Z0-9.]+)?$', base, re.I):
                nested = entry.name.split('/')
                suffix = '-'.join(nested[1:])
                (NOTICES / (name + '-' + suffix.replace('/', '-'))).write_bytes(archive.extractfile(entry).read())
    return dict(name=name, url=url, SHA256=sha, archive=target.name)

jobs = []
# Exact source release archives and checksums from the installed formulae.
for name in ['libirecovery', 'libimobiledevice', 'libimobiledevice-glue', 'libusbmuxd', 'libplist', 'libtatsu', 'libzip', 'openssl@4', 'xz', 'zstd']:
    directory = Path('/opt/homebrew/opt') / name / '.brew'
    formula = next(directory.glob('*.rb')).read_text()
    url = re.search(r'^  url "([^"]+)"', formula, re.M)[1]
    sha = re.search(r'^  sha256 "([^"]+)"', formula, re.M)[1]
    jobs.append((name, url, sha))

repos = [('img4lib', 'LukeZGD/img4lib', 'HEAD'),
         ('ipwnder_lite', 'LukeZGD/ipwnder_lite', 'refs/heads/macos'),
         ('tsschecker', '1Conan/tsschecker', 'HEAD'),
         ('libideviceactivation', 'libimobiledevice/libideviceactivation', '9ca1851'),
         ('kit-libimobiledevice', 'LukeZGD/libimobiledevice', 'HEAD'),
         ('kit-libirecovery', 'LukeZGD/libirecovery', 'HEAD'),
         ('SSHRD-kerneldiff', 'verygenericname/SSHRD_Script', '708ce254fea08e442ecb4cd20c3fdbfe6ce9ab66')]
for name, repo, ref in repos:
    commit = ref
    if ref == 'HEAD' or ref.startswith('refs/'):
        commit = subprocess.check_output(['git', 'ls-remote', 'https://github.com/' + repo + '.git', ref], text=True).split()[0]
    jobs.append((name, 'https://codeload.github.com/' + repo + '/tar.gz/' + commit, None))

def collect(job):
    result = download(*job)
    print('Collected ' + result['name'], flush=True)
    return result
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
    manifest.extend(pool.map(collect, jobs))
(NOTICES / 'upstream-sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('All source archives and notices collected.')
