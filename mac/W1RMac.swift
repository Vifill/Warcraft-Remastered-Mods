// Warcraft I & II: Remastered for Mac — sets up a free Wine (Sikarugir, built from CrossOver's
// open-source Wine) with WineMetalGL, installs the Windows Battle.net, and adds the mods.
import CryptoKit
import SwiftUI

// MARK: - Paths and pinned downloads

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let data = home.appendingPathComponent("Library/Application Support/Warcraft1Mac")
    static let wrapper = data.appendingPathComponent("Wrapper.app")
    static let mods = data.appendingPathComponent("mods")
    static let cache = data.appendingPathComponent("downloads")
    static let installedFlag = data.appendingPathComponent(".installed")
    static let log = data.appendingPathComponent("install.log")
    static let ini = mods.appendingPathComponent("w1r_mods.ini")
    static let ini2 = mods.appendingPathComponent("w2r_mods.ini")
    static let launcher = wrapper.appendingPathComponent("Contents/MacOS/Sikarugir")
    static let engine = wrapper.appendingPathComponent("Contents/SharedSupport/wine")
    static let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix")
    static let driveC = prefix.appendingPathComponent("drive_c")
    static let battleNet = driveC.appendingPathComponent("Program Files (x86)/Battle.net/Battle.net.exe")
    static let resources = Bundle.main.resourceURL!
}

struct Download {
    let file: String
    let url: String
    let sha256: String?
}

enum Downloads {
    static let template = Download(
        file: "Template-1.0.22.tar.xz",
        url: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.22.tar.xz",
        sha256: "02a8e9e1140121128188bce5380b5adf187fd6084fd2cb266e22cc8ab50e5155")
    static let engine = Download(
        file: "WS12WineSikarugir11.0_1.tar.xz",
        url: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz",
        sha256: "67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e")
    static let wineMetalGL = Download(
        file: "winemetalgl-3.2.0-x86_64.tar.gz",
        url: "https://github.com/metalsharp/WineMetalGL/releases/download/winemetalgl-3.2.0/winemetalgl-3.2.0-x86_64.tar.gz",
        sha256: "ce3aea78dd93c85312c262772c00e70d51c330b3c94a41a28bc0035f4f0a2513")
    static let battleNet = Download(
        file: "Battle.net-Setup.exe",
        url: "https://www.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live",
        sha256: nil)
}

struct SetupError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Helpers

@discardableResult
func run(_ exe: String, _ args: [String], wait: Bool = true) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    guard wait else { return "" }
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(decoding: out, as: UTF8.self)
    appendLog("$ \(exe) \(args.joined(separator: " "))\n\(text)")
    if p.terminationStatus != 0 {
        throw SetupError(message: "\(URL(fileURLWithPath: exe).lastPathComponent) failed (\(p.terminationStatus)). See install.log.")
    }
    return text
}

func runAsync(_ exe: String, _ args: [String]) async throws {
    _ = try await Task.detached { try run(exe, args) }.value
}

func appendLog(_ s: String) {
    let line = Data((s.hasSuffix("\n") ? s : s + "\n").utf8)
    if let h = try? FileHandle(forWritingTo: Paths.log) {
        h.seekToEndOfFile(); h.write(line); try? h.close()
    } else {
        try? line.write(to: Paths.log)
    }
}

func sha256(of url: URL) throws -> String {
    let h = try FileHandle(forReadingFrom: url)
    defer { try? h.close() }
    var hasher = SHA256()
    while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func fetch(_ d: Download) async throws -> URL {
    let dest = Paths.cache.appendingPathComponent(d.file)
    let fm = FileManager.default
    if let want = d.sha256, fm.fileExists(atPath: dest.path), (try? sha256(of: dest)) == want { return dest }
    let (tmp, response) = try await URLSession.shared.download(from: URL(string: d.url)!)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw SetupError(message: "Download failed: \(d.file)")
    }
    try? fm.removeItem(at: dest)
    try fm.moveItem(at: tmp, to: dest)
    if let want = d.sha256, try sha256(of: dest) != want {
        try? fm.removeItem(at: dest)
        throw SetupError(message: "\(d.file) did not match its expected checksum, so it was not used.")
    }
    return dest
}

/// Set `"key"="value"` inside `[section]` of a Wine .reg file, adding the section if needed.
func setRegValue(_ text: String, section: String, key: String, value: String) -> String {
    var lines = text.components(separatedBy: "\n")
    let entry = "\"\(key)\"=\"\(value)\""
    if let s = lines.firstIndex(where: { $0.hasPrefix("[\(section)]") }) {
        var i = s + 1
        while i < lines.count, lines[i].hasPrefix("#") { i += 1 }
        var j = i
        while j < lines.count, !lines[j].isEmpty, !lines[j].hasPrefix("[") {
            if lines[j].hasPrefix("\"\(key)\"=") { lines[j] = entry; return lines.joined(separator: "\n") }
            j += 1
        }
        lines.insert(entry, at: i)
        return lines.joined(separator: "\n")
    }
    let stamp = Int(Date().timeIntervalSince1970)
    return text + (text.hasSuffix("\n") ? "" : "\n") + "\n[\(section)] \(stamp)\n\(entry)\n"
}

// MARK: - Games

struct Campaign {
    let key: String       // key in GlobalSave.json "missionsCompleted"
    let label: String
    let missions: Int
}

struct Game: Identifiable {
    let id: String
    let name: String              // also the name of its saves subfolder
    let saveFolder: String        // under "Saved Games" inside Wine
    let installFolder: String     // under Program Files (x86)
    let exes: [String]            // programs that need WineMetalGL
    let campaigns: [Campaign]

    static let wc1 = Game(id: "wc1", name: "Warcraft I", saveFolder: "WarcraftRemastered",
                          installFolder: "Warcraft I Remastered", exes: ["Warcraft.exe"],
                          campaigns: [Campaign(key: "orc", label: "Orc", missions: 12),
                                      Campaign(key: "human", label: "Human", missions: 12)])
    static let wc2 = Game(id: "wc2", name: "Warcraft II", saveFolder: "Warcraft2Remastered",
                          installFolder: "Warcraft II Remastered",
                          exes: ["Warcraft II.exe", "Warcraft II Map Editor.exe"],
                          campaigns: [Campaign(key: "todOrc", label: "Orc", missions: 14),
                                      Campaign(key: "todHuman", label: "Human", missions: 14),
                                      Campaign(key: "bdpOrc", label: "Dark Portal Orc", missions: 12),
                                      Campaign(key: "bdpHuman", label: "Dark Portal Human", missions: 12)])
    static let all = [wc1, wc2]

    /// Which game a saves folder belongs to, from its GlobalSave.json or its name.
    static func detect(_ folder: URL) -> Game {
        let text = (try? String(contentsOf: folder.appendingPathComponent("GlobalSave.json"), encoding: .utf8)) ?? ""
        if text.contains("todOrc") || text.contains("bdp") { return wc2 }
        if text.contains("\"orc\"") { return wc1 }
        return folder.lastPathComponent.contains("2") ? wc2 : wc1
    }
}

// MARK: - Saved games

/// Saved games live outside the Wine environment so Uninstall and reinstall keep them:
/// `Saves.base/<game name>`, linked from each game's save folder inside Wine.
enum Saves {
    static let base = Paths.home.appendingPathComponent("Library/Application Support/Warcraft1Mac Saves")
    static func dir(_ g: Game) -> URL { base.appendingPathComponent(g.name) }

    struct Source: Identifiable {
        let game: Game
        let folder: URL
        let done: [String: Int]
        var id: String { folder.path }
        var total: Int { done.values.reduce(0, +) }
        var summary: String {
            game.campaigns.map { "\($0.label) \(done[$0.key] ?? 0) of \($0.missions)" }.joined(separator: ", ") + " missions"
        }
    }

    /// `drive_c/users/<user>/Saved Games/<game folder>` for a drive_c (real user folders only;
    /// Sikarugir/CrossOver add links such as <mac user> -> Sikarugir).
    static func saveFolders(in driveC: URL, _ g: Game) -> [URL] {
        let fm = FileManager.default
        let users = driveC.appendingPathComponent("users")
        let names = (try? fm.contentsOfDirectory(atPath: users.path)) ?? []
        return names.filter { name in
            name != "Public" && !name.hasPrefix(".") &&
                (try? fm.destinationOfSymbolicLink(atPath: users.appendingPathComponent(name).path)) == nil
        }.map { users.appendingPathComponent("\($0)/Saved Games/\(g.saveFolder)") }
    }

    static func gameFolder(_ g: Game) -> URL? { saveFolders(in: Paths.driveC, g).first }

    static func progress(of folder: URL, _ g: Game) -> Source? {
        let file = folder.appendingPathComponent("GlobalSave.json")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let end = text.range(of: "}}"),
              let data = String(text[..<end.upperBound]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let done = json["missionsCompleted"] as? [String: Any] else { return nil }
        var counts: [String: Int] = [:]
        for c in g.campaigns { counts[c.key] = done[c.key] as? Int ?? 0 }
        return Source(game: g, folder: folder, done: counts)
    }

    /// Version 1.0 kept Warcraft I saves directly in `base`; move them into `base/Warcraft I`.
    static func migrateLayout() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: base.path)) ?? []
        let gameDirs = Set(Game.all.map(\.name))
        let old = names.filter { !$0.hasPrefix(".") && !gameDirs.contains($0) }
        guard !old.isEmpty else { return }
        let target = dir(.wc1)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for n in old {
            let dst = target.appendingPathComponent(n)
            if fm.fileExists(atPath: dst.path) { continue }
            try? fm.moveItem(at: base.appendingPathComponent(n), to: dst)
        }
        appendLog("saves: moved \(old.count) items into \(target.path)")
    }

    /// Point the game's save folder at `dir(g)`, moving any saves already there into it.
    static func link(_ g: Game) throws {
        let fm = FileManager.default
        guard let game = gameFolder(g) else { return }
        let target = dir(g)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        if let dest = try? fm.destinationOfSymbolicLink(atPath: game.path) {
            if dest == target.path { return }
            try fm.removeItem(at: game)                     // stale link (e.g. old layout)
        } else {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: game.path, isDirectory: &isDir), isDir.boolValue {
                let files = try fm.contentsOfDirectory(atPath: game.path)
                if !files.isEmpty {
                    let existing = (try? fm.contentsOfDirectory(atPath: target.path)) ?? []
                    if existing.contains(where: { !$0.hasPrefix("backup-") }) {
                        try backupCurrent(g, reason: "before-merge")
                    }
                    for f in files {
                        let dst = target.appendingPathComponent(f)
                        try? fm.removeItem(at: dst)
                        try fm.moveItem(at: game.appendingPathComponent(f), to: dst)
                    }
                }
                try fm.removeItem(at: game)
            } else if fm.fileExists(atPath: game.path) {
                try fm.removeItem(at: game)
            }
        }
        try fm.createDirectory(at: game.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: game, withDestinationURL: target)
        appendLog("saves: linked \(game.path) -> \(target.path)")
    }

    static func linkAll() {
        migrateLayout()
        for g in Game.all { try? link(g) }
    }

    /// Copy the current saves into `dir(g)/backup-<date>-<reason>`.
    @discardableResult
    static func backupCurrent(_ g: Game, reason: String) throws -> URL? {
        let fm = FileManager.default
        let d = dir(g)
        let files = ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { !$0.hasPrefix("backup-") }
        guard !files.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let backup = d.appendingPathComponent("backup-\(f.string(from: Date()))-\(reason)")
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in files { try fm.copyItem(at: d.appendingPathComponent(name), to: backup.appendingPathComponent(name)) }
        return backup
    }

    static func importFrom(_ folder: URL, _ g: Game) throws {
        let fm = FileManager.default
        let d = dir(g)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        try backupCurrent(g, reason: "before-import")
        for name in try fm.contentsOfDirectory(atPath: folder.path) where !name.hasPrefix(".") && !name.hasPrefix("backup-") {
            let src = folder.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let dst = d.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
        appendLog("saves: imported \(g.name) from \(folder.path)")
    }

    /// Save folders for `g` in other Wine setups: wrappers and prefixes in ~/Wine, ~/Games and
    /// Applications, CrossOver and Whisky bottles, and ~/.wine.
    static func otherSources(_ g: Game) -> [Source] {
        let fm = FileManager.default
        let home = Paths.home
        var driveCs: [URL] = [home.appendingPathComponent(".wine/drive_c")]
        func children(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }
                .map { dir.appendingPathComponent($0) }
        }
        for root in ["Wine", "Games", "Applications"].map({ home.appendingPathComponent($0) })
            + [URL(fileURLWithPath: "/Applications")] {
            for item in children(root) {
                driveCs += [item.appendingPathComponent("drive_c"),
                            item.appendingPathComponent("prefix/drive_c"),
                            item.appendingPathComponent("Contents/SharedSupport/prefix/drive_c"),
                            item.appendingPathComponent("Contents/drive_c")]
            }
        }
        for bottles in ["Library/Application Support/CrossOver/Bottles",
                        "Library/Containers/com.isaacmarovitz.Whisky/Bottles"] {
            driveCs += children(home.appendingPathComponent(bottles)).map { $0.appendingPathComponent("drive_c") }
        }
        let ours = Paths.driveC.resolvingSymlinksInPath().path
        let mine = dir(g).resolvingSymlinksInPath().path
        var seen = Set<String>()
        var found: [Source] = []
        for c in driveCs where fm.fileExists(atPath: c.path) && c.resolvingSymlinksInPath().path != ours {
            for folder in saveFolders(in: c, g) {
                let real = folder.resolvingSymlinksInPath().path
                guard real != mine, !seen.contains(real), let s = progress(of: folder, g) else { continue }
                seen.insert(real)
                found.append(s)
            }
        }
        return found.sorted { $0.total > $1.total }
    }
}

// MARK: - Wine environment

/// Registry settings every install needs; applied at install and to existing installs on launch.
/// With `dryRun` only reports whether anything would change.
@discardableResult
func applyRegistry(dryRun: Bool = false) throws -> Bool {
    let reg = Paths.prefix.appendingPathComponent("user.reg")
    let before = try String(contentsOf: reg, encoding: .utf8)
    var text = setRegValue(before, section: "Environment", key: "SDL_AUDIODRIVER", value: "directsound")
    for g in Game.all {
        for exe in g.exes {
            let section = "Software\\\\Wine\\\\AppDefaults\\\\\(exe)\\\\DllOverrides"
            text = setRegValue(text, section: section, key: "opengl32", value: "native")
        }
    }
    for exe in ["Warcraft.exe", "Warcraft II.exe"] {        // the mod DLL (stand-in VERSION.dll)
        let section = "Software\\\\Wine\\\\AppDefaults\\\\\(exe)\\\\DllOverrides"
        text = setRegValue(text, section: section, key: "version", value: "native,builtin")
    }
    guard text != before else { return false }
    if !dryRun {
        try text.write(to: reg, atomically: true, encoding: .utf8)
        appendLog("registry: updated")
    }
    return true
}

func gameRunning() -> Bool {
    (try? run("/usr/bin/pgrep", ["-f", "Warcraft.exe -uid|Warcraft II.exe"])) != nil
}

/// Stop this install's Wine (Battle.net and its background Agent) and wait until it is gone.
func stopWine() async {
    _ = try? run(Paths.launcher.path, ["WSS-wineserverkill"])
    for _ in 0..<30 where wineRunning() { try? await Task.sleep(nanoseconds: 500_000_000) }
}

/// Keep the data folder's copies of files shipped in the app (sync script, mod DLL) current with
/// this app version; sync_mods.sh then carries the DLL into the game folders.
func refreshBundledFiles() {
    guard FileManager.default.fileExists(atPath: Paths.data.path) else { return }
    try? FileManager.default.createDirectory(at: Paths.mods, withIntermediateDirectories: true)
    for (name, dir) in [("sync_mods.sh", Paths.data), ("VERSION.dll", Paths.mods)] {
        let src = Paths.resources.appendingPathComponent(name)
        let dst = dir.appendingPathComponent(name)
        guard let new = try? Data(contentsOf: src), (try? Data(contentsOf: dst)) != new else { continue }
        try? new.write(to: dst, options: .atomic)
        appendLog("updated \(name) from the app")
        if name == "sync_mods.sh" {
            // an older copy may still be running and holding the lock; replace it
            _ = try? run("/usr/bin/pkill", ["-f", "Warcraft1Mac/sync_mods.sh"])
            try? FileManager.default.removeItem(at: Paths.data.appendingPathComponent(".sync.pid"))
            if wineRunning() {
                _ = try? run("/bin/sh", ["-c", "nohup /bin/sh \"$HOME/Library/Application Support/Warcraft1Mac/sync_mods.sh\" >/dev/null 2>&1 &"])
            }
        }
    }
}

func wineRunning() -> Bool {
    (try? run("/usr/bin/pgrep", ["-f", "Warcraft1Mac/Wrapper.app.*wineserver"])) != nil
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var ghostFix = true { didSet { saveSettings() } }
    @Published var middlePan = true { didSet { saveSettings() } }
    @Published var astar = true { didSet { saveSettings() } }
    @Published var middlePan2 = true { didSet { saveSettings() } }
    @Published var astar2 = true { didSet { saveSettings() } }
    @Published var status = ""
    @Published var busy = false
    @Published var step = 0
    @Published var installed = FileManager.default.fileExists(atPath: Paths.installedFlag.path)
    @Published var showUninstall = false
    @Published var importOffer: Saves.Source?
    let totalSteps = 9
    private var loading = true

    init() {
        loadSettings()
        loading = false
        refreshBundledFiles()
        if installed && !FileManager.default.fileExists(atPath: Paths.ini2.path) { saveSettings() }
        if installed && !wineRunning() { prepareEnvironment() }
        status = installed ? "Ready. Click Play to open Battle.net." :
            "Click Install. Setup downloads about 300 MB and takes a few minutes."
        // Only offer imports once the environment is up to date (needs Wine stopped).
        if installed && !wineRunning() { checkImportOffer() }
    }

    /// Bring an installed environment up to date with this app version (registry settings for
    /// both games, saves layout and links). Only while Wine is stopped.
    func prepareEnvironment() {
        do { try applyRegistry() } catch { appendLog("registry: \(error.localizedDescription)") }
        Saves.linkAll()
    }

    private let declinedFile = Paths.data.appendingPathComponent(".import-declined")

    /// Offer saves from another Wine setup when it has more progress than ours.
    func checkImportOffer() {
        let declined = (try? String(contentsOf: declinedFile, encoding: .utf8)) ?? ""
        for g in Game.all {
            let ours = Saves.progress(of: Saves.dir(g), g)?.total ?? 0
            if let s = Saves.otherSources(g).first(where: { $0.total > ours && !declined.contains($0.folder.path + "\n") }) {
                importOffer = s
                return
            }
        }
        importOffer = nil
    }

    func declineImport(_ s: Saves.Source) {
        let declined = ((try? String(contentsOf: declinedFile, encoding: .utf8)) ?? "") + s.folder.path + "\n"
        try? declined.write(to: declinedFile, atomically: true, encoding: .utf8)
    }

    func importSaves(from folder: URL, game g: Game) {
        if (try? run("/usr/bin/pgrep", ["-f", "Warcraft.exe -uid|Warcraft II.exe"])) != nil {
            status = "Quit the game first, then import again (it rewrites its saves when it exits)."
            return
        }
        do {
            try Saves.importFrom(folder, g)
            if !wineRunning() { try? Saves.link(g) }
            let p = Saves.progress(of: Saves.dir(g), g)
            status = "\(g.name) saves imported" + (p.map { " (\($0.summary))." } ?? ".") +
                " Your previous saves were backed up in the saves folder."
        } catch {
            status = "Import failed: \(error.localizedDescription)"
        }
    }

    func importManually() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a Warcraft I or II saves folder (WarcraftRemastered or Warcraft2Remastered)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        guard files.contains(where: { $0 == "GlobalSave.json" || $0.hasSuffix(".sav") }) else {
            status = "That folder has no Warcraft saves (GlobalSave.json or .sav files)."
            return
        }
        importSaves(from: url, game: Game.detect(url))
    }

    func loadSettings() {
        func reader(_ url: URL) -> ((String) -> String?)? {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return { k in
                text.components(separatedBy: .newlines).first { $0.hasPrefix("\(k)=") }
                    .map { String($0.dropFirst(k.count + 1)).trimmingCharacters(in: .whitespaces) }
            }
        }
        if let value = reader(Paths.ini) {
            ghostFix = value("ghost_fix") != "0"
            middlePan = value("middle_mouse_pan") != "0"
            astar = (value("pathfinding") ?? "astar").hasPrefix("a")
        }
        if let value = reader(Paths.ini2) {
            middlePan2 = value("middle_mouse_pan") != "0"
            astar2 = (value("pathfinding") ?? "astar").hasPrefix("a")
        }
    }

    func saveSettings() {
        guard !loading else { return }
        let ini = """
            [mods]
            enabled=1
            ghost_fix=\(ghostFix ? 1 : 0)
            middle_mouse_pan=\(middlePan ? 1 : 0)
            pan_speed_percent=100
            pathfinding=\(astar ? "astar" : "original")
            patch_delay_ms=8000

            """
        let ini2 = """
            [mods]
            enabled=1
            middle_mouse_pan=\(middlePan2 ? 1 : 0)
            pan_speed_percent=100
            pathfinding=\(astar2 ? "astar" : "original")
            patch_delay_ms=8000

            """
        try? FileManager.default.createDirectory(at: Paths.mods, withIntermediateDirectories: true)
        try? ini.replacingOccurrences(of: "\n", with: "\r\n").write(to: Paths.ini, atomically: true, encoding: .utf8)
        try? ini2.replacingOccurrences(of: "\n", with: "\r\n").write(to: Paths.ini2, atomically: true, encoding: .utf8)
    }

    func install() {
        busy = true
        step = 0
        Task {
            do {
                try await performInstall()
                installed = true
                status = "Battle.net is starting. Sign in, install Warcraft I and/or II: Remastered, and play. " +
                    "Next time just open this app and click Play."
                checkImportOffer()
            } catch {
                status = "Setup stopped: \(error.localizedDescription)"
            }
            busy = false
        }
    }

    private func advance(_ s: String) {
        step += 1
        status = s
        appendLog("== \(s)")
    }

    private func performInstall() async throws {
        let fm = FileManager.default
        for d in [Paths.data, Paths.mods, Paths.cache] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }

        advance("Checking Rosetta…")
        if (try? run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])) == nil {
            status = "Installing Rosetta (macOS will ask for your password)…"
            var err: NSDictionary?
            NSAppleScript(source: "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges")?
                .executeAndReturnError(&err)
            if err != nil { throw SetupError(message: "Rosetta is needed to run Windows games. Install it and try again.") }
        }

        advance("Downloading Wine (about 170 MB)…")
        let engineTar = try await fetch(Downloads.engine)
        advance("Downloading the Wine wrapper (about 100 MB)…")
        let templateTar = try await fetch(Downloads.template)
        advance("Downloading WineMetalGL…")
        let wmglTar = try await fetch(Downloads.wineMetalGL)
        let setupExe = try await fetch(Downloads.battleNet)

        advance("Unpacking…")
        let work = Paths.data.appendingPathComponent("unpack")
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        if fm.fileExists(atPath: Paths.launcher.path) {
            _ = try? run(Paths.launcher.path, ["WSS-wineserverkill"])
        }
        try? fm.removeItem(at: Paths.wrapper)
        try await runAsync("/usr/bin/tar", ["-xJf", templateTar.path, "-C", work.path])
        guard let tpl = try fm.contentsOfDirectory(atPath: work.path).first(where: { $0.hasSuffix(".app") }) else {
            throw SetupError(message: "The wrapper download looks wrong.")
        }
        try fm.moveItem(at: work.appendingPathComponent(tpl), to: Paths.wrapper)
        try await runAsync("/usr/bin/tar", ["-xJf", engineTar.path, "-C", work.path])
        try fm.moveItem(at: work.appendingPathComponent("wswine.bundle"), to: Paths.engine)
        try await runAsync("/usr/bin/tar", ["-xzf", wmglTar.path, "-C", work.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", Paths.wrapper.path])

        advance("Adding WineMetalGL (OpenGL 4.6 for the game)…")
        let wm = work.appendingPathComponent("winemetalgl-3.2.0-x86_64/module")
        let lib = Paths.engine.appendingPathComponent("lib/wine")
        let copies = [("x86_64-windows/winemetalgl.dll", "x86_64-windows/winemetalgl.dll"),
                      ("i386-windows/winemetalgl.dll", "i386-windows/winemetalgl.dll"),
                      ("x86_64-unix/winemetalgl.so", "x86_64-unix/winemetalgl.so"),
                      ("x86_64-unix/libwinemetalgl.dylib", "x86_64-unix/libwinemetalgl.dylib")]
        for (s, d) in copies {
            let dst = lib.appendingPathComponent(d)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: wm.appendingPathComponent(s), to: dst)
        }
        for f in ["winemetalgl.so", "libwinemetalgl.dylib"] {
            _ = try? run("/usr/bin/codesign", ["-f", "-s", "-", lib.appendingPathComponent("x86_64-unix/\(f)").path])
        }
        for f in ["opengl32.dll", "winemetalgl.dll"] {
            let dst = Paths.mods.appendingPathComponent(f)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: wm.appendingPathComponent("i386-windows/\(f)"), to: dst)
        }
        let dllDst = Paths.mods.appendingPathComponent("VERSION.dll")
        try? fm.removeItem(at: dllDst)
        try fm.copyItem(at: Paths.resources.appendingPathComponent("VERSION.dll"), to: dllDst)
        saveSettings()
        try? fm.removeItem(at: work)

        advance("Configuring the wrapper…")
        let plistURL = Paths.wrapper.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw SetupError(message: "Could not read the wrapper settings.")
        }
        plist["Program Name and Path"] = "/Program Files (x86)/Battle.net/Battle.net.exe"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        let sync = Paths.data.appendingPathComponent("sync_mods.sh")
        try? fm.removeItem(at: sync)
        try fm.copyItem(at: Paths.resources.appendingPathComponent("sync_mods.sh"), to: sync)
        let startup = Paths.wrapper.appendingPathComponent("Contents/Resources/Scripts/StartupScript")
        var script = (try? String(contentsOf: startup, encoding: .utf8)) ?? "#!/bin/sh\n"
        if !script.contains("sync_mods.sh") {
            script += "\n# Warcraft I for Mac: keep the mod files in the game folder\n" +
                "nohup /bin/sh \"$HOME/Library/Application Support/Warcraft1Mac/sync_mods.sh\" >/dev/null 2>&1 &\n"
            try script.write(to: startup, atomically: true, encoding: .utf8)
        }

        advance("Creating the Windows environment (about a minute)…")
        try await runAsync(Paths.launcher.path, ["WSS-wineprefixcreate"])
        _ = try? run(Paths.launcher.path, ["WSS-wineserverkill"])
        try await Task.sleep(nanoseconds: 3_000_000_000)
        try applyRegistry()
        Saves.linkAll()

        advance("Starting the Battle.net installer…")
        try fm.createDirectory(at: Paths.installedFlag.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: Paths.installedFlag)
        try run(Paths.launcher.path, [setupExe.path], wait: false)
    }

    func play() {
        saveSettings()
        // Battle.net's background Agent keeps Wine running after Battle.net closes, which would
        // block pending settings updates forever; stop it first (we are about to start it anyway).
        if wineRunning(), !gameRunning(), (try? applyRegistry(dryRun: true)) == true {
            busy = true
            status = "Applying updated settings…"
            Task {
                await stopWine()
                prepareEnvironment()
                busy = false
                launch()
            }
            return
        }
        if !wineRunning() { prepareEnvironment() }
        launch()
    }

    private func launch() {
        startSync()
        if FileManager.default.fileExists(atPath: Paths.battleNet.path) {
            NSWorkspace.shared.openApplication(at: Paths.wrapper, configuration: .init())
            status = "Battle.net is opening. Mods switch on a few seconds after the game starts."
        } else {
            let setup = Paths.cache.appendingPathComponent(Downloads.battleNet.file)
            _ = try? run(Paths.launcher.path, [setup.path], wait: false)
            status = "Battle.net isn't installed yet, so its installer is starting."
        }
    }

    private func startSync() {
        _ = try? run("/bin/sh", ["-c", "nohup /bin/sh \"$HOME/Library/Application Support/Warcraft1Mac/sync_mods.sh\" >/dev/null 2>&1 &"])
    }

    func reinstallBattleNet() {
        let setup = Paths.cache.appendingPathComponent(Downloads.battleNet.file)
        _ = try? run(Paths.launcher.path, [setup.path], wait: false)
    }

    func uninstall() {
        if FileManager.default.fileExists(atPath: Paths.launcher.path) {
            _ = try? run(Paths.launcher.path, ["WSS-wineserverkill"])
        }
        try? FileManager.default.removeItem(at: Paths.data)
        installed = false
        status = "Removed. Your saved games are kept in \"\(Saves.base.path)\" and come back if you install again."
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject var m = Model()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Warcraft I & II: Remastered for Mac").font(.title2.bold())
            Text("Runs the Windows versions of Warcraft I and II: Remastered through free Wine. You need your own Battle.net account and copies of the games.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox("Warcraft I mods") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Fix the crash after loading some saves", isOn: $m.ghostFix)
                    Toggle("Hold the middle mouse button and drag to pan the map", isOn: $m.middlePan)
                    Toggle("Smarter pathfinding (A*) instead of the original", isOn: $m.astar)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            GroupBox("Warcraft II mods") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Hold the middle mouse button and drag to pan the map", isOn: $m.middlePan2)
                    Toggle("Smarter pathfinding (A*) instead of the original", isOn: $m.astar2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            Text("Changes apply the next time a game starts.").font(.caption).foregroundStyle(.secondary)
            if m.busy {
                ProgressView(value: Double(m.step), total: Double(m.totalSteps))
            }
            Text(m.status).fixedSize(horizontal: false, vertical: true)
            HStack {
                if m.installed {
                    Button("Play") { m.play() }.keyboardShortcut(.defaultAction).controlSize(.large).disabled(m.busy)
                } else {
                    Button("Install") { m.install() }.keyboardShortcut(.defaultAction).controlSize(.large).disabled(m.busy)
                }
                Spacer()
                Menu("More") {
                    Button("Run the Battle.net installer again") { m.reinstallBattleNet() }.disabled(!m.installed)
                    Button("Import saved games…") { m.importManually() }.disabled(m.busy)
                    Button("Show saved games in Finder") {
                        try? FileManager.default.createDirectory(at: Saves.base, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([Saves.base])
                    }
                    Button("Show files in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.data]) }
                    Divider()
                    Button("Uninstall…") { m.showUninstall = true }.disabled(m.busy)
                }
                .fixedSize()
            }
        }
        .padding(22)
        .frame(width: 480)
        .confirmationDialog("Remove the game, Battle.net and Wine from this Mac?", isPresented: $m.showUninstall) {
            Button("Remove everything", role: .destructive) { m.uninstall() }
        } message: {
            Text("Wine, Battle.net and the game are deleted. Your saved games are kept. Your Battle.net account and purchases are not affected.")
        }
        .alert("Import your saved games?", isPresented: Binding(
            get: { m.importOffer != nil && !m.busy }, set: { if !$0 { m.importOffer = nil } })) {
            Button("Import") { if let s = m.importOffer { m.importSaves(from: s.folder, game: s.game) }; m.importOffer = nil }
            Button("Not now", role: .cancel) { if let s = m.importOffer { m.declineImport(s) }; m.importOffer = nil }
        } message: {
            Text(m.importOffer.map { "Found \($0.game.name) saves with more progress (\($0.summary)) in\n\($0.folder.path)\n\nYour current saves are backed up first." } ?? "")
        }
    }
}

@main
struct W1RMacApp: App {
    init() {
        // Diagnostics without the UI: list save locations, change nothing.
        if CommandLine.arguments.contains("--list-saves") {
            print("saves folder: \(Saves.base.path)")
            for g in Game.all {
                print("\(g.name): \(Saves.progress(of: Saves.dir(g), g)?.summary ?? "no saves")")
                let game = Saves.gameFolder(g)
                let link = game.flatMap { try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path) }
                print("  in Wine: \(game?.path ?? "none")\(link.map { " -> \($0)" } ?? " (not linked)")")
                for s in Saves.otherSources(g) { print("  found elsewhere: \(s.summary) in \(s.folder.path)") }
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("Warcraft I & II for Mac") { ContentView() }
            .windowResizability(.contentSize)
    }
}
