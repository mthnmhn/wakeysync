import AppKit
import Foundation

/// Minimal Umami analytics client.
///
/// Design constraints:
/// - Off by default. Sends nothing until the user opts in.
/// - No personally identifying data. No Bluetooth MACs, no IPs (Umami strips
///   IP at ingest), no user-typed content.
/// - Fails silently. Network errors must never block a sync.
/// - Single file so anyone reviewing the repo can audit it end-to-end.
///
/// Configuration:
/// - Reads `WSUmamiEndpoint` (e.g. `https://analytics.wakeysync.dev`) and
///   `WSUmamiWebsiteId` (UUID) from the app's Info.plist. If either is
///   missing or empty, the client is a no-op even when "enabled" is true.
///   This lets dev builds run without ever sending anything.
enum Telemetry {

    // MARK: - Public API

    static func bootstrap() {
        // Called from app delegate on launch. No-op for now; reserved so
        // future warm-up (e.g. resolving DNS, reading firmware) can hook in
        // without changing call sites.
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Keys.enabled)
        UserDefaults.standard.set(true, forKey: Keys.consentAsked)
    }

    static var hasAskedConsent: Bool {
        UserDefaults.standard.bool(forKey: Keys.consentAsked)
    }

    static func markConsentAsked() {
        UserDefaults.standard.set(true, forKey: Keys.consentAsked)
    }

    /// Fire a named event. Safe to call from any thread. Returns immediately.
    static func track(_ event: String, data: [String: String] = [:]) {
        guard isEnabled, let config = Config.fromBundle() else { return }
        let environment = Environment.current()
        let payload = Payload(
            websiteId: config.websiteId,
            hostname: config.hostname,
            event: event,
            data: data.merging(environment.asDictionary()) { current, _ in current }
        )
        Sender.send(payload, to: config.endpoint)
    }

    // MARK: - Storage keys

    private enum Keys {
        static let enabled = "WSAnalyticsEnabled"
        static let consentAsked = "WSAnalyticsConsentAsked"
    }
}

// MARK: - Config

private struct Config {
    let endpoint: URL
    let websiteId: String
    let hostname: String

    static func fromBundle() -> Config? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard
            let endpointString = info["WSUmamiEndpoint"] as? String,
            let websiteId = info["WSUmamiWebsiteId"] as? String,
            !endpointString.isEmpty,
            !websiteId.isEmpty,
            let endpoint = URL(string: endpointString)
        else {
            return nil
        }
        let hostname = (info["WSUmamiHostname"] as? String) ?? "wakeysync.app"
        return Config(endpoint: endpoint, websiteId: websiteId, hostname: hostname)
    }
}

// MARK: - Environment fingerprint

private struct Environment {
    let appVersion: String
    let macOSVersion: String
    let macModel: String

    static func current() -> Environment {
        Environment(
            appVersion: appVersion(),
            macOSVersion: macOSVersionMajorMinor(),
            macModel: macModelIdentifier()
        )
    }

    func asDictionary() -> [String: String] {
        [
            "app_version": appVersion,
            "macos": macOSVersion,
            "mac_model": macModel,
        ]
    }

    private static func appVersion() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return short
    }

    private static func macOSVersionMajorMinor() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private static func macModelIdentifier() -> String {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

// MARK: - Payload

private struct Payload {
    let websiteId: String
    let hostname: String
    let event: String
    let data: [String: String]

    func asJSON() -> Data? {
        let body: [String: Any] = [
            "type": "event",
            "payload": [
                "website": websiteId,
                "hostname": hostname,
                "screen": "1x1",
                "language": Locale.current.identifier,
                "url": "/",
                "name": event,
                "data": data,
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: body, options: [])
    }
}

// MARK: - Sender

private enum Sender {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func send(_ payload: Payload, to endpoint: URL) {
        guard let body = payload.asJSON() else { return }
        var request = URLRequest(url: endpoint.appendingPathComponent("api/send"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let task = session.dataTask(with: request) { _, _, _ in
            // Silently ignore all outcomes. Telemetry must never disrupt the app.
        }
        task.resume()
    }

    private static func userAgent() -> String {
        // Format the UA so Umami's user-agent parser recognises macOS.
        // It looks for the substring "Mac OS X" with underscore-separated
        // version digits, as in real browser UAs.
        let env = Environment.current()
        let osVersionForUA = env.macOSVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(osVersionForUA)) "
            + "WakeySync/\(env.appVersion) (\(env.macModel))"
    }
}
