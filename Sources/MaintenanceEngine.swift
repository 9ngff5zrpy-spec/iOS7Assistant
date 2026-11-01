import Foundation

private struct MaintenanceAsset: Decodable { let file: String; let url: String; let sha256: String }
private struct MaintenanceComponent: Decodable { let name: String; let file: String; let path: String; let key: String; let sha256: String }
private struct MaintenanceAssets: Decodable {
    let firmwareURL: String
    let components: [MaintenanceComponent]
    let assets: [MaintenanceAsset]
    let sshURL: String
    let sshTarSHA256: String
    let preferenceLoaderSHA256: String
}

// Offline preparation and verified downloads only: this executable never opens USB.
func prepareMaintenance(root: URL, tools: URL, resources: URL) throws {
    let fm = FileManager.default
    let configRoot = resources.appendingPathComponent("Maintenance")
    let config = try JSONDecoder().decode(MaintenanceAssets.self, from: Data(contentsOf: configRoot.appendingPathComponent("assets.json")))
    let destination = try PreparedProfile.safePath(MaintenanceProfile.folderName(resources: resources), root: root)
    if fm.fileExists(atPath: destination.path) {
        try MaintenanceProfile.load(at: destination).validate(at: destination)
        emit("maintenancePrepared", 1); return
    }
    let cache = try PreparedProfile.safePath("maintenance-downloads", root: root)
    try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    let work = root.appendingPathComponent(".maintenance-" + UUID().uuidString)
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: work) }
    func execute(_ name: String, _ args: [String], cwd: URL? = nil) throws {
        _ = try tool(tools.appendingPathComponent(name), args, cwd: cwd ?? work)
    }
    func verified(_ name: String, sha: String, fetch: (URL) throws -> Void) throws -> URL {
        let file = try PreparedProfile.safePath(name, root: cache)
        if fm.fileExists(atPath: file.path), try PreparedProfile.hash(file) == sha { return file }
        let temporary = work.appendingPathComponent(UUID().uuidString)
        try fetch(temporary)
        guard try PreparedProfile.hash(temporary) == sha else { throw AssistantError("maintenanceHash", name) }
        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
        try fm.moveItem(at: temporary, to: file); return file
    }
    func download(_ url: String, to: URL) throws {
        guard url.hasPrefix("https://") else { throw AssistantError("unsafePath", url) }
        _ = try tool(URL(fileURLWithPath: "/usr/bin/curl"), ["--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "20", "--max-time", "300", "--output", to.path, url])
    }
    emit("maintenanceDownloading", 0.02)
    var assets: [String: URL] = [:]
    for (index, asset) in config.assets.enumerated() {
        assets[asset.file] = try verified(asset.file, sha: asset.sha256) { try download(asset.url, to: $0) }
        emit("maintenanceDownloading", 0.03 + 0.25 * Double(index + 1) / Double(config.assets.count))
    }
    let preferenceLoader = configRoot.appendingPathComponent("preferenceloader.deb")
    guard try PreparedProfile.hash(preferenceLoader) == config.preferenceLoaderSHA256 else { throw AssistantError("maintenanceHash", "PreferenceLoader") }
    assets["preferenceloader.deb"] = preferenceLoader
    let sshTar = try verified("iram.tar", sha: config.sshTarSHA256) { target in
        let zip = work.appendingPathComponent("iram.zip")
        try download(config.sshURL, to: zip)
        try validateArchivePaths(zip)
        let out = work.appendingPathComponent("ssh-extracted")
        _ = try tool(URL(fileURLWithPath: "/usr/bin/unzip"), ["-q", zip.path, "iram.tar", "-d", out.path])
        try fm.copyItem(at: out.appendingPathComponent("iram.tar"), to: target)
    }
    let prepared = work.appendingPathComponent("prepared")
    try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
    emit("maintenanceFirmware", 0.30)
    for (index, c) in config.components.enumerated() {
        let original = try verified(c.file, sha: c.sha256) { target in
            try execute("pzb", ["-g", c.path, "-o", target.lastPathComponent, config.firmwareURL], cwd: target.deletingLastPathComponent())
        }
        let raw = work.appendingPathComponent(c.name + ".raw")
        let out = prepared.appendingPathComponent(c.name + ".img4")
        let ticket = configRoot.appendingPathComponent("IM4M7")
        if c.name == "iBSS" || c.name == "iBEC" {
            try execute("img4", ["-i", original.path, "-o", raw.path, "-k", c.key])
            let patched = work.appendingPathComponent(c.name + ".patched")
            _ = try tool(URL(fileURLWithPath: "/usr/bin/bspatch"), [raw.path, patched.path, configRoot.appendingPathComponent(c.file + ".patch").path])
            try execute("img4", ["-i", patched.path, "-o", out.path, "-A", "-T", c.name.lowercased(), "-M", ticket.path])
        } else if c.name == "Kernelcache" {
            try execute("img4", ["-i", original.path, "-o", raw.path, "-k", c.key, "-D"])
            try execute("img4", ["-i", raw.path, "-o", out.path, "-T", "rkrn", "-M", ticket.path])
        } else {
            try execute("img4", ["-i", original.path, "-o", raw.path, "-k", c.key])
            if c.name == "RestoreRamdisk" {
                try execute("hfsplus", [raw.path, "grow", "50000000"])
                try execute("hfsplus", [raw.path, "untar", sshTar.path])
                try execute("hfsplus", [raw.path, "untar", configRoot.appendingPathComponent("sbplist.tar").path])
                try execute("hfsplus", [raw.path, "add", configRoot.appendingPathComponent("ios7-identity").path, "usr/bin/ios7-identity"])
                try execute("hfsplus", [raw.path, "chmod", "755", "usr/bin/ios7-identity"])
            }
            try execute("img4", ["-i", raw.path, "-o", out.path, "-A", "-T", c.name == "DeviceTree" ? "rdtr" : "rdsk", "-M", ticket.path])
        }
        emit("maintenanceFirmware", 0.30 + 0.35 * Double(index + 1) / Double(config.components.count))
    }
    emit("maintenanceBootstrap", 0.70)
    let stage = work.appendingPathComponent("bootstrap")
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    for name in ["freeze.tar.gz", "nopatcyh.tar", "panguaxe.tar", "openssh.tar.gz", "openssl.tar.gz"] {
        let paths = try tool(URL(fileURLWithPath: "/usr/bin/tar"), ["-tf", assets[name]!.path])
        for path in paths.split(separator: "\n") {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw AssistantError("unsafePath", String(path)) }
        }
        _ = try tool(URL(fileURLWithPath: "/usr/bin/tar"), ["-xpf", assets[name]!.path, "-C", stage.path])
    }
    let payload = stage.appendingPathComponent("private/ios7-bootstrap")
    try fm.createDirectory(at: payload, withIntermediateDirectories: true)
    let variable = stage.appendingPathComponent("private/var")
    for path in ["mobile", "Keychains"] {
        let item = variable.appendingPathComponent(path)
        if fm.fileExists(atPath: item.path) { try fm.removeItem(at: item) }
    }
    try fm.moveItem(at: variable, to: payload.appendingPathComponent("var"))
    if let enumerator = fm.enumerator(at: stage, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
        var remove: [URL] = []
        for case let file as URL in enumerator where file.lastPathComponent.lowercased().contains("patcyh") { remove.append(file) }
        for file in remove.sorted(by: { $0.path.count > $1.path.count }) { try? fm.removeItem(at: file) }
    }
    let cydiaDaemon = stage.appendingPathComponent("Library/LaunchDaemons/com.saurik.Cydia.Startup.plist")
    try fm.moveItem(at: cydiaDaemon, to: payload.appendingPathComponent("Cydia.Startup.plist"))
    let sshDaemon = stage.appendingPathComponent("Library/LaunchDaemons/com.openssh.sshd.plist")
    var sshPlist = try plist(Data(contentsOf: sshDaemon))
    var sockets = sshPlist["Sockets"] as? [String: Any] ?? [:]
    var listeners = sockets["Listeners"] as? [String: Any] ?? [:]
    listeners["SockNodeName"] = "127.0.0.1"; sockets["Listeners"] = listeners; sshPlist["Sockets"] = sockets
    try PropertyListSerialization.data(fromPropertyList: sshPlist, format: .xml, options: 0).write(to: sshDaemon)
    let debs = payload.appendingPathComponent("debs")
    try fm.createDirectory(at: debs, withIntermediateDirectories: true)
    let cydia = work.appendingPathComponent("substrate")
    try fm.createDirectory(at: cydia, withIntermediateDirectories: true)
    _ = try tool(URL(fileURLWithPath: "/usr/bin/tar"), ["-xpf", assets["cydiasubstrate.tar"]!.path, "-C", cydia.path])
    for name in ["mobilesubstrate_fix.deb", "com.saurik.substrate.safemode_fix.deb"] {
        try fm.copyItem(at: cydia.appendingPathComponent("private/var/root/Media/Cydia/AutoInstall/" + name), to: debs.appendingPathComponent(name))
    }
    for name in ["fiona.deb", "preferenceloader.deb"] { try fm.copyItem(at: assets[name]!, to: debs.appendingPathComponent(name)) }
    try validateArchivePaths(assets["wifi-fix.zip"]!)
    _ = try tool(URL(fileURLWithPath: "/usr/bin/unzip"), ["-q", assets["wifi-fix.zip"]!.path, "scs-wifi-fix-ios7_1.0.1_iphoneos-arm.deb", "-d", debs.path])
    try fm.copyItem(at: configRoot.appendingPathComponent("install.sh"), to: payload.appendingPathComponent("install.sh"))
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: payload.appendingPathComponent("install.sh").path)
    try fm.copyItem(at: configRoot.appendingPathComponent("installer.plist"), to: stage.appendingPathComponent("Library/LaunchDaemons/com.local.ios7-bootstrap.plist"))
    fm.createFile(atPath: stage.appendingPathComponent(".cydia_no_stash").path, contents: Data())
    _ = try tool(URL(fileURLWithPath: "/usr/bin/tar"), ["--uid", "0", "--gid", "0", "--uname", "root", "--gname", "wheel", "-cpf", prepared.appendingPathComponent("bootstrap.tar").path, "-C", stage.path, "."])
    var paths: [String] = []
    if let enumerator = fm.enumerator(at: stage, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
        for case let file as URL in enumerator {
            let relative = String(file.path.dropFirst(stage.path.count + 1))
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if (values.isRegularFile == true || values.isSymbolicLink == true) && !relative.hasPrefix("private/ios7-bootstrap/") { paths.append(relative) }
        }
    }
    try paths.sorted().joined(separator: "\n").appending("\n").write(to: prepared.appendingPathComponent("backup-paths.txt"), atomically: true, encoding: .utf8)
    try fm.copyItem(at: configRoot.appendingPathComponent("install.sh"), to: prepared.appendingPathComponent("install.sh"))
    var hashes: [String: String] = [:]
    for file in ["iBSS.img4", "iBEC.img4", "DeviceTree.img4", "Kernelcache.img4", "RestoreRamdisk.img4", "bootstrap.tar", "backup-paths.txt", "install.sh"] { hashes[file] = try PreparedProfile.hash(prepared.appendingPathComponent(file)) }
    try JSONEncoder().encode(MaintenanceProfile(files: hashes)).write(to: prepared.appendingPathComponent("maintenance.json"), options: .atomic)
    try fm.moveItem(at: prepared, to: destination)
    emit("maintenancePrepared", 1)
}
