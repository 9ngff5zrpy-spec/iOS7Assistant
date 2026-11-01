# iOS 7 Assistant

A simple macOS assistant for installing and booting iOS 7.1.2 on the iPhone 5s Global (iPhone6,2 / n53ap), with English and Spanish instructions.

**Experimental release:** the complete GUI-driven restore and maintenance workflow still needs end-to-end hardware validation. The underlying manual method was successful on our device. Back up your data: installation erases the iPhone.

## What it does

- Creates a custom restore IPSW from original Apple iOS 7.1.2 and 12.5.8 firmware.
- Guides tethered installation and subsequent boots after shutdown.
- Provides Apple activation over USB, followed by guided Cydia, SCS WiFi Fix and Fiona installation.
- Pauses for manual USB reconnection after iBSS and iBEC and checks the expected device state before proceeding.
- Includes its tools and libraries; no Homebrew, Python or Rosetta installation is needed.

## Apple silicon and USB

On our Apple silicon Mac, we encountered DFU-entry and USB reconnection problems with direct Lightning-to-USB-C, associated with USB-C/Power Delivery negotiation and USB mode transitions. Our working procedure uses Lightning-to-USB-A with a USB-C adapter for DFU, then switches to a direct Lightning-to-USB-C cable for transfers. After iBSS and iBEC, reconnect the Mac end when prompted. The app waits briefly and checks each stage. These are observations from our setup; behavior may differ across Macs, cables and adapters.

## Requirements

- Apple silicon Mac running macOS 14 or later; Intel is not supported in this version.
- iPhone 5s Global, iPhone6,2 / n53ap; iPhone6,1 is not supported.
- Original iOS 7.1.2 and iOS 12.5.8 IPSWs, internet access, and at least 12 GB of free space.
- The Mac is required to boot after each shutdown. Do not enable a passcode or Touch ID.

## Usage

1. Open the app and prepare a reusable folder using the two original IPSWs. Apple firmware is not bundled.
2. Choose Install iOS 7 or Boot iOS 7. Follow the USB-A DFU instructions, switch to direct USB-C, and complete both manual reconnection pauses.
3. After the first boot, verify iOS and activate through Apple's service. If already activated, skip Wi-Fi setup.
4. Continue to Cydia & fixes. Follow the maintenance boot, final tethered boot and verification steps. Test Cydia, WPA2 Wi-Fi and sleep on the phone.

The app downloads maintenance assets from their upstream sources and verifies their hashes. The build is ad-hoc signed and not notarized; macOS may require Open Anyway in Privacy & Security.

## Credits

Project: **@criss.repair_** — [CrissRepair on YouTube](https://www.youtube.com/@CrissRepair). Developed with assistance from Codex.

Thanks to [Legacy-iOS-Kit](https://github.com/LukeZGD/Legacy-iOS-Kit), [5sd7](https://github.com/AcePlayzGamesYT/5sd7), [surrealra1n](https://github.com/pwnerblu/surrealra1n), libimobiledevice contributors, exploit and patcher authors, the Pangu team, Jay Freeman, [DevTweaker](https://github.com/DevTweaker/Tweak), Julio Verne and all other upstream contributors. Third-party licenses and source archives accompany the app.

## Español

La app guía la instalación y el arranque tethered de iOS 7.1.2 en iPhone6,2. Usa USB-A con adaptador para DFU y USB-C directo para las cargas; reconecta el extremo del Mac cuando la app lo indique. La instalación borra los datos. La interfaz permite español e inglés.
