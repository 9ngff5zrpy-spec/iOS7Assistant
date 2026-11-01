import Foundation
import CryptoKit

struct AssistantError: LocalizedError {
    let key: String
    let detail: String
    init(_ key: String, _ detail: String = "") { self.key = key; self.detail = detail }
    var errorDescription: String? { detail.isEmpty ? key : "\(key): \(detail)" }
}

struct DeviceIdentity: Equatable, Codable {
    let ecid: String
    let product: String
    let model: String
    let mode: String
    let ibfl: String
    let srtg: String
    let pwned: Bool
    let apNonce: String
    let sepNonce: String
    init(query: String) throws {
        var values: [String: String] = [:]
        for line in query.components(separatedBy: .newlines) {
            guard let separator = line.range(of: ": ") else { continue }
            values[String(line[..<separator.lowerBound])] = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let raw = values["ECID"], let value = Self.number(raw), value > 0 else { throw AssistantError("deviceMissing") }
        ecid = String(format: "0x%016llx", value)
        product = values["PRODUCT"] ?? ""; model = values["MODEL"] ?? ""
        mode = values["MODE"] ?? ""; ibfl = values["IBFL"] ?? ""; srtg = values["SRTG"] ?? ""
        pwned = !(values["PWND"] ?? "").isEmpty
        apNonce = values["NONC"] ?? ""; sepNonce = values["SNON"] ?? ""
        guard product == "iPhone6,2", model == "n53ap", values["CPID"] == "0x8960", values["BDID"] == "0x02" else { throw AssistantError("unsupportedDevice", product + " / " + model) }
    }
    static func number(_ raw: String) -> UInt64? {
        raw.lowercased().hasPrefix("0x") ? UInt64(raw.dropFirst(2), radix: 16) : UInt64(raw)
    }
    func requireSame(as expected: DeviceIdentity) throws {
        guard ecid == expected.ecid else { throw AssistantError("deviceChanged") }
    }
    func requireBootROM() throws {
        guard mode == "DFU", srtg == "iBoot-1704.10", ibfl == "0x1c" else { throw AssistantError("needDFU") }
    }
    func requireIBSS() throws {
        guard mode == "DFU", ibfl == "0x1d" else { throw AssistantError("needIBSS") }
    }
    func requireRecovery() throws {
        guard mode == "Recovery" else { throw AssistantError("needRecovery") }
    }
}

struct PreparedProfile: Codable {
    var formatVersion: Int = 1
    var product: String = "iPhone6,2"
    var board: String = "n53ap"
    var version: String = "7.1.2"
    var build: String = "11D257"
    var files: [String: String]
    func validate(at root: URL) throws {
        guard formatVersion == 1, product == "iPhone6,2", board == "n53ap", version == "7.1.2", build == "11D257" else { throw AssistantError("invalidProfile") }
        for file in files.keys {
            let url = try Self.safePath(file, root: root)
            guard FileManager.default.fileExists(atPath: url.path), try Self.hash(url) == files[file] else { throw AssistantError("invalidProfile", file) }
        }
        for required in ["templates/iBSS.im4p", "templates/iBEC.restore.im4p", "templates/iBEC.boot.im4p", "templates/DeviceTree.raw", "templates/Kernelcache.im4p", "BuildManifest.plist", "prepared.ipsw"] {
            guard files[required] != nil else { throw AssistantError("invalidProfile", required) }
        }
    }
    static func safePath(_ name: String, root: URL) throws -> URL {
        guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), !name.isEmpty else { throw AssistantError("unsafePath", name) }
        let result = root.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard result.path.hasPrefix(base) else { throw AssistantError("unsafePath", name) }
        return result
    }
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct MaintenanceProfile: Codable {
    var formatVersion = 1
    var product = "iPhone6,2"
    var files: [String: String]
    static func folderName(resources: URL) throws -> String {
        // Changing the embedded reader must invalidate previously prepared
        // ramdisks, even when their own file hashes are still valid.
        "maintenance-v3-" + String(try PreparedProfile.hash(resources.appendingPathComponent("Maintenance/ios7-identity")).prefix(16))
    }
    static func load(at root: URL) throws -> Self { try JSONDecoder().decode(Self.self, from: Data(contentsOf: root.appendingPathComponent("maintenance.json"))) }
    func validate(at root: URL) throws {
        guard formatVersion == 1, product == "iPhone6,2" else { throw AssistantError("invalidProfile") }
        for name in ["iBSS.img4", "iBEC.img4", "DeviceTree.img4", "Kernelcache.img4", "RestoreRamdisk.img4", "bootstrap.tar", "backup-paths.txt", "install.sh"] {
            guard let hash = files[name], try PreparedProfile.hash(PreparedProfile.safePath(name, root: root)) == hash else { throw AssistantError("invalidProfile", name) }
        }
    }
}

enum ActivationState {
    static func isActivated(_ output: String) -> Bool { output.trimmingCharacters(in: .whitespacesAndNewlines) == "Activated" }
}

enum WorkflowMode: String, CaseIterable { case boot, restore, extras }
enum WorkflowStep: Int, CaseIterable {
    case setup, dfu, cable, ibss, ibec, ready, restore, boot, done, maintenanceConnect, extrasReady
    var titleKey: String { ["setupTitle", "dfuTitle", "cableTitle", "ibssTitle", "ibecTitle", "readyTitle", "restoreTitle", "bootTitle", "doneTitle", "maintenanceConnectTitle", "extrasReadyTitle"][rawValue] }
}
