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

    private static func matchesPayKeyword(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pattern = #"(?:^|[^a-z0-9])pay(?:ment|s)?(?:$|[^a-z0-9])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
