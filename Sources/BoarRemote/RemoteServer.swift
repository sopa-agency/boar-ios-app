import BoarCore
import Foundation

/// A llama.cpp `llama-server` on another computer in the same network (a Mac mini), reached over its OpenAI-compatible
/// HTTP API. Only text generation goes there: search, the library and the chats stay on this device.
public struct RemoteServer: Sendable, Equatable, Codable {
    /// "http://mac-mini.local:8080".
    public var baseURL: URL
    /// The server's `--api-key`, when it was started with one.
    public var apiKey: String?

    public init(baseURL: URL, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
    }

    /// Reads what people type: "mac-mini.local", "192.168.0.20:8080", "http://host:8080/". Port 8080 when none is given.
    public static func parse(_ text: String, apiKey: String? = nil) -> RemoteServer? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var parts = URLComponents(string: s), let host = parts.host, !host.isEmpty,
              parts.scheme == "http" || parts.scheme == "https" else { return nil }
        if parts.port == nil { parts.port = 8080 }
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { return nil }
        return RemoteServer(baseURL: url, apiKey: apiKey)
    }

    /// "mac-mini.local:8080", for labels.
    public var displayName: String {
        let host = baseURL.host() ?? baseURL.absoluteString
        return baseURL.port.map { "\(host):\($0)" } ?? host
    }

    func request(_ path: String, body: Data? = nil, timeout: TimeInterval = 600) -> URLRequest {
        var r = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
        if let body {
            r.httpMethod = "POST"
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let apiKey { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return r
    }
}

/// What the server reported when BOAR checked it.
public struct RemoteServerStatus: Sendable, Equatable {
    /// The model file it serves, without the extension ("Qwen3-4B-Instruct-2507-Q4_K_M").
    public var modelName: String
    /// Its context window per request, when it says.
    public var contextTokens: Int?
}

public enum RemoteServerError: Error, Equatable, CustomStringConvertible {
    case unreachable(String)
    case httpStatus(Int, String)
    case badResponse(String)

    public var description: String {
        switch self {
        case .unreachable(let s): "The Mac on your network didn't answer (\(s))."
        case .httpStatus(let code, let s): code == 401 ? "The server asked for an API key." : "The server answered \(code): \(s)"
        case .badResponse(let s): "The server sent something BOAR can't read: \(s)"
        }
    }
}

extension RemoteServer {
    /// Checks that a llama-server is there and which model it serves (`GET /props`, then `/v1/models`).
    public func probe(session: URLSession = .shared, timeout: TimeInterval = 5) async throws -> RemoteServerStatus {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request("props", timeout: timeout))
        } catch {
            throw RemoteServerError.unreachable((error as? URLError).map { $0.localizedDescription } ?? String(describing: error))
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let path = o["model_path"] as? String ?? ""
            let settings = o["default_generation_settings"] as? [String: Any]
            let nCtx = (settings?["n_ctx"] as? Int) ?? (o["n_ctx"] as? Int)
            let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".gguf", with: "")
            return RemoteServerStatus(modelName: name.isEmpty ? "llama-server" : name, contextTokens: nCtx)
        }
        if code == 401 { throw RemoteServerError.httpStatus(401, "") }
        // Older servers or OpenAI-compatible proxies: the model list.
        let (d2, r2) = try await session.data(for: request("v1/models", timeout: timeout))
        let c2 = (r2 as? HTTPURLResponse)?.statusCode ?? 0
        guard c2 == 200, let o = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
              let first = (o["data"] as? [[String: Any]])?.first, let id = first["id"] as? String else {
            throw RemoteServerError.httpStatus(c2, String(decoding: d2.prefix(200), as: UTF8.self))
        }
        return RemoteServerStatus(modelName: (id as NSString).lastPathComponent.replacingOccurrences(of: ".gguf", with: ""), contextTokens: nil)
    }
}
