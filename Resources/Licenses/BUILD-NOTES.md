# Included sources and build changes

App version 0.1.0. Target: arm64 macOS 14.0. No Intel or Rosetta dependency.

The app ships local copies of its tools and libraries. It does not invoke Homebrew, Python, a shell script, Xcode or a pre-existing kit installation at runtime. `/usr/bin/unzip` and `/usr/bin/zip` are the macOS system utilities used by the native preparation engine.

## Modified restore engine

Base: libimobiledevice/idevicerestore commit `4b3e847e1d9a1210049a9e3f1d1caa38650c6617`.

The included patch adds opt-in `CODEX_PRESERVE_IOS7_IBEC=1`. It accepts only iPhone6,2 already in Recovery with `iBoot-1940.10.58`, reuses the open recovery handle, and skips resending iBEC. All following restore stages stay in one execution and share its ticket. Without the environment variable, upstream behavior remains in effect.

`SourceArchives/idevicerestore-modified.tar.gz` contains the modified source, generated configure/config headers and original licensing. `Scripts/build-portable-restore.py` in the app source release lists the compilation and link inputs. It compiles C sources with `clang -std=gnu23 -O2 -mmacosx-version-min=14.0` and uses the kit's macOS 11-compatible libirecovery, libimobiledevice, glue, libusbmuxd, libplist and libtatsu dylibs. The package process rewrites the load paths to bundled relative paths.

libzip 1.12.1 is built from the accompanying verified source archive with CMake: deployment target 14, architecture arm64, static library, LZMA/Zstandard and OpenSSL/GnuTLS/mbedTLS/CommonCrypto backends disabled. Normal ZIP/deflate support remains enabled; Apple restore IPSWs do not require those extra backends. Link dependencies are system zlib and bzip2. This avoids dependencies on the build machine's newer Homebrew dylibs.

## Other locally compiled tools

- iPatcher commit `a86137983ef66ab35d079014df99f36bff4a5ace`: `clang -O2 -mmacosx-version-min=14.0 iPatcher/iPatcher.c -o ipatcher`.
- Kernel64Patcher2/seprmvr64 fork commit `7a1a55135355f44f8ed92114fa5c56886124021f`: compile `src/Kernel64Patcher.c`, `src/seprmvr64.c` and the embedded plooshfinder `src/*.c`, `src/formats/*.c`, `src/asm/*.c` with `-O2 -mmacosx-version-min=14.0 -Wno-int-conversion -Wno-incompatible-pointer-types -Iplooshfinder/include`. No source patches were applied. Native arm64 output was checked byte-for-byte against the working iOS 7 patched kernel; iPatcher's iBSS and restore iBEC output is likewise verified during preparation.
- `ios7-boot`: app source `Sources/BootHelper.c`, compiled with deployment target 14 and the kit's libirecovery. Generic ECID argument; no personal device ID is embedded.
- `idevice_id`: original `tools/idevice_id.c` from libimobiledevice 1.4.0, compiled with deployment target 14 and the kit's libimobiledevice dylib. Define its `PACKAGE_URL`, `PACKAGE_BUGREPORT` and `PACKAGE_VERSION` metadata as in the release.
- Swift GUI and file-preparation engine: `Scripts/build.sh`, deployment target macOS 14, optimized arm64. The GUI uses SwiftUI and Observation; preparation uses Foundation/CryptoKit. These sources accompany the release.

## Unmodified upstream tools and libraries

`ipwnder`, `irecovery` 1.3.1, `ideviceinfo` 1.4.0, `ideviceactivation` 1.1.1-28-g9ca1851, `img4`, `kerneldiff`, `tsschecker` 0.413-dd7e883 and kit dylibs are derived from the Legacy-iOS-Kit v26 distribution used successfully in this project. Packaging keeps their arm64 slices, rewrites library load paths and replaces signatures with local ad-hoc signatures. Original notices are preserved in the source archives and adjacent license files.

tsschecker source is pinned to `dd7e883adc94e2289e492b196bfbf67c7e18a544` and its libfragmentzip to `aaf6fae83a0aa6f7aae1c94721857076d04a14e8`. img4lib and tsschecker source archives include their submodules. Repository revisions, release URLs and archive hashes are recorded in `upstream-sources.json`. The kit fork source snapshots and exact release archives are included for the portable libraries.

The local build provenance records original executable/library hashes. The development source release includes this manifest with local build paths removed. Source archives allow inspection, rebuilding and replacement of third-party components; the app is locally signed, with no technical restriction on replacing these libraries and re-signing a modified build.

## Validation limits

Offline preparation completed with the embedded tools and produced the known patched component hashes. Demo tests cover both full workflows, language parity, wrong-device and wrong-stage rejection, path validation and the demo hardware-access guard. Build checks reject dependencies requiring macOS newer than 14 or loading libraries outside the app/system.

Runtime testing was on this project's current Apple Silicon Mac (macOS 27). Compatibility deployment checks are not a substitute for actual tests on macOS 14, 15 or 26. No additional phone restore was performed merely to test this GUI.
