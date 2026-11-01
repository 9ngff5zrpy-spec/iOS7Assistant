#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun --sdk iphoneos clang -target arm64-apple-ios8.0 -O2 -Wall -Wextra -Werror -framework CoreFoundation Sources/DeviceIdentity.c -o Resources/Maintenance/ios7-identity
codesign --force --sign - --digest-algorithm=sha1,sha256 Resources/Maintenance/ios7-identity
