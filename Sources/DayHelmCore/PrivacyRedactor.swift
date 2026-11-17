import Foundation

public struct PrivacyRedactorConfig: Sendable, Equatable, Codable {
    public var redactWeChat: Bool
    public var redactMessages: Bool
    public var additionalSensitiveBundlePrefixes: [String]
    public var additionalSensitiveKeywords: [String]

    public static let `default` = PrivacyRedactorConfig()

    public init(
        redactWeChat: Bool = true,
        redactMessages: Bool = true,
        additionalSensitiveBundlePrefixes: [String] = [],
        additionalSensitiveKeywords: [String] = []
    ) {
        self.redactWeChat = redactWeChat
        self.redactMessages = redactMessages
        self.additionalSensitiveBundlePrefixes = additionalSensitiveBundlePrefixes
        self.additionalSensitiveKeywords = additionalSensitiveKeywords
    }
}

public enum PrivacyRedactor {
    private static let passwordManagerPrefixes = [
        "com.1password",
        "com.bitwarden",
        "com.agilebits"
    ]

    private static let bankingSubstringKeywords = [
        "bank",
        "checkout",
        "stripe",
        "alipay",
        "paypal",
        "wechatpay",
        "unionpay"
    ]

    private static let medicalAndIDKeywords = [
        "病历",
        "诊断",
        "身份证",
        "护照"
    ]

    private static let systemPrivacyKeywords = [
        "privacy",
        "security",
        "隐私",
        "安全",
        "passcode",
        "密码",
        "accessibility",
        "辅助功能",
        "screen recording",
        "录屏",
        "touch id"
    ]

    private static let sensitiveQueryParamNames: Set<String> = [
        "token",
        "key",
        "session",
        "sig",
        "secret",
        "password",
        "auth"
    ]

    public static func redact(
        _ sample: ActivitySample,
        config: PrivacyRedactorConfig = .default
    ) -> ActivitySample {
        if sample.redacted {
            return ActivitySample(
                timestamp: sample.timestamp,
                appName: sample.appName,
                bundleId: sample.bundleId,
                windowTitle: nil,
                url: nil,
                idleSeconds: sample.idleSeconds,
                screenLocked: sample.screenLocked,
                inputActive: sample.inputActive,
                redacted: true
            )
        }

        if shouldRedact(sample, config: config) {
            return ActivitySample(
                timestamp: sample.timestamp,
                appName: sample.appName,
                bundleId: sample.bundleId,
                windowTitle: nil,
                url: nil,
                idleSeconds: sample.idleSeconds,
                screenLocked: sample.screenLocked,
                inputActive: sample.inputActive,
                redacted: true
            )
        }

        let sanitizedURL = sanitizeURL(sample.url)
        return ActivitySample(
            timestamp: sample.timestamp,
            appName: sample.appName,
            bundleId: sample.bundleId,
            windowTitle: sample.windowTitle,
            url: sanitizedURL,
            idleSeconds: sample.idleSeconds,
            screenLocked: sample.screenLocked,
            inputActive: sample.inputActive,
            redacted: false
        )
    }

    public static func shouldRedact(
        _ sample: ActivitySample,
        config: PrivacyRedactorConfig = .default
    ) -> Bool {
        let bundleLower = sample.bundleId?.lowercased() ?? ""

        // 1. Password managers
        if !bundleLower.isEmpty {
            for prefix in passwordManagerPrefixes {
                if bundleLower == prefix || bundleLower.hasPrefix(prefix + ".") {
                    return true
                }
            }
            for prefix in config.additionalSensitiveBundlePrefixes {
                let p = prefix.lowercased()
                if !p.isEmpty && (bundleLower == p || bundleLower.hasPrefix(p)) {
                    return true
                }
            }
        }

        // 2. Private chat
        if config.redactWeChat && bundleLower == "com.tencent.xinwechat" {
            return true
        }
        if config.redactMessages && bundleLower == "com.apple.mobilesms" {
            return true
        }

        let titleLower = sample.windowTitle?.lowercased() ?? ""
        let urlLower = sample.url?.lowercased() ?? ""
        let combined = titleLower + " " + urlLower

        // 3. System privacy settings
        if bundleLower == "com.apple.systempreferences" || bundleLower == "com.apple.systemsettings" {
            if systemPrivacyKeywords.contains(where: { titleLower.contains($0) }) {
                return true
            }
        }

        // 4. Banking / payment keywords in title or URL
        for keyword in bankingSubstringKeywords {
            if combined.contains(keyword) {
                return true
            }
        }
        if matchesPayKeyword(titleLower) || matchesPayKeyword(urlLower) {
            return true
        }

        // 5. Medical / ID keywords
        for keyword in medicalAndIDKeywords {
            if combined.contains(keyword) {
                return true
            }
        }

        // 6. Custom keywords
        for keyword in config.additionalSensitiveKeywords {
            let k = keyword.lowercased()
            if !k.isEmpty && combined.contains(k) {
                return true
            }
        }

        return false
    }

    public static func sanitizeURL(_ urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty else {
            return urlString
        }
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }
        guard let items = components.queryItems, !items.isEmpty else {
            return urlString
        }
        let filtered = items.filter { !sensitiveQueryParamNames.contains($0.name.lowercased()) }
        if filtered.count == items.count {
            return urlString
        }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.string ?? urlString
    }

    // MARK: - Credential Redaction (metadata + OCR text)

    /// Ordered from most specific to most generic so tokens are not partially masked twice.
    private static let secretRedactionRules: [(pattern: String, template: String)] = [
        (#"\bsk-[A-Za-z0-9_\-]{16,}"#, "sk-***"),
        (#"\bgh[pousr]_[A-Za-z0-9]{16,}"#, "gh*_***"),
        (#"\bxox[abprs]-[A-Za-z0-9\-]{8,}"#, "xox*-***"),
        (#"\bAKIA[0-9A-Z]{16}\b"#, "AKIA***"),
        (#"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{4,}"#, "jwt.***"),
        (#"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=\-]{8,}"#, "$1 ***"),
        (#"(?i)\b(api[_-]?key|access[_-]?key|client[_-]?secret|secret|token|password|passwd|pwd|authorization)\b\s*[:=]\s*[\"'`]?([^\s\"'`;,&?]{3,})[\"'`]?"#, "$1=***")
    ]

    private static let compiledSecretRules: [(regex: NSRegularExpression, template: String)] = secretRedactionRules.compactMap { rule in
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: []) else { return nil }
        return (regex, rule.template)
    }

    /// Masks credentials found in free-form metadata or OCR text while keeping surrounding context.
    public static func redactSecrets(in text: String) -> String {
        guard !text.isEmpty, !compiledSecretRules.isEmpty else { return text }
        var result = text
        for rule in compiledSecretRules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = rule.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: rule.template
            )
        }
        return result
    }

    /// Normalizes a single metadata value (event `data`, snapshot title): strips URL
    /// credential query params when it looks like a URL, then masks embedded secrets.
    public static func sanitizeMetadataValue(_ value: String) -> String {
        if value.contains("://") || value.lowercased().hasPrefix("http") {
            let cleaned = sanitizeURL(value) ?? value
            return redactSecrets(in: cleaned)
        }
        return redactSecrets(in: value)
    }

    private static func matchesPayKeyword(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pattern = #"(?:^|[^a-z0-9])pay(?:ment|s)?(?:$|[^a-z0-9])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
