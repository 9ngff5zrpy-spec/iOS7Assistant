import Foundation

@main struct WorkflowTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    static func rejects(_ key: String, _ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection: \(key)") }
        catch { expect((error as? AssistantError)?.key == key, "Unexpected error: \(error)") }
    }
    @MainActor static func wait(_ model: AssistantModel) async {
        for _ in 0..<300 {
            if !model.isBusy { expect(model.errorKey == nil, model.errorDetail); return }
            try? await Task.sleep(for: .milliseconds(30))
        }
        fatalError("Workflow timed out")
    }
    @MainActor static func reachReady(_ model: AssistantModel) async {
        model.begin(); await wait(model); expect(model.step == .dfu, "DFU first")
        model.checkDFU(); await wait(model); expect(model.step == .cable, "Cable swap")
        model.cableSwitched(); await wait(model); expect(model.step == .ibss, "Pause after iBSS")
        model.afterIBSS(); await wait(model); expect(model.step == .ibec, "Pause after iBEC")
        model.afterIBEC(); await wait(model); expect(model.step == .ready, "Recovery verified")
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let strings = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: root.appendingPathComponent("Strings.json")))
        expect(Set(strings["es"]!.keys) == Set(strings["en"]!.keys), "ES/EN parity")
        expect(!strings.values.flatMap(\.values).contains(""), "No empty translations")
        expect(ActivationState.isActivated("Activated\n"), "Activated state accepted")
        expect(!ActivationState.isActivated("Unactivated"), "Unactivated must not match")
        expect(!ActivationState.isActivated("Error: Activated"), "Error text must not count as activation")
        expect(AssistantModel.registryContainsECID(["children": [["unique-chip-id": Data([0x34, 0x12, 0, 0, 0, 0, 0, 0])]]], expected: 0x1234), "Ramdisk little endian ECID")
        expect(AssistantModel.registryContainsECID(["unique-chip-id": Data([0, 0, 0, 0, 0, 0, 0x12, 0x34])], expected: 0x1234), "Ramdisk big endian ECID")
        expect(!AssistantModel.registryContainsECID(["unique-chip-id": Data([0x43, 0x21])], expected: 0x1234), "Reject other ramdisk device")
        let query = "ECID: 0x1234\nPRODUCT: iPhone6,2\nMODEL: n53ap\nCPID: 0x8960\nBDID: 0x02\nMODE: DFU\nIBFL: 0x1c\nSRTG: iBoot-1704.10"
        let device = try DeviceIdentity(query: query); try device.requireBootROM()
        expect(device.ecid == "0x0000000000001234", "Normalized ECID")
        rejects("unsupportedDevice") { _ = try DeviceIdentity(query: query.replacingOccurrences(of: "iPhone6,2", with: "iPhone6,1")) }
        rejects("deviceMissing") { _ = try DeviceIdentity(query: "") }
        rejects("deviceChanged") { try device.requireSame(as: DeviceIdentity(query: query.replacingOccurrences(of: "0x1234", with: "0x4321"))) }
        rejects("needIBSS") { try device.requireIBSS() }
        let ibss = try DeviceIdentity(query: query.replacingOccurrences(of: "0x1c", with: "0x1d")); try ibss.requireIBSS()
        rejects("needDFU") { try ibss.requireBootROM() }
        rejects("needRecovery") { try ibss.requireRecovery() }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let reader = temp.appendingPathComponent("Maintenance/ios7-identity")
        try FileManager.default.createDirectory(at: reader.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old reader".utf8).write(to: reader)
        let oldMaintenance = try MaintenanceProfile.folderName(resources: temp)
        let unchangedMaintenance = try MaintenanceProfile.folderName(resources: temp)
        expect(oldMaintenance == unchangedMaintenance, "Unchanged reader reuses prepared maintenance")
        try Data("corrected reader".utf8).write(to: reader)
        let fixedMaintenance = try MaintenanceProfile.folderName(resources: temp)
        expect(oldMaintenance != fixedMaintenance, "Reader fix must not reuse a stale ramdisk")
        rejects("unsafePath") { _ = try PreparedProfile.safePath("../outside", root: temp) }
        rejects("unsafePath") { _ = try PreparedProfile.safePath("/etc/passwd", root: temp) }
        try FileManager.default.createSymbolicLink(at: temp.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        rejects("unsafePath") { _ = try PreparedProfile.safePath("link/passwd", root: temp) }
        rejects("invalidProfile") { try PreparedProfile(files: [:]).validate(at: temp) }
        let binary = Data([0, 255, 254, 10, 128, 0, 65])
        let copy = temp.appendingPathComponent("binary-output")
        let ioRunner = CommandRunner()
        _ = try await ioRunner.run(URL(fileURLWithPath: "/bin/cat"), [], input: binary, outputFile: copy) { _ in }
        let copied = try Data(contentsOf: copy)
        expect(copied == binary, "Binary SSH transfer must not decode stdout as text")
        let runner = CommandRunner(); runner.demo = true
        do { _ = try await runner.run(URL(fileURLWithPath: "/usr/bin/true"), [], hardware: true) { _ in }; fatalError("Demo hardware guard failed") }
        catch { expect((error as? AssistantError)?.key == "operationFailed", "Demo must block hardware") }
        let model = AssistantModel(resources: root); model.isDemo = true; model.profileValid = true
        await reachReady(model)
        model.startBoot(); await wait(model); expect(model.step == .done && model.bootVerified, "Boot flow")
        model.reset(); model.mode = .restore
        await reachReady(model)
        model.startRestore(); expect(!model.isBusy && model.step == .ready, "Restore requires erase consent")
        model.eraseConsent = true; model.startRestore(); await wait(model)
        expect(model.restoreCompleted && model.step == .done, "Restore flow")
        model.firstBoot(); expect(model.mode == .boot && model.step == .dfu, "First boot repeats cable procedure")
        expect(model.log.contains("DEMO: restore simulated; no hardware access"), "Simulation explicit")
        model.reset(); model.mode = .extras
        await reachReady(model)
        model.startMaintenance(); await wait(model); expect(model.step == .maintenanceConnect, "Maintenance boot pause")
        model.connectMaintenance(); await wait(model); expect(model.step == .extrasReady && model.maintenanceStaged, "Bootstrap staged before final boot")
        model.bootAfterMaintenance(); expect(model.mode == .boot && model.step == .dfu && model.extrasPendingBoot, "Final boot required")
        model.finishExtras(); expect(!model.isBusy && !model.extrasVerified, "Cannot finish before boot verification")
        await reachReady(model)
        model.startBoot(); await wait(model)
        model.verifyBoot(); await wait(model); expect(model.activationConfirmed, "Activated message after verification")
        model.finishExtras(); await wait(model); expect(model.extrasVerified && model.activationConfirmed, "Jailbreak workflow completed")
        print("PASS: \(checks) workflow, identity, profile and localization checks; no USB access.")
    }
}
