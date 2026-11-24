/// What About's version block copies on press and hold: plain text for a bug report (android `AboutDebug.report`). Only the
/// clipboard: nothing is sent.
public enum AboutReport {
    /// `version`: the version line; `device`: the model and the system; `plugins`: the titles of the plugins on.
    public static func text(version: String, device: String, plugins: [String]) -> String {
        let list = plugins.isEmpty ? "none" : plugins.joined(separator: ", ")
        return "BOAR \(version)\nDevice: \(device)\nPlugins (\(plugins.count)): \(list)"
    }
}
