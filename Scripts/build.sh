#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build Vendor/bin
swiftc -O -target arm64-apple-macosx14.0 -module-cache-path Build/ModuleCache Sources/Domain.swift Sources/Engine.swift Sources/MaintenanceEngine.swift -o Vendor/bin/ios7-engine
swiftc -O -target arm64-apple-macosx14.0 -module-cache-path Build/ModuleCache Sources/Domain.swift Sources/AssistantModel.swift Sources/MaintenanceModel.swift Sources/AssistantApp.swift -o Build/iOS7Assistant
python3 Scripts/bundle.py
