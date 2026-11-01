import Foundation
import Darwin

@MainActor extension AssistantModel {
    var maintenanceRoot: URL? {
        guard let profile, let name = try? MaintenanceProfile.folderName(resources: resources) else { return nil }
        return profile.appendingPathComponent(name)
    }

    func normalDevice(expected: String? = nil) async throws -> (String, String) {
        let ids = try await command("idevice_id", ["-l"], timeout: 10).split(whereSeparator: \.isNewline).map(String.init)
        if ids.isEmpty {
            let args = (expected.map { ["-i", $0] } ?? []) + ["-q"]
            if let output = try? await command("irecovery", args, timeout: 9), !output.isEmpty {
                let detected = try DeviceIdentity(query: output)
                if let expected, DeviceIdentity.number(expected) != DeviceIdentity.number(detected.ecid) { throw AssistantError("deviceChanged") }
                if detected.mode == "Recovery" { throw AssistantError("normalRequiredRecovery") }
                if detected.mode == "DFU" { throw AssistantError("normalRequiredDFU") }
            }
            throw AssistantError("deviceMissing")
        }
        guard ids.count == 1, let id = ids.first else { throw AssistantError("oneDevice") }
        let product = try await command("ideviceinfo", ["-u", id, "-k", "ProductType"], timeout: 12).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !product.isEmpty else { throw AssistantError("deviceMissing") }
        guard product == "iPhone6,2" else { throw AssistantError("unsupportedDevice", product) }
        let version = try await command("ideviceinfo", ["-u", id, "-k", "ProductVersion"], timeout: 12).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version == "7.1.2" else { throw AssistantError("bootNotReady", version) }
        let raw = try await command("ideviceinfo", ["-u", id, "-k", "UniqueChipID"], timeout: 12).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = DeviceIdentity.number(raw), number > 0 else { throw AssistantError("deviceMissing") }
        let chip = String(format: "0x%016llx", number)
        if let expected, DeviceIdentity.number(expected) != number { throw AssistantError("deviceChanged") }
        return (id, chip)
    }

    func beginExtras() {
        guard !isBusy else { return }
        mode = .extras; maintenanceStaged = false; extrasPendingBoot = false; extrasVerified = false
        cydiaTest = false; wifiTest = false; sleepTest = false
        begin()
    }

    func startMaintenance() {
        guard mode == .extras, step == .ready else { return }
        perform {
            let current = try await self.query(); try current.requireRecovery()
            self.statusKey = "maintenanceBooting"
            if !self.isDemo {
                guard let root = self.maintenanceRoot else { throw AssistantError("invalidProfile") }
                _ = try await self.command("ios7-maintenance-boot", ["--ecid", current.ecid, root.path], timeout: 45)
            }
            self.step = .maintenanceConnect; self.statusKey = ""
        }
    }

    func stopProxy() {
        proxyProcess?.terminate(); proxyProcess = nil
        try? proxyLog?.close(); proxyLog = nil; proxyPort = 0
    }
    func stopAllProcesses() { runner.stop(); stopProxy() }

    func startProxy(normal: Bool) async throws -> URL {
        guard !isDemo else { throw AssistantError("operationFailed", "No proxy is permitted in demo mode") }
        let id: String
        if normal { (id, _) = try await normalDevice(expected: maintenanceECID) }
        else {
            let ids = try await command("idevice_id", ["-l"], timeout: 10).split(whereSeparator: \.isNewline).map(String.init)
            guard ids.count == 1, let only = ids.first else { throw AssistantError("maintenanceMissing") }; id = only
        }
        guard let profile else { throw AssistantError("profileMissing") }
        let session = profile.appendingPathComponent("maintenance-session-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        maintenanceSession = session
        let log = session.appendingPathComponent("proxy.log")
        let devicePort = normal ? 22 : 44
        for _ in 0..<4 {
            stopProxy()
            proxyPort = try Self.availableLocalPort()
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: log); proxyLog = handle
            let process = Process(); process.executableURL = tools.appendingPathComponent("iproxy")
            process.arguments = ["-s", "127.0.0.1", "-u", id, "\(proxyPort):\(devicePort)"]
            process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
            var env = ProcessInfo.processInfo.environment; env.removeValue(forKey: "DYLD_LIBRARY_PATH"); env.removeValue(forKey: "DYLD_INSERT_LIBRARIES"); process.environment = env
            do { try process.run() } catch { stopProxy(); throw error }
            proxyProcess = process
            try await Task.sleep(for: .milliseconds(400))
            if process.isRunning {
                append("USB proxy: 127.0.0.1:\(proxyPort) -> device \(id):\(devicePort)\n")
                return session
            }
            let detail = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            append(detail); stopProxy()
            if !detail.localizedCaseInsensitiveContains("Address already in use") { throw AssistantError("proxyStartFailed", detail) }
        }
        throw AssistantError("proxyStartFailed", "Could not allocate a free local port after four attempts.")
    }

    static func availableLocalPort() throws -> Int {
        let socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw AssistantError("operationFailed", "socket") }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socketFD, $0, length) } }
        let named = withUnsafeMutablePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) } }
        Darwin.close(socketFD)
        guard bound == 0, named == 0 else { throw AssistantError("operationFailed", "local port") }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    func ssh(_ script: String, input: Data? = nil, inputFile: URL? = nil, outputFile: URL? = nil, timeout: TimeInterval = 40) async throws -> String {
        guard !isDemo, proxyPort > 0, let session = maintenanceSession else { throw AssistantError("operationFailed", "SSH is not connected") }
        let args = ["-e", "/usr/bin/ssh", "-F", "/dev/null", "-T", "-o", "StrictHostKeyChecking=accept-new", "-o", "UserKnownHostsFile=" + session.appendingPathComponent("known_hosts").path, "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", "-p", String(proxyPort), "root@127.0.0.1", script]
        runner.demo = isDemo
        return try await runner.run(tools.appendingPathComponent("sshpass"), args, environment: ["SSHPASS": "alpine"], timeout: timeout, hardware: true, input: input, inputFile: inputFile, outputFile: outputFile) { [weak self] in self?.append($0) }
    }

    func waitForSSH() async throws {
        var last: Error = AssistantError("maintenanceMissing")
        for _ in 0..<4 {
            do { _ = try await ssh("/bin/bash -c 'echo IOS7_SSH_READY'", timeout: 12); return }
            catch { last = error; try await Task.sleep(for: .seconds(1)) }
        }
        let proxyDetails = maintenanceSession.flatMap { try? String(contentsOf: $0.appendingPathComponent("proxy.log"), encoding: .utf8) } ?? ""
        if proxyDetails.contains("Connection refused") {
            throw AssistantError("deviceSSHNotReady", proxyDetails + "\n" + last.localizedDescription)
        }
        throw last
    }

    static func registryContainsECID(_ value: Any, expected: UInt64) -> Bool {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if key == "unique-chip-id", let data = child as? Data, !data.isEmpty, data.count <= 8 {
                    let big = data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                    let little = data.reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                    if big == expected || little == expected { return true }
                }
                if registryContainsECID(child, expected: expected) { return true }
            }
        } else if let array = value as? [Any] { return array.contains { registryContainsECID($0, expected: expected) } }
        return false
    }

    func connectMaintenance() {
        guard step == .maintenanceConnect, mode == .extras else { return }
        perform {
            if self.isDemo { self.maintenanceStaged = true; self.step = .extrasReady; return }
            guard let root = self.maintenanceRoot, let expected = self.maintenanceECID.flatMap(DeviceIdentity.number) else { throw AssistantError("invalidProfile") }
            try MaintenanceProfile.load(at: root).validate(at: root)
            self.statusKey = "maintenanceConnecting"
            let session = try await self.startProxy(normal: false); defer { self.stopProxy() }
            try await self.waitForSSH()
            // Included during offline preparation: no write/remount of the
            // read-only runtime ramdisk is needed to establish identity.
            let identity = try await self.ssh("/usr/bin/ios7-identity")
            let reported = identity.components(separatedBy: .newlines).first { $0.hasPrefix("ECID: ") }.flatMap { DeviceIdentity.number(String($0.dropFirst(6))) }
            guard reported == expected else { throw AssistantError("deviceChanged") }
            let preflight = """
            set -e
            /bin/mkdir -p /mnt1
            if ! /sbin/mount | /usr/bin/grep -q ' on /mnt1 '; then /sbin/mount_hfs -o ro /dev/disk0s1s1 /mnt1; fi
            /usr/bin/grep -q 11D257 /mnt1/System/Library/CoreServices/SystemVersion.plist
            if [ -e /mnt1/Applications/Cydia.app/Cydia ]; then echo CYDIA_ALREADY_PRESENT; exit 42; fi
            /sbin/mount -u -o rw /mnt1
            echo MAINTENANCE_SYSTEM_VERIFIED
            """
            self.statusKey = "maintenanceChecking"
            do { _ = try await self.ssh("/bin/bash -s", input: Data(preflight.utf8)) }
            catch {
                if (error as? AssistantError)?.detail.contains("CYDIA_ALREADY_PRESENT") == true { throw AssistantError("existingCydia") }
                throw error
            }
            self.statusKey = "maintenanceBackup"
            let backup = session.appendingPathComponent("system-before-bootstrap.tar")
            let backupScript = "while IFS= read -r p; do if [ -e \"/mnt1/$p\" ] || [ -L \"/mnt1/$p\" ]; then printf '%s\\n' \"$p\"; fi; done | /usr/bin/tar -cpf - --no-recursion -C /mnt1 -T -"
            _ = try await self.ssh(backupScript, inputFile: root.appendingPathComponent("backup-paths.txt"), outputFile: backup, timeout: 120)
            _ = try await self.runner.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-tf", backup.path], timeout: 15) { _ in }
            self.statusKey = "maintenanceInstalling"
            _ = try await self.ssh("/usr/bin/tar -xpf - -C /mnt1", inputFile: root.appendingPathComponent("bootstrap.tar"), timeout: 180)
            let verification = "set -e; test -s /mnt1/Applications/Cydia.app/Cydia; test -s /mnt1/private/ios7-bootstrap/var/lib/dpkg/status; test -s /mnt1/Library/LaunchDaemons/com.local.ios7-bootstrap.plist; /bin/cat /mnt1/private/ios7-bootstrap/install.sh; /bin/sync"
            let actual = try await self.ssh("/bin/bash -s", input: Data(verification.utf8))
            let intended = try String(contentsOf: root.appendingPathComponent("install.sh"), encoding: .utf8)
            guard actual.contains(intended.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw AssistantError("maintenanceVerifyFailed") }
            // This ramdisk has mount but no umount executable. Flush writes
            // and make the installed system read-only before leaving it.
            _ = try await self.ssh("set -e; /bin/sync; /sbin/mount -u -o ro /mnt1; /sbin/mount | /usr/bin/grep ' on /mnt1 ' | /usr/bin/grep -q 'read-only'", timeout: 30)
            self.maintenanceStaged = true; self.step = .extrasReady; self.statusKey = ""
        }
    }

    func bootAfterMaintenance() {
        guard maintenanceStaged, !isBusy else { return }
        extrasPendingBoot = true; bootVerified = false; extrasVerified = false
        firstBoot()
    }

    func finishExtras() {
        guard extrasPendingBoot, bootVerified, !extrasVerified else { return }
        perform {
            if self.isDemo { self.activationConfirmed = true; self.extrasVerified = true; self.statusKey = "extrasVerified"; return }
            self.statusKey = "extrasCompleting"
            let session = try await self.startProxy(normal: true); defer { self.stopProxy() }
            try await self.waitForSSH()
            let script = """
            set -e
            export PATH=/usr/bin:/bin:/usr/sbin:/sbin
            for ((i=0; i<45; i++)); do [ -f /var/root/ios7-bootstrap.done ] && break; sleep 2; done
            if [ ! -f /var/root/ios7-bootstrap.done ]; then tail -60 /var/log/ios7-bootstrap.log; exit 1; fi
            dpkg-query -W -f='${Package} ${Version} ${Status}\\n' cydia mobilesubstrate com.saurik.substrate.safemode preferenceloader com.julioverne.fiona com.scs.wififix
            test -s /Applications/Cydia.app/Cydia
            """
            let result = try await self.ssh("/bin/bash -s", input: Data(script.utf8), timeout: 120)
            for package in ["cydia", "mobilesubstrate", "com.saurik.substrate.safemode", "preferenceloader", "com.julioverne.fiona", "com.scs.wififix"] {
                guard result.split(separator: "\n").contains(where: { $0.hasPrefix(package + " ") && $0.hasSuffix("install ok installed") }) else { throw AssistantError("maintenanceVerifyFailed", package) }
            }
            let fionaFile = session.appendingPathComponent("fiona.plist")
            _ = try await self.ssh("/bin/cat /var/mobile/Library/Preferences/com.julioverne.fiona.plist", outputFile: fionaFile)
            let fiona = try PropertyListSerialization.propertyList(from: Data(contentsOf: fionaFile), options: [], format: nil) as? [String: Any]
            guard fiona?["Enabled"] as? Bool == true else { throw AssistantError("maintenanceVerifyFailed", "Fiona") }
            let (id, _) = try await self.normalDevice(expected: self.maintenanceECID)
            let state = try await self.command("ideviceinfo", ["-u", id, "-k", "ActivationState"], timeout: 12)
            guard ActivationState.isActivated(state) else { throw AssistantError("activateFailed") }
            let sshConfig = session.appendingPathComponent("sshd.plist")
            _ = try await self.ssh("/bin/cat /Library/LaunchDaemons/com.openssh.sshd.plist", outputFile: sshConfig)
            var daemon = try PropertyListSerialization.propertyList(from: Data(contentsOf: sshConfig), options: [], format: nil) as? [String: Any] ?? [:]
            guard daemon["Label"] as? String == "com.openssh.sshd" else { throw AssistantError("maintenanceVerifyFailed", "SSH daemon") }
            daemon["Disabled"] = true
            let data = try PropertyListSerialization.data(fromPropertyList: daemon, format: .xml, options: 0)
            _ = try await self.ssh("set -e; cat > /Library/LaunchDaemons/com.openssh.sshd.plist.ios7-new; chmod 644 /Library/LaunchDaemons/com.openssh.sshd.plist.ios7-new; chown 0:0 /Library/LaunchDaemons/com.openssh.sshd.plist.ios7-new; mv -f /Library/LaunchDaemons/com.openssh.sshd.plist.ios7-new /Library/LaunchDaemons/com.openssh.sshd.plist", input: data)
            let cleanup = """
            set -e
            /bin/launchctl unload /Library/LaunchDaemons/com.local.ios7-bootstrap.plist 2>/dev/null || true
            rm -f /Library/LaunchDaemons/com.local.ios7-bootstrap.plist
            rm -rf /private/ios7-bootstrap
            sync
            (sleep 2; /bin/launchctl unload /Library/LaunchDaemons/com.openssh.sshd.plist) </dev/null >/dev/null 2>&1 &
            echo MAINTENANCE_CLEANUP_DONE
            """
            let done = try await self.ssh("/bin/bash -s", input: Data(cleanup.utf8))
            guard done.contains("MAINTENANCE_CLEANUP_DONE") else { throw AssistantError("maintenanceVerifyFailed") }
            self.activationConfirmed = true; self.extrasVerified = true; self.statusKey = "extrasVerified"
        }
    }
}
