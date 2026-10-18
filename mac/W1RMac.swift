// Warcraft I: Remastered for Mac — sets up a free Wine (Sikarugir, built from CrossOver's
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

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var ghostFix = true { didSet { saveSettings() } }
    @Published var middlePan = true { didSet { saveSettings() } }
    @Published var astar = true { didSet { saveSettings() } }
    @Published var status = ""
    @Published var busy = false
    @Published var step = 0
    @Published var installed = FileManager.default.fileExists(atPath: Paths.installedFlag.path)
    @Published var showUninstall = false
    let totalSteps = 9
    private var loading = true

    init() {
        loadSettings()
        loading = false
        status = installed ? "Ready. Click Play to open Battle.net." :
            "Click Install. Setup downloads about 300 MB and takes a few minutes."
    }

    func loadSettings() {
        guard let text = try? String(contentsOf: Paths.ini, encoding: .utf8) else { return }
        func value(_ k: String) -> String? {
            text.split(separator: "\n").first { $0.hasPrefix("\(k)=") }.map { String($0.dropFirst(k.count + 1)) }
        }
        ghostFix = value("ghost_fix") != "0"
        middlePan = value("middle_mouse_pan") != "0"
        astar = (value("pathfinding") ?? "astar").hasPrefix("a")
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
        try? FileManager.default.createDirectory(at: Paths.mods, withIntermediateDirectories: true)
        try? ini.replacingOccurrences(of: "\n", with: "\r\n").write(to: Paths.ini, atomically: true, encoding: .utf8)
    }

    func install() {
        busy = true
        step = 0
        Task {
            do {
                try await performInstall()
                installed = true
                status = "Battle.net is starting. Sign in, install Warcraft I: Remastered, and play. " +
                    "Next time just open this app and click Play."
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
        let reg = Paths.prefix.appendingPathComponent("user.reg")
        var text = try String(contentsOf: reg, encoding: .utf8)
        text = setRegValue(text, section: "Environment", key: "SDL_AUDIODRIVER", value: "directsound")
        let overrides = "Software\\\\Wine\\\\AppDefaults\\\\Warcraft.exe\\\\DllOverrides"
        text = setRegValue(text, section: overrides, key: "opengl32", value: "native")
        text = setRegValue(text, section: overrides, key: "version", value: "native,builtin")
        try text.write(to: reg, atomically: true, encoding: .utf8)

        advance("Starting the Battle.net installer…")
        try fm.createDirectory(at: Paths.installedFlag.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: Paths.installedFlag)
        try run(Paths.launcher.path, [setupExe.path], wait: false)
    }

    func play() {
        saveSettings()
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
        status = "Removed. Battle.net, the game and all settings for it on this Mac are gone."
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject var m = Model()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Warcraft I: Remastered for Mac").font(.title2.bold())
            Text("Runs the Windows version through free Wine. You need your own Battle.net account and a copy of the game.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox("Mods") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Fix the crash after loading some saves", isOn: $m.ghostFix)
                    Toggle("Hold the middle mouse button and drag to pan the map", isOn: $m.middlePan)
                    Toggle("Smarter pathfinding (A*) instead of the original", isOn: $m.astar)
                    Text("Changes apply the next time the game starts.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
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
            Text("Everything this app set up is deleted. Your Battle.net account and purchases are not affected.")
        }
    }
}

@main
struct W1RMacApp: App {
    var body: some Scene {
        WindowGroup("Warcraft I for Mac") { ContentView() }
            .windowResizability(.contentSize)
    }
}
