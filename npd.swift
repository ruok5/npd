import Foundation

let HOME = FileManager.default.homeDirectoryForCurrentUser.path
let JSON_PATH = "\(HOME)/.nowplaying.json"
let YIELD_WINDOW: TimeInterval = 600

let iso = ISO8601DateFormatter()

func log(_ msg: String) {
    let line = "[\(iso.string(from: Date()))] \(msg)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

// Another writer owns the file while its entry says it's playing and is
// fresher than YIELD_WINDOW; writers must re-stamp updatedAt within that
// window (each track change is plenty) to keep ownership.
func foreignSourceActive() -> Bool {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: JSON_PATH)),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let source = obj["source"] as? String, source != "Music",
          (obj["state"] as? String) == "playing",
          let stamp = obj["updatedAt"] as? String,
          let ts = iso.date(from: stamp)
    else { return false }
    return Date().timeIntervalSince(ts) < YIELD_WINDOW
}

func writeJSON(_ dict: [String: Any]) {
    let newState = (dict["state"] as? String) ?? "unknown"
    if newState != "playing", foreignSourceActive() {
        log("foreign source active; skipped \(newState) write")
        return
    }
    var out = dict
    out["source"] = "Music"
    out["updatedAt"] = iso.string(from: Date())
    do {
        let data = try JSONSerialization.data(
            withJSONObject: out,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: JSON_PATH), options: .atomic)
        let title = (out["title"] as? String) ?? "(no title)"
        let state = (out["state"] as? String) ?? "?"
        log("wrote \(state): \(title)")
    } catch {
        log("write failed: \(error)")
    }
}

// Strip reissue noise — "[2011 Remaster]", "(Deluxe Edition)", "(Bonus Track)",
// "[Disc 2]", "(25th Anniversary ...)" — from titles and album names.
let noisePatterns = [
    " *\\[[^\\]]*[Rr]emaster[^\\]]*\\]",
    " *\\([^)]*[Rr]emaster[^)]*\\)",
    " *\\[[^\\]]*[Ee]dition[^\\]]*\\]",
    " *\\([^)]*[Ee]dition[^)]*\\)",
    " *\\[[^\\]]*[Bb]onus[^\\]]*\\]",
    " *\\([^)]*[Bb]onus[^)]*\\)",
    " *\\[Disc [0-9]+\\]",
    " *\\(Disc [0-9]+\\)",
    " *\\[[^\\]]*[Aa]nniversary[^\\]]*\\]",
    " *\\([^)]*[Aa]nniversary[^)]*\\)",
]

func cleanMusicText(_ text: String) -> String {
    var out = text
    for pattern in noisePatterns {
        out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    return out.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
}

func extract(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    out["state"] = ((userInfo["Player State"] as? String) ?? "unknown").lowercased()
    if let v = userInfo["Name"] as? String { out["title"] = cleanMusicText(v) }
    if let v = userInfo["Artist"] as? String { out["artist"] = v }
    if let v = userInfo["Album"] as? String { out["album"] = cleanMusicText(v) }
    if let v = userInfo["Album Artist"] as? String, !v.isEmpty { out["albumArtist"] = v }
    if let v = userInfo["Genre"] as? String, !v.isEmpty { out["genre"] = v }
    if let ms = userInfo["Total Time"] as? NSNumber {
        out["duration"] = ms.doubleValue / 1000.0
    }
    if let v = userInfo["Persistent ID"] as? String { out["persistentId"] = v }
    if let v = userInfo["Store URL"] as? String { out["storeUrl"] = v }
    return out
}

func seedFromAppleScript() {
    let script = """
    tell application "Music"
        if it is running then
            set s to player state as text
            if s is "playing" or s is "paused" then
                set t to current track
                return s & "|" & (name of t) & "|" & (artist of t) & "|" & (album of t) & "|" & (album artist of t) & "|" & (genre of t) & "|" & (duration of t as text) & "|" & (persistent ID of t)
            else
                return s
            end if
        else
            return "not running"
        end if
    end tell
    """
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", script]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        log("osascript launch failed: \(error)")
        return
    }
    guard let data = try? pipe.fileHandleForReading.readToEnd(),
          let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    else {
        log("osascript: no output")
        return
    }
    if raw == "not running" || raw == "stopped" {
        writeJSON(["state": "stopped"])
        return
    }
    let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 8 else {
        log("osascript: unexpected output: \(raw)")
        return
    }
    var out: [String: Any] = [:]
    out["state"] = parts[0]
    out["title"] = cleanMusicText(parts[1])
    out["artist"] = parts[2]
    out["album"] = cleanMusicText(parts[3])
    if !parts[4].isEmpty { out["albumArtist"] = parts[4] }
    if !parts[5].isEmpty { out["genre"] = parts[5] }
    if let d = Double(parts[6]) { out["duration"] = d }
    if !parts[7].isEmpty { out["persistentId"] = parts[7] }
    writeJSON(out)
}

log("npd starting; writing \(JSON_PATH)")
seedFromAppleScript()

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.Music.playerInfo"),
    object: nil,
    queue: .main
) { note in
    guard let userInfo = note.userInfo else { return }
    writeJSON(extract(userInfo))
}

log("subscribed to com.apple.Music.playerInfo; entering run loop")
RunLoop.main.run()
