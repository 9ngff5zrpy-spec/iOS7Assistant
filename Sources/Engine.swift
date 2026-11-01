import Foundation
import Darwin

// This executable performs file preparation only. It never opens a USB device.
func emit(_ key: String, _ progress: Double? = nil) {
    var object: [String: Any] = ["message": key]
    if let progress { object["progress"] = progress }
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
}
func tool(_ path: URL, _ args: [String], cwd: URL? = nil) throws -> String {
    let p = Process(); p.executableURL = path; p.arguments = args; p.currentDirectoryURL = cwd
    var env = ProcessInfo.processInfo.environment
    env.removeValue(forKey: "DYLD_LIBRARY_PATH"); env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
    env["COPYFILE_DISABLE"] = "1"
    p.environment = env
    let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: log) }
    let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
    p.standardOutput = handle; p.standardError = handle
    try p.run(); p.waitUntilExit(); try handle.synchronize()
    let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    guard p.terminationStatus == 0 else { throw AssistantError("toolFailed", path.lastPathComponent + "\n" + String(output.suffix(1800))) }
    return output
}
func plist(_ data: Data) throws -> [String: Any] {
    guard let value = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw AssistantError("invalidFirmware") }; return value
}
func archiveManifest(_ url: URL) throws -> [String: Any] {
    // plist bytes must remain untouched; unzip to a private temporary file.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try tool(URL(fileURLWithPath: "/usr/bin/unzip"), ["-q", url.path, "BuildManifest.plist", "-d", dir.path])
    return try plist(Data(contentsOf: dir.appendingPathComponent("BuildManifest.plist")))
}
func identity(_ manifest: [String: Any], version: String) throws -> [String: Any] {
    guard manifest["ProductVersion"] as? String == version,
          (manifest["SupportedProductTypes"] as? [String])?.contains("iPhone6,2") == true,
          let identities = manifest["BuildIdentities"] as? [[String: Any]],
          let found = identities.first(where: { b in
              let info = b["Info"] as? [String: Any]
              return info?["DeviceClass"] as? String == "n53ap" && (info?["Variant"] as? String ?? "").contains("Erase")
          }), let entries = found["Manifest"] as? [String: Any] else { throw AssistantError("invalidFirmware", version) }
    return entries
}
func component(_ entries: [String: Any], _ name: String) throws -> String {
    guard let entry = entries[name] as? [String: Any], let info = entry["Info"] as? [String: Any], let path = info["Path"] as? String else { throw AssistantError("missingComponent", name) }
    guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw AssistantError("unsafePath", path) }
    return path
}
func validateArchivePaths(_ url: URL) throws {
    let text = try tool(URL(fileURLWithPath: "/usr/bin/unzip"), ["-Z1", url.path])
    for name in text.split(separator: "\n") {
        guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), !name.contains("\\") else { throw AssistantError("unsafePath", String(name)) }
    }
}
func prepare(ios7: URL, ios12: URL, root: URL, tools: URL, resources: URL) throws {
    guard !FileManager.default.fileExists(atPath: root.path) else { throw AssistantError("outputExists") }
    emit("checkingFirmware", 0.02)
    let firmwareHashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: resources.appendingPathComponent("firmware-hashes.json")))
    for (version, file) in [("7.1.2", ios7), ("12.5.8", ios12)] {
        guard let expected = firmwareHashes[version], try PreparedProfile.hash(file) == expected else { throw AssistantError("invalidFirmware", version + " SHA-256") }
    }
    let m7 = try archiveManifest(ios7), m12 = try archiveManifest(ios12)
    let a = try identity(m7, version: "7.1.2"), b = try identity(m12, version: "12.5.8")
    guard m7["ProductBuildVersion"] as? String == "11D257", m12["ProductBuildVersion"] as? String == "16H88" else { throw AssistantError("invalidFirmware") }
    try validateArchivePaths(ios7); try validateArchivePaths(ios12)
    let parent = root.deletingLastPathComponent()
    let free = try FileManager.default.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as? NSNumber
    guard (free?.int64Value ?? 0) > 12_000_000_000 else { throw AssistantError("diskSpace") }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let work = root.appendingPathComponent(".building"), source = work.appendingPathComponent("ios7"), dest = work.appendingPathComponent("ios12"), tmp = work.appendingPathComponent("patches"), templates = root.appendingPathComponent("templates")
    for d in [source, dest, tmp, templates] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    var committed = false
    defer { if !committed { try? FileManager.default.removeItem(at: root) } }
    emit("extractingFirmware", 0.08)
    let selected = try ["iBSS", "iBEC", "RestoreDeviceTree", "RestoreKernelCache", "RestoreRamDisk", "OS"].map { try component(a, $0) }
    _ = try tool(URL(fileURLWithPath: "/usr/bin/unzip"), ["-q", ios7.path] + selected + ["-d", source.path])
    _ = try tool(URL(fileURLWithPath: "/usr/bin/unzip"), ["-q", ios12.path, "-d", dest.path])
    let keys = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: resources.appendingPathComponent("firmware-keys.json")))
    let expected = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: resources.appendingPathComponent("expected-patches.json")))
    func execute(_ name: String, _ args: [String]) throws { _ = try tool(tools.appendingPathComponent(name), args, cwd: tmp) }
    func raw(_ part: String, _ key: String, _ name: String) throws -> URL {
        let out = tmp.appendingPathComponent(name)
        try execute("img4", ["-i", source.appendingPathComponent(try component(a, part)).path, "-o", out.path, "-k", keys[key]!]); return out
    }
    func checked(_ file: URL, key: String) throws {
        guard let digest = expected[key], try PreparedProfile.hash(file) == digest else { throw AssistantError("patchMismatch", key) }
    }
    emit("patchingLoaders", 0.30)
    let ibss = try raw("iBSS", "ibss", "iBSS.raw"), ibec = try raw("iBEC", "ibec", "iBEC.raw")
    let ibssPatched = tmp.appendingPathComponent("iBSS.patched"), restore = tmp.appendingPathComponent("iBEC.restore"), boot = tmp.appendingPathComponent("iBEC.boot")
    try execute("ipatcher", [ibss.path, ibssPatched.path]); try checked(ibssPatched, key: "ibss")
    try execute("ipatcher", [ibec.path, restore.path, "-b", "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1"]); try checked(restore, key: "ibecRestore")
    try execute("ipatcher", [ibec.path, boot.path, "-b", "-v rd=disk0s1s1"])
    try execute("img4", ["-i", ibssPatched.path, "-o", templates.appendingPathComponent("iBSS.im4p").path, "-A", "-T", "ibss"])
    try execute("img4", ["-i", restore.path, "-o", templates.appendingPathComponent("iBEC.restore.im4p").path, "-A", "-T", "ibec"])
    try execute("img4", ["-i", boot.path, "-o", templates.appendingPathComponent("iBEC.boot.im4p").path, "-A", "-T", "ibec"])
    let dt = try raw("RestoreDeviceTree", "dtre", "DeviceTree.raw")
    try FileManager.default.copyItem(at: dt, to: templates.appendingPathComponent("DeviceTree.raw"))
    var data = try Data(contentsOf: dt); let old = Data("content-protect".utf8), replacement = Data("content-protecV".utf8)
    guard data.range(of: old) != nil else { throw AssistantError("patchMismatch", "DeviceTree") }
    while let range = data.range(of: old) { data.replaceSubrange(range, with: replacement) }
    try data.write(to: dt)
    try execute("img4", ["-i", dt.path, "-o", dest.appendingPathComponent(try component(b, "RestoreDeviceTree")).path, "-A", "-T", "rdtr"])
    emit("patchingKernel", 0.48)
    let kernel = try raw("RestoreKernelCache", "krnl", "kernel.raw"), patched = tmp.appendingPathComponent("kernel.patched"), diff = tmp.appendingPathComponent("kernel.bpatch"), im4p = tmp.appendingPathComponent("kernel.im4p")
    try execute("Kernel64Patcher2", [kernel.path, patched.path, "-u", "7", "-m", "7", "-e", "7", "-f", "7", "-k"]); try checked(patched, key: "kernel")
    try execute("img4", ["-i", source.appendingPathComponent(try component(a, "RestoreKernelCache")).path, "-o", im4p.path, "-k", keys["krnl"]!, "-D"])
    try execute("kerneldiff", [kernel.path, patched.path, diff.path])
    try execute("img4", ["-i", im4p.path, "-o", templates.appendingPathComponent("Kernelcache.im4p").path, "-P", diff.path, "-T", "rkrn"])
    func replace(_ input: URL, _ name: String) throws {
        let path = dest.appendingPathComponent(try component(b, name)); try FileManager.default.removeItem(at: path); try FileManager.default.copyItem(at: input, to: path)
    }
    try replace(templates.appendingPathComponent("iBSS.im4p"), "iBSS")
    try replace(templates.appendingPathComponent("iBEC.restore.im4p"), "iBEC")
    try replace(templates.appendingPathComponent("Kernelcache.im4p"), "RestoreKernelCache")
    try execute("img4", ["-i", source.appendingPathComponent(try component(a, "RestoreRamDisk")).path, "-o", dest.appendingPathComponent(try component(b, "RestoreRamDisk")).path, "-k", keys["rdsk"]!, "-D"])
    emit("buildingIPSW", 0.66)
    try replace(source.appendingPathComponent(try component(a, "OS")), "OS")
    try FileManager.default.copyItem(at: dest.appendingPathComponent("BuildManifest.plist"), to: root.appendingPathComponent("BuildManifest.plist"))
    _ = try tool(URL(fileURLWithPath: "/usr/bin/zip"), ["-0", "-q", "-r", root.appendingPathComponent("prepared.ipsw").path, "."], cwd: dest)
    emit("verifyingFiles", 0.92)
    var hashes: [String: String] = [:]
    let files = ["BuildManifest.plist", "prepared.ipsw", "templates/iBSS.im4p", "templates/iBEC.restore.im4p", "templates/iBEC.boot.im4p", "templates/DeviceTree.raw", "templates/Kernelcache.im4p"]
    for file in files { hashes[file] = try PreparedProfile.hash(root.appendingPathComponent(file)) }
    let profile = PreparedProfile(files: hashes)
    try JSONEncoder().encode(profile).write(to: root.appendingPathComponent("profile.json"), options: .atomic)
    try FileManager.default.removeItem(at: work); committed = true; emit("profileReady", 1)
}
func personalize(root: URL, tools: URL, ecid: String, ap: String, sep: String) throws {
    guard DeviceIdentity.number(ecid) != nil, ap.count == 40, sep.count == 40, (ap + sep).allSatisfy({ $0.isHexDigit }) else { throw AssistantError("invalidNonce") }
    let profile = try JSONDecoder().decode(PreparedProfile.self, from: Data(contentsOf: root.appendingPathComponent("profile.json")))
    // Full IPSW validation happens on prepare/import; validate small templates here.
    for (file, hash) in profile.files where file != "prepared.ipsw" {
        guard try PreparedProfile.hash(PreparedProfile.safePath(file, root: root)) == hash else { throw AssistantError("invalidProfile", file) }
    }
    let device = root.appendingPathComponent("devices/" + ecid), temp = root.appendingPathComponent(".ticket-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    emit("requestingTicket", 0.1)
    _ = try tool(tools.appendingPathComponent("tsschecker"), ["-d", "iPhone6,2", "-i", "12.5.8", "-m", root.appendingPathComponent("BuildManifest.plist").path, "-e", ecid, "--apnonce", ap, "--sepnonce", sep, "-s", "-b", "--save-path", temp.path])
    guard let blob = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "shsh2" }), let ticket = try plist(Data(contentsOf: blob))["ApImg4Ticket"] as? Data, ticket.count > 4000 else { throw AssistantError("ticketFailed") }
    let ticketFile = temp.appendingPathComponent("ticket.im4m"); try ticket.write(to: ticketFile)
    try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
    func pack(_ source: String, _ target: String, _ type: String, plain: Bool = false) throws {
        var args = ["-i", root.appendingPathComponent(source).path, "-o", device.appendingPathComponent(target).path, "-T", type, "-M", ticketFile.path]
        if plain { args.append("-A") }
        _ = try tool(tools.appendingPathComponent("img4"), args)
    }
    emit("preparingBoot", 0.65)
    try pack("templates/iBSS.im4p", "iBSS.img4", "ibss")
    try pack("templates/iBEC.restore.im4p", "iBEC.restore.img4", "ibec")
    try pack("templates/iBEC.boot.im4p", "iBEC.boot.img4", "ibec")
    try pack("templates/DeviceTree.raw", "DeviceTree.img4", "rdtr", plain: true)
    try pack("templates/Kernelcache.im4p", "Kernelcache.img4", "rkrn")
    try ticket.write(to: device.appendingPathComponent("ticket.im4m"))
    let manifest = try ["iBSS.img4", "iBEC.restore.img4", "iBEC.boot.img4", "DeviceTree.img4", "Kernelcache.img4"].reduce(into: [String: String]()) { $0[$1] = try PreparedProfile.hash(device.appendingPathComponent($1)) }
    try JSONEncoder().encode(manifest).write(to: device.appendingPathComponent("hashes.json"), options: .atomic)
    emit("bootFilesReady", 1)
}
func engineMain() throws {
    var args = Array(CommandLine.arguments.dropFirst()); guard !args.isEmpty else { throw AssistantError("arguments") }
    let command = args.removeFirst(); var values: [String: String] = [:]
    while args.count >= 2 { let key = args.removeFirst(); values[key] = args.removeFirst() }
    func url(_ key: String) throws -> URL { guard let text = values[key] else { throw AssistantError("arguments", key) }; return URL(fileURLWithPath: text).standardizedFileURL }
    if command == "prepare" { try prepare(ios7: url("--ios7"), ios12: url("--ios12"), root: url("--output"), tools: url("--tools"), resources: url("--resources")) }
    else if command == "personalize" { try personalize(root: url("--profile"), tools: url("--tools"), ecid: values["--ecid"] ?? "", ap: values["--apnonce"] ?? "", sep: values["--sepnonce"] ?? "") }
    else if command == "validate" { let root = try url("--profile"); try JSONDecoder().decode(PreparedProfile.self, from: Data(contentsOf: root.appendingPathComponent("profile.json"))).validate(at: root); emit("profileReady", 1) }
    else if command == "maintenance-prepare" { try prepareMaintenance(root: url("--profile"), tools: url("--tools"), resources: url("--resources")) }
    else { throw AssistantError("arguments", command) }
}
@main struct EngineMain {
    static func main() {
        do { try engineMain() } catch {
            let e = error as? AssistantError; emit("error:" + (e?.key ?? "operationFailed")); FileHandle.standardError.write(Data((e?.detail ?? error.localizedDescription).utf8)); exit(1)
        }
    }
}
