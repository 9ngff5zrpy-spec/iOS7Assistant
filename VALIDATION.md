# Validation — 0.2.0

- Swift GUI, file engine and native helpers target arm64 macOS 14.0. Intel is excluded.
- Bundler checks the minimum deployment target of every tool and dylib and rejects versions above 14. All non-system dylibs are copied and load commands rewritten to app-relative paths.
- Local ad-hoc signatures are verified with `codesign --verify --deep --strict`.
- 79 automated checks passed: complete simulated boot and restore flows, manual pause ordering, erase-consent gating, first-boot flow, supported model, stable ECID, BootROM/iBSS/Recovery state checks, safe profile paths, ES/EN translation parity and a hardware-access block in demo mode.
- Full offline IPSW preparation passed using only the packaged tools with `PATH=/usr/bin:/bin`. No Homebrew tools were resolved at runtime.
- The resulting boot templates, BuildManifest and all six installation components were byte-identical to the earlier successful preparation. Patched iBSS, restore iBEC and kernel hashes are checked against the known working outputs in the engine.
- The macOS 14 kernel patcher was separately run on the decrypted original kernel and compared byte-for-byte against the known working patched kernel.
- Packaged idevicerestore and idevice_id version/help commands loaded their bundled libraries successfully, without querying or modifying a USB device.
- Native UI reviewed in Spanish and English: DFU with USB-A + adapter, switch to direct USB-C, both manual reconnection pauses, simple navigation and credits. Verified `@criss.repair_`, Codex assistance and the exact YouTube destination in the accessibility tree.

Runtime checks used the current Apple Silicon Mac on macOS 27. Execution on macOS 14, 15 and 26 still needs real-machine testing. Complete restore and maintenance runs initiated from the new GUI have not yet been validated end-to-end; the underlying restore/boot method previously succeeded on the project's iPhone6,2. No extra phone restore was performed during app development.

This test release is not Developer ID signed or notarized. It includes a guided Cydia/SCS WiFi Fix/Fiona workflow; the newly integrated hardware maintenance path still needs an end-to-end real-phone run. The previous manual procedure did succeed on this phone.

## 0.2.0 checks

- Direct ActivationState query returned `Activated` on the target iPhone; the old CLI `state` command printed Activated with exit status 1. The GUI now reads ActivationState directly and displays the explicit skip-Wi-Fi message only for Activated.
- Full maintenance preparation passed with cached originals, and its iBSS, iBEC, DeviceTree and kernel were byte-identical to the known working maintenance images.
- Bootstrap validation confirmed the system/data separation, original Cydia and patch packages, the existing-dpkg-database guard, loopback-only normal SSH, corrected `/bin/su`, and final SpringBoard restart.
- Real HTTPS downloads of all eight remote bootstrap assets matched the verified SHA-256 values. A partial iBSS download from Apple also matched its known hash. PreferenceLoader is bundled with LGPL source instead of bypassing the expired BigBoss TLS certificate.
- Tests cover the new maintenance/final-boot workflow, explicit activation parsing, ECID verification from ramdisk IORegistry, the demo hardware guard and binary input/output preservation for SSH archive transfers.
