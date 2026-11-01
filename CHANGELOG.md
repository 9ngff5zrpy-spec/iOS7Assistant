# Changelog

## 0.2.3

- Finish maintenance by syncing and remounting the installed system read-only; the ramdisk does not include an umount executable. Verified this cleanup on the target phone after staging the bootstrap.
- Fix the ECID reader's IOKit path for the iOS 8 maintenance ramdisk (`Versions/A/IOKit`).
- Report the exact dynamic-loader error if either supported framework path fails.
- Key prepared maintenance folders by the embedded reader's hash so a fixed app cannot silently reuse a ramdisk containing the old reader.
- Include the native reader build script in the source archive.

## 0.2.2

- Include the native ECID reader directly in the maintenance ramdisk.
- Avoid the incompatible ioreg/ncurses dependency.
- Remove the attempt to remount the read-only running ramdisk for uploading the reader.
- Prepare a separate maintenance-v2 folder so existing cached images cannot silently retain the old behavior.

## 0.2.1

- Distinguish DFU/Recovery, absent devices and multiple connected devices.
