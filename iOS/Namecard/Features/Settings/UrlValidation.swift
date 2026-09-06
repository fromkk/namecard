import Foundation

/// Validates and normalizes a URL for NDEF writing, matching the Android
/// `validateUrlInput`: only http/https, adds https:// when the scheme is
/// missing, rejects whitespace and non-web schemes.
enum UrlValidation {
    enum Outcome: Equatable {
        case valid(String)
        case invalid(String)
    }

    static func normalize(_ input: String) -> Outcome {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .invalid("URLを入力してください") }
        if trimmed.contains(where: { $0.isWhitespace || $0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }) {
            return .invalid("空白を含まないURLを入力してください")
        }

        let hasWebScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        if !hasWebScheme, let colon = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) {
            let afterColon = trimmed[colon.upperBound...].prefix { $0 != "/" }
            if Int(afterColon) == nil {
                return .invalid("http:// または https:// のURLを入力してください")
            }
        }

        let candidate = hasWebScheme ? trimmed : "https://" + trimmed
        // Percent-encode invalid characters (e.g. a non-ASCII path) so a URL the
        // Android client accepts is not rejected here. Whitespace was already
        // rejected above, matching Android.
        guard
            let url = URL(string: candidate, encodingInvalidCharacters: true),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            return .invalid("http:// または https:// のURLを入力してください")
        }
        guard let host = components.host, !host.isEmpty else {
            return .invalid("ホスト名を含むURLを入力してください")
        }
        return .valid(url.absoluteString)
    }
}
