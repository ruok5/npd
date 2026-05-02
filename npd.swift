import Foundation

let HOME = FileManager.default.homeDirectoryForCurrentUser.path
let JSON_PATH = "\(HOME)/.nowplaying.json"

let iso = ISO8601DateFormatter()

func log(_ msg: String) {
    let line = "[\(iso.string(from: Date()))] \(msg)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

func writeJSON(_ dict: [String: Any]) {
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

func extract(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    out["state"] = ((userInfo["Player State"] as? String) ?? "unknown").lowercased()
    if let v = userInfo["Name"] as? String { out["title"] = v }
    if let v = userInfo["Artist"] as? String { out["artist"] = v }
    if let v = userInfo["Album"] as? String { out["album"] = v }
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
    out["title"] = parts[1]
    out["artist"] = parts[2]
    out["album"] = parts[3]
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
