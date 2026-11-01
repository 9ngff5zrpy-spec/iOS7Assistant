import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers
import Darwin

@MainActor @Observable final class CommandRunner {
    var process: Process?
    var demo = false
    func run(_ url: URL, _ args: [String], cwd: URL? = nil, environment: [String: String] = [:], timeout: TimeInterval = 60, hardware: Bool = false, input: Data? = nil, inputFile: URL? = nil, outputFile: URL? = nil, onOutput: @escaping (String) -> Void) async throws -> String {
        guard !hardware || !demo else { throw AssistantError("operationFailed", "Hardware access is blocked in demo mode.") }
        let p = Process(); p.executableURL = url; p.arguments = args; p.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "DYLD_LIBRARY_PATH"); env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        env.merge(environment, uniquingKeysWith: { _, new in new }); p.environment = env
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iOS7Assistant", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(UUID().uuidString + ".log")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file), reader = try FileHandle(forReadingFrom: file)
        var handles: [FileHandle] = []
        let inputTemp = dir.appendingPathComponent(UUID().uuidString + ".input")
        defer { process = nil; try? writer.close(); try? reader.close(); for handle in handles { try? handle.close() }; try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: inputTemp) }
        var source = inputFile
        if let input { try input.write(to: inputTemp); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inputTemp.path); source = inputTemp }
        if let source { let handle = try FileHandle(forReadingFrom: source); handles.append(handle); p.standardInput = handle }
        else { p.standardInput = FileHandle.nullDevice }
        if let outputFile {
            guard FileManager.default.createFile(atPath: outputFile.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw AssistantError("operationFailed", outputFile.path) }
            let handle = try FileHandle(forWritingTo: outputFile); handles.append(handle); p.standardOutput = handle
        } else { p.standardOutput = writer }
        p.standardError = writer; process = p
        try p.run()
        let start = Date(); var output = Data()
        while p.isRunning {
            if let new = try reader.readToEnd(), !new.isEmpty { output.append(new); onOutput(String(decoding: new, as: UTF8.self)) }
            if Date().timeIntervalSince(start) > timeout {
                p.terminate()
                try? await Task.sleep(for: .seconds(1))
                if p.isRunning { Darwin.kill(p.processIdentifier, SIGKILL) }
                throw AssistantError("timeout", url.lastPathComponent)
            }
            try await Task.sleep(for: .milliseconds(180))
        }
        if let tail = try reader.readToEnd(), !tail.isEmpty { output.append(tail); onOutput(String(decoding: tail, as: UTF8.self)) }
        let text = String(decoding: output, as: UTF8.self)
        guard p.terminationStatus == 0 else {
            for line in text.components(separatedBy: .newlines).reversed() {
                if let data = line.data(using: .utf8), let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let key = item["message"] as? String, key.hasPrefix("error:") { throw AssistantError(String(key.dropFirst(6)), String(text.suffix(1800))) }
            }
            throw AssistantError("toolFailed", url.lastPathComponent + "\n" + String(text.suffix(1800)))
        }
        return text
    }
    func stop() { process?.terminate() }
}

@MainActor @Observable final class AssistantModel {
    var language: String = UserDefaults.standard.string(forKey: "language") ?? (Locale.current.language.languageCode?.identifier == "es" ? "es" : "en") {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    var mode: WorkflowMode = .boot
    var step: WorkflowStep = .setup
    var isDemo = CommandLine.arguments.contains("--demo")
    var isBusy = false
    var isFlashing = false
    var statusKey = ""
    var errorKey: String?
    var errorDetail = ""
    var progress: Double?
    var log = ""
    var ios7: URL?
    var ios12: URL?
    var profile: URL?
    var profileValid = false
    var device: DeviceIdentity?
    var eraseConsent = false
    var restoreCompleted = false
    var bootVerified = false
    var activationConfirmed = false
    var reconnectNotice = false
    var timerRemaining = 0
    var timerTask: Task<Void, Never>?
    var maintenanceECID: String?
    var maintenanceStaged = false
    var extrasPendingBoot = false
    var extrasVerified = false
    var cydiaTest = false
    var wifiTest = false
    var sleepTest = false
    var proxyProcess: Process?
    var proxyLog: FileHandle?
    var proxyPort = 0
    var maintenanceSession: URL?
    let runner = CommandRunner()
    let resources: URL
    let tools: URL
    private let translations: [String: [String: String]]
    private var streamBuffer = ""
    init(resources: URL? = nil) {
        self.resources = resources ?? Bundle.main.resourceURL!
        tools = self.resources.appendingPathComponent("tools")
        let data = try? Data(contentsOf: self.resources.appendingPathComponent("Strings.json"))
        translations = data.flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
        if let path = UserDefaults.standard.string(forKey: "profile"), FileManager.default.fileExists(atPath: path + "/profile.json") { profile = URL(fileURLWithPath: path) }
        if isDemo { profileValid = true }
        if let index = CommandLine.arguments.firstIndex(of: "--resume-maintenance"),
           CommandLine.arguments.indices.contains(index + 1),
           let ecid = DeviceIdentity.number(CommandLine.arguments[index + 1]), ecid > 0, profile != nil {
            maintenanceECID = String(format: "0x%016llx", ecid)
            mode = .extras; step = .maintenanceConnect
        }
        if let index = CommandLine.arguments.firstIndex(of: "--resume-maintenance-boot"),
           CommandLine.arguments.indices.contains(index + 1),
           let ecid = DeviceIdentity.number(CommandLine.arguments[index + 1]), ecid > 0, profile != nil {
            maintenanceECID = String(format: "0x%016llx", ecid)
            mode = .extras; step = .dfu
        }
        if let index = CommandLine.arguments.firstIndex(of: "--resume-maintenance-final"),
           CommandLine.arguments.indices.contains(index + 1),
           let ecid = DeviceIdentity.number(CommandLine.arguments[index + 1]), ecid > 0, profile != nil {
            maintenanceECID = String(format: "0x%016llx", ecid)
            mode = .extras; maintenanceStaged = true; step = .extrasReady
        }
    }
    func t(_ key: String) -> String { translations[language]?[key] ?? translations["en"]?[key] ?? key }
    func append(_ text: String) {
        log += text; if log.count > 160_000 { log = String(log.suffix(140_000)) }
        streamBuffer += text
        while let range = streamBuffer.range(of: "\n") {
            let line = String(streamBuffer[..<range.lowerBound]); streamBuffer.removeSubrange(..<range.upperBound)
            if let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = event["message"] as? String, !message.hasPrefix("error:") { statusKey = message }
                if let value = event["progress"] as? Double { progress = value }
            }
        }
        if isFlashing && (text.contains("Waiting for device to enter restore mode") || text.contains("waiting for it to reappear")) { reconnectNotice = true }
        if isFlashing && (text.contains("Sending filesystem now") || text.contains("Sending BasebandData") || text.contains("Verifying restore")) { reconnectNotice = false }
    }
    func perform(_ body: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; errorKey = nil; errorDetail = ""; progress = nil
        Task { @MainActor in
            do { try await body() }
            catch { let e = error as? AssistantError; errorKey = e?.key ?? "operationFailed"; errorDetail = e?.detail ?? error.localizedDescription; append("\n\(error.localizedDescription)\n") }
            isBusy = false; isFlashing = false; progress = nil
        }
    }
    func command(_ name: String, _ args: [String], timeout: TimeInterval = 60, hardware: Bool = true, environment: [String: String] = [:], cwd: URL? = nil) async throws -> String {
        runner.demo = isDemo
        return try await runner.run(tools.appendingPathComponent(name), args, cwd: cwd, environment: environment, timeout: timeout, hardware: hardware) { [weak self] in self?.append($0) }
    }
    func chooseFirmware(isSeven: Bool) {
        let p = NSOpenPanel(); p.canChooseDirectories = false; p.allowsMultipleSelection = false; p.allowedContentTypes = [.data]; p.title = t(isSeven ? "firmware7" : "firmware12")
        if p.runModal() == .OK, let url = p.url { if isSeven { ios7 = url } else { ios12 = url } }
    }
    func prepareFiles() {
        if isDemo { perform { self.statusKey = "buildingIPSW"; try await Task.sleep(for: .milliseconds(400)); self.profileValid = true; self.statusKey = "profileReady" }; return }
        guard let ios7, let ios12 else { return }
        let panel = NSSavePanel(); panel.title = t("chooseOutput"); panel.nameFieldStringValue = "iPhone6,2-iOS7.1.2"; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        perform {
            _ = try await self.command("ios7-engine", ["prepare", "--ios7", ios7.path, "--ios12", ios12.path, "--output", target.path, "--tools", self.tools.path, "--resources", self.resources.path], timeout: 1800, hardware: false)
            self.profile = target; self.profileValid = true; UserDefaults.standard.set(target.path, forKey: "profile"); self.statusKey = "profileReady"
        }
    }
    func importProfile() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.title = t("profileLocation")
        guard p.runModal() == .OK, let root = p.url else { return }
        perform {
            if !self.isDemo { _ = try await self.command("ios7-engine", ["validate", "--profile", root.path], timeout: 180, hardware: false) }
            self.profile = root; self.profileValid = true; UserDefaults.standard.set(root.path, forKey: "profile"); self.statusKey = "profileReady"
        }
    }
    func begin() {
        perform {
            if !self.isDemo && !self.profileValid {
                guard let profile = self.profile else { throw AssistantError("profileMissing") }
                self.statusKey = "verifyingFiles"
                _ = try await self.command("ios7-engine", ["validate", "--profile", profile.path], timeout: 180, hardware: false)
                self.profileValid = true
            }
            if self.mode == .extras {
                if !self.isDemo {
                    let (id, chip) = try await self.normalDevice(expected: self.device?.ecid)
                    var state = try await self.command("ideviceinfo", ["-u", id, "-k", "ActivationState"], timeout: 12)
                    if !ActivationState.isActivated(state) {
                        _ = try await self.command("ideviceactivation", ["activate", "-b", "-u", id], timeout: 100)
                        state = try await self.command("ideviceinfo", ["-u", id, "-k", "ActivationState"], timeout: 15)
                    }
                    guard ActivationState.isActivated(state) else { throw AssistantError("activateBeforeExtras") }
                    self.activationConfirmed = true; self.maintenanceECID = chip
                    guard let profile = self.profile else { throw AssistantError("profileMissing") }
                    _ = try await self.command("ios7-engine", ["maintenance-prepare", "--profile", profile.path, "--tools", self.tools.path, "--resources", self.resources.path], timeout: 1500, hardware: false)
                } else { self.maintenanceECID = "0x0000000000001234"; self.activationConfirmed = true }
            }
            self.step = .dfu; self.statusKey = ""; self.eraseConsent = false; self.device = nil
        }
    }
    func query() async throws -> DeviceIdentity {
        if isDemo {
            let mode = step == .ibec || step == .ready ? "Recovery" : "DFU"
            let ibfl = step == .ibss ? "0x1d" : "0x1c"
            return try DeviceIdentity(query: "ECID: 0x1234\nPRODUCT: iPhone6,2\nMODEL: n53ap\nCPID: 0x8960\nBDID: 0x02\nMODE: \(mode)\nIBFL: \(ibfl)\nSRTG: iBoot-1704.10\nNONC: \(String(repeating: "a", count: 40))\nSNON: \(String(repeating: "b", count: 40))\nPWND: demo")
        }
        let output: String
        do { output = try await command("irecovery", (device.map { ["-i", $0.ecid] } ?? []) + ["-q"], timeout: 9) }
        catch { throw AssistantError("deviceMissing") }
        let current = try DeviceIdentity(query: output)
        if let device { try current.requireSame(as: device) }
        if let maintenanceECID, current.ecid != maintenanceECID { throw AssistantError("deviceChanged") }
        return current
    }
    func checkDFU() {
        timerTask?.cancel(); timerRemaining = 0
        perform { self.statusKey = "checkingDevice"; let current = try await self.query(); try current.requireBootROM(); self.device = current; self.step = .cable; self.statusKey = "" }
    }
    var deviceFolder: URL? { guard let root = profile, let device else { return nil }; return root.appendingPathComponent("devices/" + device.ecid) }
    func validateBootFiles() throws -> Bool {
        guard let folder = deviceFolder, let data = try? Data(contentsOf: folder.appendingPathComponent("hashes.json")), let hashes = try? JSONDecoder().decode([String: String].self, from: data) else { return false }
        for file in ["iBSS.img4", "iBEC.restore.img4", "iBEC.boot.img4", "DeviceTree.img4", "Kernelcache.img4"] {
            guard let hash = hashes[file], try PreparedProfile.hash(PreparedProfile.safePath(file, root: folder)) == hash else { throw AssistantError("invalidProfile", file) }
        }
        return true
    }
    func send(_ name: String) async throws {
        if isDemo { append("DEMO: \(name)\n"); try await Task.sleep(for: .milliseconds(250)); return }
        guard let folder = mode == .extras ? maintenanceRoot : deviceFolder, let device else { throw AssistantError("invalidProfile") }
        _ = try await command("irecovery", ["-i", device.ecid, "-f", folder.appendingPathComponent(name).path], timeout: 25)
    }
    func cableSwitched() {
        perform {
            let current = try await self.query(); try current.requireBootROM()
            if self.mode == .extras, !self.isDemo {
                guard let root = self.maintenanceRoot else { throw AssistantError("invalidProfile") }
                try MaintenanceProfile.load(at: root).validate(at: root)
            } else if try !self.isDemo && !self.validateBootFiles() {
                guard let root = self.profile else { throw AssistantError("invalidProfile") }
                _ = try await self.command("ios7-engine", ["personalize", "--profile", root.path, "--tools", self.tools.path, "--ecid", current.ecid, "--apnonce", current.apNonce, "--sepnonce", current.sepNonce], timeout: 180, hardware: false)
                guard try self.validateBootFiles() else { throw AssistantError("invalidProfile") }
            }
            self.statusKey = "exploiting"
            if !current.pwned && !self.isDemo {
                _ = try await self.command("ipwnder", ["-p"], timeout: 45)
                let confirmed = try await self.query(); try confirmed.requireBootROM()
                guard confirmed.pwned else { throw AssistantError("toolFailed", "pwnDFU") }
            }
            self.statusKey = "sendingIBSS"
            if !self.isDemo, let device = self.device { _ = try await self.command("irecovery", ["-i", device.ecid, "-f", self.resources.appendingPathComponent("dummy.bin").path], timeout: 12) }
            try await self.send("iBSS.img4"); self.step = .ibss; self.statusKey = ""
        }
    }
    func afterIBSS() {
        perform {
            self.statusKey = "settlingUSB"
            try await Task.sleep(for: .seconds(1))
            self.statusKey = "checkingDevice"; let current = try await self.query(); try current.requireIBSS()
            self.statusKey = "sendingIBEC"; try await self.send(self.mode == .extras ? "iBEC.img4" : (self.mode == .boot ? "iBEC.boot.img4" : "iBEC.restore.img4"))
            self.step = .ibec; self.statusKey = ""
        }
    }
    func afterIBEC() {
        perform {
            self.statusKey = "settlingUSB"
            try await Task.sleep(for: .seconds(1))
            self.statusKey = "checkingDevice"; let current = try await self.query(); try current.requireRecovery()
            if !self.isDemo { _ = try await self.command(self.mode == .extras ? "ios7-maintenance-boot" : "ios7-boot", ["--probe", "--ecid", current.ecid], timeout: 10) }
            self.step = .ready; self.statusKey = ""
        }
    }
    func startRestore() {
        guard mode == .restore, step == .ready, eraseConsent else { return }
        perform {
            let current = try await self.query(); try current.requireRecovery()
            if !self.isDemo { _ = try await self.command("ios7-boot", ["--probe", "--ecid", current.ecid], timeout: 10) }
            self.step = .restore; self.isFlashing = true; self.statusKey = "restoreTitle"; self.reconnectNotice = false
            if self.isDemo {
                self.append("DEMO: restore simulated; no hardware access\n")
                for i in 0...12 { self.progress = Double(i)/12; try await Task.sleep(for: .milliseconds(180)) }
            } else {
                guard let profile = self.profile else { throw AssistantError("invalidProfile") }
                let work = profile.appendingPathComponent("restore-session-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let output = try await self.command("idevicerestore", ["-eyk", "-i", current.ecid, "-C", work.appendingPathComponent("cache").path, "--logfile", work.appendingPathComponent("restore.log").path, profile.appendingPathComponent("prepared.ipsw").path], timeout: 2400, environment: ["CODEX_PRESERVE_IOS7_IBEC": "1"], cwd: work)
                let fileLog = (try? String(contentsOf: work.appendingPathComponent("restore.log"), encoding: .utf8)) ?? ""
                guard (output + fileLog).contains("Status: Restore Finished"), (output + fileLog).contains("DONE") else { throw AssistantError("notRestored") }
            }
            self.restoreCompleted = true; self.step = .done; self.statusKey = "restoreDone"
        }
    }
    func startBoot() {
        guard mode == .boot, step == .ready else { return }
        perform {
            let current = try await self.query(); try current.requireRecovery()
            self.step = .boot; self.statusKey = "bootTitle"
            if self.isDemo { self.append("DEMO: boot simulated; no hardware access\n"); try await Task.sleep(for: .milliseconds(500)); self.bootVerified = true }
            else {
                guard let folder = self.deviceFolder else { throw AssistantError("invalidProfile") }
                _ = try await self.command("ios7-boot", ["--ecid", current.ecid, folder.appendingPathComponent("DeviceTree.img4").path, folder.appendingPathComponent("Kernelcache.img4").path], timeout: 35)
            }
            self.step = .done; self.statusKey = self.bootVerified ? "bootDone" : "bootSent"
        }
    }
    func verifyBoot() {
        perform {
            if !self.isDemo {
                let output = try await self.command("ideviceinfo", ["-s", "-k", "ProductVersion"], timeout: 12)
                guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "7.1.2" else { throw AssistantError("bootNotReady") }
                let chip = try await self.command("ideviceinfo", ["-s", "-k", "UniqueChipID"], timeout: 12)
                guard let device = self.device, DeviceIdentity.number(chip.trimmingCharacters(in: .whitespacesAndNewlines)) == DeviceIdentity.number(device.ecid) else { throw AssistantError("deviceChanged") }
            }
            self.bootVerified = true; self.statusKey = "bootDone"
            if self.isDemo { self.activationConfirmed = true; self.statusKey = "activated" }
            if !self.isDemo {
                let (id, _) = try await self.normalDevice(expected: self.device?.ecid)
                let state = try await self.command("ideviceinfo", ["-u", id, "-k", "ActivationState"], timeout: 12)
                self.activationConfirmed = ActivationState.isActivated(state)
                if self.activationConfirmed { self.statusKey = "activated" }
            }
        }
    }
    func activate() {
        perform {
            if self.isDemo { self.activationConfirmed = true; self.statusKey = "activated"; return }
            let (id, _) = try await self.normalDevice(expected: self.device?.ecid)
            var state = try await self.command("ideviceinfo", ["-u", id, "-k", "ActivationState"], timeout: 12)
            if !ActivationState.isActivated(state) {
                _ = try await self.command("ideviceactivation", ["activate", "-b", "-u", id], timeout: 100)
                state = try await self.command("ideviceinfo", ["-u", id, "-k", "ActivationState"], timeout: 15)
            }
            guard ActivationState.isActivated(state) else { throw AssistantError("activateFailed") }
            self.activationConfirmed = true; self.statusKey = "activated"
        }
    }
    func firstBoot() { mode = .boot; step = .dfu; device = nil; restoreCompleted = false; eraseConsent = false; bootVerified = false; activationConfirmed = false; statusKey = ""; errorKey = nil }
    func reset() { guard !isBusy else { return }; stopProxy(); timerTask?.cancel(); timerRemaining = 0; step = .setup; device = nil; errorKey = nil; statusKey = ""; eraseConsent = false; restoreCompleted = false; bootVerified = false; activationConfirmed = false; maintenanceECID = nil; maintenanceStaged = false; extrasPendingBoot = false; extrasVerified = false; cydiaTest = false; wifiTest = false; sleepTest = false }
    func startTimer() {
        timerTask?.cancel(); timerRemaining = 20
        timerTask = Task { @MainActor in
            for remaining in stride(from: 20, through: 0, by: -1) {
                if Task.isCancelled { return }; timerRemaining = remaining
                if remaining > 0 { try? await Task.sleep(for: .seconds(1)) }
            }
        }
    }
    func saveLog() {
        let p = NSSavePanel(); p.nameFieldStringValue = "iOS7-Assistant.log"
        if p.runModal() == .OK, let url = p.url { try? log.write(to: url, atomically: true, encoding: .utf8) }
    }
}
