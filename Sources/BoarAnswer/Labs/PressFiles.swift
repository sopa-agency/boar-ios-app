import Foundation

/// Press's files on the device (android engine `labs/PressFiles.kt`; phase 2): `files/labs/press/` holds `projects.json`
/// and one folder per project, where the photos picked from the device are COPIED: the project keeps working if the
/// photo leaves the library, and the copy goes with its project, with Clear all and with Forgot PIN.
public enum PressFiles {
    /// The long side of a copied photo: sharp in an A4 PDF, small on the device.
    public static let photoMax = 1600

    /// A project's folder, always one level under the Press folder: a character that isn't a letter, digit, - or _
    /// becomes _, so "." and ".." can't name a parent, and an empty id is the folder "_", never the Press folder itself
    /// (validator G-9: "delete project" on it would have wiped every project). Kotlin replaces per UTF-16 unit.
    public static func projectDir(_ pressDir: URL, _ projectId: String) -> URL {
        var name = String(String.UnicodeScalarView(projectId.utf16.map { u -> Unicode.Scalar in
            let ok = (0x41...0x5A).contains(u) || (0x61...0x7A).contains(u) || (0x30...0x39).contains(u) || u == 0x2D || u == 0x5F
            return ok ? Unicode.Scalar(u)! : "_"
        }))
        if name.allSatisfy(\.isWhitespace) { name = "_" }
        return pressDir.appending(path: name, directoryHint: .isDirectory)
    }

    /// Java `File(path).name`: the last part after "/", trailing slashes aside.
    static func fileName(_ path: String) -> String {
        var p = Substring(path)
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    }

    /// Java `File(path).parentFile?.name`: the folder the path names its file in, nil for a bare name.
    static func parentName(_ path: String) -> String? {
        var p = Substring(path)
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        let parts = p.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }
        return String(parts[parts.count - 2])
    }

    /// A photo block's file: a plain name in its project's folder; "", "." and ".." become "_", never a folder (G-9).
    public static func photoFile(_ pressDir: URL, _ projectId: String, _ name: String) -> URL {
        let plain = fileName(name)
        let safe = plain.allSatisfy(\.isWhitespace) || plain == "." || plain == ".." ? "_" : plain
        return projectDir(pressDir, projectId).appending(path: safe, directoryHint: .notDirectory)
    }

    /// True when no project uses the photo `name` of `projectId` any more (its block removed past the Undo, G-1).
    public static func unused(_ lib: PressDoc.Library, _ projectId: String, _ name: String) -> Bool {
        !lib.projects.contains { p in
            p.id == projectId && p.blocks.contains { $0.picture.map { $0.kind == .photo && fileName($0.file) == name } ?? false }
        }
    }

    /// How to stand a photo upright from its EXIF orientation (1–8): the degrees to rotate, then whether to mirror it
    /// left-right (validator G-6: the mirrored ones, 2, 4, 5 and 7, were left as taken).
    public static func upright(_ orientation: Int) -> (degrees: Int, mirror: Bool) {
        switch orientation {
        case 2: (0, true)
        case 3: (180, false)
        case 4: (180, true)
        case 5: (90, true)
        case 6: (90, false)
        case 7: (270, true)
        case 8: (270, false)
        default: (0, false)
        }
    }

    /// Writes a photo into its project's folder as `name`: `write` fills a temporary file first, renamed when complete,
    /// so a half copy never shows. Returns the file.
    @discardableResult
    public static func copyInto(_ pressDir: URL, _ projectId: String, _ name: String, write: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default
        let dir = projectDir(pressDir, projectId)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appending(path: fileName(name), directoryHint: .notDirectory)
        let tmp = dir.appending(path: fileName(name) + ".tmp", directoryHint: .notDirectory)
        do {
            try? fm.removeItem(at: tmp)
            try write(tmp)
            if fm.fileExists(atPath: out.path) { _ = try fm.replaceItemAt(out, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: out) }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
        return out
    }

    /// A project deleted: its folder, photos and all.
    public static func deleteProject(_ pressDir: URL, _ projectId: String) {
        try? FileManager.default.removeItem(at: projectDir(pressDir, projectId))
    }

    /// Clear all, Forgot PIN: every project's folder and the projects file.
    public static func eraseAll(_ pressDir: URL) { try? FileManager.default.removeItem(at: pressDir) }

    /// What the folders hold that no project uses any more (a photo removed past its Undo, a project gone, a copy cut
    /// short): files and folders to delete. Only ever run on projects read from their file.
    public static func orphans(_ pressDir: URL, _ lib: PressDoc.Library) -> [URL] {
        let fm = FileManager.default
        var dirs: [String: PressDoc.Project] = [:]
        for p in lib.projects { dirs[projectDir(pressDir, p.id).lastPathComponent] = p }
        let children = (try? fm.contentsOfDirectory(at: pressDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { d -> [URL] in
                guard let p = dirs[d.lastPathComponent] else { return [d] }
                // A photo's copy, and a drawing copied into the project when the chats were cleared with Press kept (R-A3).
                let used = Set(p.blocks.compactMap(\.picture)
                    .filter { $0.kind == .photo || parentName($0.file) == d.lastPathComponent }.map { fileName($0.file) })
                let files = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
                return files.filter { !used.contains($0.lastPathComponent) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
    }

    /// A photo's size once copied: its long side at most `max`, its shape kept.
    public static func scaled(_ width: Int, _ height: Int, max limit: Int = photoMax) -> (Int, Int) {
        if width <= 0 || height <= 0 { return (0, 0) }
        let long = max(width, height)
        if long <= limit { return (width, height) }
        func round(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
        return (max(1, round(Double(width) * Double(limit) / Double(long))), max(1, round(Double(height) * Double(limit) / Double(long))))
    }

    /// The power of two to decode with: the largest that still leaves the long side at least `max`.
    public static func sampleSize(_ width: Int, _ height: Int, max limit: Int = photoMax) -> Int {
        var s = 1
        let long = max(width, height)
        while long / (s * 2) >= limit { s *= 2 }
        return s
    }
}
