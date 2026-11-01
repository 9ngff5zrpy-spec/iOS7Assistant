# Credits / Créditos

**@criss.repair_** — [YouTube: CrissRepair](https://www.youtube.com/@CrissRepair).

Desarrollado con asistencia de **Codex**. Developed with assistance from **Codex**.

This application coordinates a manual, tethered workflow. Original exploits, patchers and device libraries remain the work of the following authors; no endorsement is implied.

| Project | Authors / source | Role |
| --- | --- | --- |
| Legacy-iOS-Kit | [LukeZGD and contributors](https://github.com/LukeZGD/Legacy-iOS-Kit) | Distribution of the proven macOS device tools and portable libraries |
| 5sd7 | [AcePlayzGamesYT / StillDebugging and contributors](https://github.com/AcePlayzGamesYT/5sd7) | Firmware preparation method |
| surrealra1n | [pwnerblu and contributors](https://github.com/pwnerblu/surrealra1n) | Reference preparation and boot workflow |
| ipwnder_lite | [dora2ios; LukeZGD fork](https://github.com/LukeZGD/ipwnder_lite) | A7 pwnDFU; checkm8 work by axi0mX and contributors |
| idevicerestore | [libimobiledevice contributors](https://github.com/libimobiledevice/idevicerestore) | Restore engine; local optional iBEC preservation patch |
| libirecovery | [libimobiledevice; LukeZGD fork](https://github.com/LukeZGD/libirecovery) | Recovery/DFU transport |
| libimobiledevice, libusbmuxd, libimobiledevice-glue, libplist, libtatsu, libideviceactivation | [libimobiledevice contributors](https://github.com/libimobiledevice) | Device communication, tickets and official activation |
| iPatcher | [exploit3dguy; xerub and contributors](https://github.com/exploit3dguy/iPatcher) | iBSS/iBEC patching |
| Kernel64Patcher / seprmvr64 | [y08wilmarchive fork](https://github.com/y08wilmarchive/Kernel64Patcher); Ralph0045, mineek, xerub, Ploosh and contributors | iOS 7 kernel patches; embeds plooshfinder |
| img4lib | [xerub; LukeZGD fork](https://github.com/LukeZGD/img4lib) | Firmware container handling; includes original Apple libDER notices and lzfse |
| kerneldiff | [LukeZGD source](https://gist.github.com/LukeZGD/8c719b613ca28d6883552437bdd500de), based on Nathan's SSHRD_Script | Kernel binary patch generation |
| tsschecker | [tihmstar; 1Conan fork](https://github.com/1Conan/tsschecker) | Apple signing requests; includes libfragmentzip and jssy |
| libzip | [Dieter Baron, Thomas Klausner and contributors](https://libzip.org/) | ZIP support linked statically into the restore engine |
| Firmware keys | [The Apple Wiki](https://theapplewiki.com/) and surrealra1n contributors | Public iPhone6,2 7.1.2 component keys |

The interface, engine and boot helper are supplied under GPL-3.0-or-later. Bundled third-party components retain their own copyright and license terms. Full license texts, original notices and source archives accompany this file. See `upstream-sources.json`, revision files, `BUILD-NOTES.md`, `idevicerestore-conservar-ibec.patch` and `SourceArchives/`.

Apple firmware, device-specific tickets, account credentials and Apple trademarks are not part of the app's source release. macOS frameworks and system ZIP tools are supplied by the operating system.

## Maintenance additions (0.2.0)

The runtime downloads the Legacy-iOS-Kit jailbreak archives and iarchive/exploit3dguy SSH tools, original Apple 8.1 components, Fiona from julioverne and SCS WiFi Fix from DevTweaker. The pinned URLs and SHA-256 values are in `Maintenance/assets.json`. Apple firmware is not embedded in this app.

Additional credits: Pangu Team; Jay Freeman (saurik) for Cydia/Substrate; DevTweaker for SCS WiFi Fix; julioverne for Fiona; Dustin Howett and Sam Bingner for PreferenceLoader; planetbeing and xpwn contributors for hfsplus; tihmstar for partialZipBrowser; sshpass authors and LukeZGD for the macOS port; libusbmuxd authors for iproxy. PreferenceLoader 2.2.6 is included with its LGPL license and matching source. The maintenance root SSH listener binds only to localhost and is disabled after verification.
