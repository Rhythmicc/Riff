import Foundation

/// Curated search aliases for applications whose localized display name does
/// not contain the characters users type (for example 微信 → wechat/weixin).
/// Keyed by bundle identifier so the aliases survive app renames.
enum AppAliasCatalog {
    private static let aliasesByBundleIdentifier: [String: [String]] = [
        "com.tencent.xinWeChat": ["wechat", "weixin"]
    ]

    static func aliases(for bundleIdentifier: String) -> [String] {
        aliasesByBundleIdentifier[bundleIdentifier] ?? []
    }
}
