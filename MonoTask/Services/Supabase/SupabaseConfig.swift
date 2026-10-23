import Foundation
import Observation

@Observable
@MainActor
final class SupabaseConfig {
    static let shared = SupabaseConfig()

    private let lastSyncKey = "monotask_supabase_last_sync"

    // Public client settings. Database access is restricted by Supabase Auth and RLS.
    static let defaultUrl = "https://jgkeycihgmdwxfxomtim.supabase.co"
    static let defaultAnonKey = "sb_publishable_4vNqfASf8rplPt2ys982tA_tqlBT0QO"

    /// Supabase URL loaded from environment variables, .env file, bundled plist, or fallback default
    var url: String {
        didSet {
            SupabaseService.shared.configureClient()
        }
    }

    /// Supabase Anon Public Key loaded from environment variables, .env file, bundled plist, or fallback default
    var anonKey: String {
        didSet {
            SupabaseService.shared.configureClient()
        }
    }

    var lastSyncDate: Date? {
        didSet {
            if let lastSyncDate {
                UserDefaults.standard.set(lastSyncDate.timeIntervalSince1970, forKey: lastSyncKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastSyncKey)
            }
        }
    }

    private init() {
        let loadedUrl = Self.loadEnvValue(for: "SUPABASE_URL") ?? Self.defaultUrl
        let loadedKey =
            Self.loadEnvValue(for: "SUPABASE_ANON_KEY") ?? Self.loadEnvValue(for: "SUPABASE_PUBLISHABLE_KEY")
            ?? Self.loadEnvValue(for: "SUPABASE_KEY") ?? Self.defaultAnonKey

        self.url = loadedUrl
        self.anonKey = loadedKey

        let lastSyncTimestamp = UserDefaults.standard.double(forKey: lastSyncKey)
        if lastSyncTimestamp > 0 {
            self.lastSyncDate = Date(timeIntervalSince1970: lastSyncTimestamp)
        } else {
            self.lastSyncDate = nil
        }
    }

    var isConfigured: Bool {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUrl.isEmpty, !trimmedKey.isEmpty else { return false }
        guard let parsedUrl = URL(string: trimmedUrl),
            let scheme = parsedUrl.scheme,
            scheme == "https" || scheme == "http"
        else {
            return false
        }
        return true
    }

    var cleanUrl: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed)
    }

    // MARK: - Environment & Configuration Loading

    private static func loadEnvValue(for key: String) -> String? {
        // 1. Check ProcessInfo environment variables (Xcode scheme / CI)
        if let envVal = ProcessInfo.processInfo.environment[key],
            !envVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return envVal.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Check Bundle Info.plist
        if let infoVal = Bundle.main.infoDictionary?[key] as? String,
            !infoVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !infoVal.hasPrefix("$(")
        {
            return infoVal.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 3. Check for bundled configuration files in App Resources
        let resourceCandidates: [(String, String?)] = [
            ("SupabaseConfig", "plist"),
            ("supabase", "plist"),
            ("env", "plist"),
            (".env", nil),
            ("env", nil),
        ]

        for (name, ext) in resourceCandidates {
            if let bundleUrl = Bundle.main.url(forResource: name, withExtension: ext) {
                if ext == "plist" || bundleUrl.pathExtension == "plist" {
                    if let dict = NSDictionary(contentsOf: bundleUrl) as? [String: Any],
                        let val = dict[key] as? String,
                        !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        return val.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else if let parsed = parseEnvFile(at: bundleUrl),
                    let val = parsed[key],
                    !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return val.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // 4. File system search (macOS development, Xcode run from source)
        #if os(macOS) || targetEnvironment(simulator)
        let currentDir = FileManager.default.currentDirectoryPath
        let sourceFileDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Supabase/
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // MonoTask/
            .deletingLastPathComponent()  // Project root

        let candidatePaths = [
            currentDir + "/.env",
            currentDir + "/.env.local",
            sourceFileDir.appendingPathComponent(".env").path,
            sourceFileDir.appendingPathComponent(".env.local").path,
            sourceFileDir.appendingPathComponent("MonoTask/.env").path,
            sourceFileDir.appendingPathComponent("MonoTask/Resources/.env").path,
        ]

        for path in candidatePaths {
            let fileUrl = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileUrl.path),
                let parsed = parseEnvFile(at: fileUrl),
                let val = parsed[key], !val.isEmpty
            {
                return val
            }
        }
        #endif

        // 5. Fallback compiled defaults
        switch key {
        case "SUPABASE_URL":
            return defaultUrl
        case "SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY", "SUPABASE_KEY":
            return defaultAnonKey
        default:
            return nil
        }
    }

    private static func parseEnvFile(at url: URL) -> [String: String]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var dict: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let eqIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
            var val = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            if !key.isEmpty {
                dict[key] = val
            }
        }
        return dict
    }
}
