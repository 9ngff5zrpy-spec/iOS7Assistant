#!/usr/bin/env python3
"""Developer packaging utility. Python is NOT required by the distributed app.

Copy every non-system dylib recursively, preserve distinct library versions,
rewrite all load commands to relative paths, and sign each resulting Mach-O.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'dist'
APP = DIST / 'iOS 7 Assistant.app'
TOOLS = APP / 'Contents/Resources/tools'
LIB = TOOLS / 'lib'
KIT = ROOT / 'Vendor/bin'
identity = os.environ.get('SIGN_IDENTITY', '-')
for name in ['Strings.json', 'firmware-keys.json', 'expected-patches.json', 'firmware-hashes.json', 'dummy.bin']:
    if not (ROOT / 'Resources' / name).is_file(): raise RuntimeError('Missing required resource: ' + name)

def run(*args):
    try: return subprocess.check_output(list(map(str, args)), text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as error:
        print(error.output)
        raise

if APP.exists():
    shutil.rmtree(APP)
(APP / 'Contents/MacOS').mkdir(parents=True)
LIB.mkdir(parents=True)
for source in (ROOT / 'Resources').iterdir():
    target = APP / 'Contents/Resources' / source.name
    if source.is_dir(): shutil.copytree(source, target)
    else: shutil.copy2(source, target)
shutil.copy2(ROOT / 'Build/iOS7Assistant', APP / 'Contents/MacOS/iOS7Assistant')

mapping = {}
records = []
def deps(path):
    lines = run('/usr/bin/otool', '-arch', 'arm64', '-L', path).splitlines()[1:]
    result = []
    for line in lines:
        if ' (compatibility version ' in line:
            result.append(line.strip().split(' (compatibility version ')[0])
    return result

def resolve(dep, original):
    if dep.startswith('@executable_path/'):
        return (KIT / dep.removeprefix('@executable_path/')).resolve()
    if dep.startswith('@loader_path/'):
        found = (original.parent / dep.removeprefix('@loader_path/')).resolve()
        # The kit dylibs use their own loader-relative install IDs. Newly linked
        # helpers inherit those IDs; their libraries are in our input lib folder.
        if not found.exists() and original.parent == KIT.resolve():
            found = (KIT / 'lib' / dep.removeprefix('@loader_path/')).resolve()
        return found
    if dep.startswith('@rpath/'):
        raise RuntimeError(f'Unresolved rpath: {original}: {dep}')
    return Path(dep).resolve()

def copy_library(source):
    source = source.resolve()
    if source in mapping: return mapping[source]
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    target = LIB / (source.stem + '-' + digest[:10] + '.dylib')
    mapping[source] = target
    copy_macho(source, target, library=True)
    return target

def copy_macho(source, target, library=False):
    source = source.resolve()
    # Keep arm64 only: no Rosetta runtime requirement.
    arches = run('/usr/bin/lipo', '-archs', source).strip().split()
    if 'arm64' not in arches: raise RuntimeError(f'Not native arm64: {source}')
    if len(arches) > 1: run('/usr/bin/lipo', source, '-thin', 'arm64', '-output', target)
    else: shutil.copy2(source, target)
    target.chmod(0o755)
    subprocess.run(['/usr/bin/codesign', '--remove-signature', str(target)], capture_output=True)
    arguments = []
    for dep in deps(source):
        if dep.startswith(('/usr/lib/', '/System/Library/')): continue
        resolved = resolve(dep, source)
        if resolved == source: continue  # dylib's own install ID
        copied = copy_library(resolved)
        relative = ('@loader_path/' if library else '@executable_path/lib/') + copied.name
        arguments.extend(['-change', dep, relative])
    if library: arguments.extend(['-id', '@loader_path/' + target.name])
    if arguments: run('/usr/bin/install_name_tool', *arguments, target)
    run('/usr/bin/codesign', '--force', '--sign', identity, target)
    records.append({'file': str(target.relative_to(APP)), 'source': str(source),
                    'originalSHA256': hashlib.sha256(source.read_bytes()).hexdigest()})

for name in ['ios7-engine', 'ios7-boot', 'ipwnder', 'irecovery', 'ideviceinfo',
             'idevice_id', 'ideviceactivation', 'idevicerestore', 'img4',
             'ipatcher', 'Kernel64Patcher2', 'kerneldiff', 'tsschecker',
             'ios7-maintenance-boot', 'pzb', 'hfsplus', 'sshpass', 'iproxy']:
    copy_macho(KIT / name, TOOLS / name)

import plistlib
info = dict(CFBundleName='iOS 7 Assistant', CFBundleDisplayName='iOS 7 Assistant',
            CFBundleIdentifier='org.ios7assistant.mac', CFBundleExecutable='iOS7Assistant',
            CFBundlePackageType='APPL', CFBundleIconFile='AppIcon', CFBundleShortVersionString='0.2.3',
            CFBundleVersion='5', LSMinimumSystemVersion='14.0',
            NSHighResolutionCapable=True, NSPrincipalClass='NSApplication',
            NSHumanReadableCopyright='Interface: iOS 7 Assistant contributors. Third-party credits included.')
(APP / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
public_records = []
for item in records:
    public_records.append({'file': item['file'], 'originalSHA256': item['originalSHA256'],
                           'inputName': Path(item['source']).name})
(APP / 'Contents/Resources/Licenses/binary-provenance.json').write_text(json.dumps(public_records, indent=2) + '\n')
run('/usr/bin/codesign', '--force', '--sign', identity, APP)
run('/usr/bin/codesign', '--verify', '--deep', '--strict', APP)
# Fail packaging if any tool still loads a dependency from the build machine.
for path in TOOLS.rglob('*'):
    if not path.is_file(): continue
    for dep in deps(path):
        if not dep.startswith(('/usr/lib/', '/System/Library/', '@loader_path/', '@executable_path/')):
            raise RuntimeError(f'External dependency left: {path}: {dep}')
    build = run('/usr/bin/xcrun', 'vtool', '-show-build', path)
    for line in build.splitlines():
        if line.strip().startswith('minos '):
            version = tuple(map(int, line.split()[1].split('.')))
            if version > (14, 0): raise RuntimeError(f'Requires newer macOS than 14: {path}: {version}')
(DIST / 'build-provenance.json').write_text(json.dumps(records, indent=2) + '\n')
print(APP)
print(f'{len(records)} native binaries/libraries bundled; no external dependencies.')
