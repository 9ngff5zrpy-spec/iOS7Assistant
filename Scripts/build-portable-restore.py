#!/usr/bin/env python3
"""Developer build: link the verified restore patch to macOS 14 compatible libs.

Arguments: idevicerestore-source libzip-source libzip-build headers-prefix
The runtime libraries in Vendor/bin/lib come from Legacy-iOS-Kit and target
macOS 11. Build-time headers may come from the matching library releases.
"""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
source, zip_source, zip_build, prefix = map(lambda p: Path(p).resolve(), sys.argv[1:])
names = ['idevicerestore', 'log', 'common', 'fls', 'mbn', 'img3', 'img4', 'ftab',
         'ipsw', 'normal', 'dfu', 'recovery', 'restore', 'asr', 'fdr', 'ace3',
         'download', 'locking', 'deviceinterfaced', 'limera1n']
args = ['clang', '-std=gnu23', '-O2', '-mmacosx-version-min=14.0', '-Wl,-headerpad_max_install_names', '-DHAVE_CONFIG_H',
        '-I' + str(source), '-I' + str(source/'src'),
        '-I' + str(zip_source/'lib'), '-I' + str(zip_build)]
for name in ['libirecovery', 'libimobiledevice', 'libimobiledevice-glue', 'libplist', 'libusbmuxd', 'libtatsu']:
    args.append('-I' + str(prefix / name / 'include'))
args += [str(source/'src'/(name+'.c')) for name in names]
for name in ['libirecovery-1.0.5', 'libimobiledevice-1.0.6', 'libimobiledevice-glue-1.0.0',
             'libusbmuxd-2.0.7', 'libplist-2.0.12', 'libtatsu.0']:
    args.append(str(root/'Vendor/bin/lib'/(name+'.dylib')))
args += [str(zip_build/'lib/libzip.a'), '-lcurl', '-lz', '-lbz2',
         '-framework', 'IOKit', '-framework', 'CoreFoundation',
         '-o', str(root/'Vendor/bin/idevicerestore')]
subprocess.run(args, check=True)
