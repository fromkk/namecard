import Testing
@testable import Namecard

struct UrlValidationTests {
    @Test func addsHttpsWhenSchemeMissing() {
        #expect(UrlValidation.normalize("example.com/namecard") == .valid("https://example.com/namecard"))
    }

    @Test func acceptsHttp() {
        #expect(UrlValidation.normalize("http://example.com") == .valid("http://example.com"))
    }

    @Test func acceptsHostWithPortWithoutScheme() {
        #expect(UrlValidation.normalize("example.com:8080/profile") == .valid("https://example.com:8080/profile"))
    }

    @Test func percentEncodesNonASCIIPath() {
        #expect(UrlValidation.normalize("http://example.com/名刺") == .valid("http://example.com/%E5%90%8D%E5%88%BA"))
    }

    @Test func rejectsNonWebSchemeAndWhitespace() {
        if case .valid = UrlValidation.normalize("mailto:test@example.com") { Issue.record("mailto should be rejected") }
        if case .valid = UrlValidation.normalize("https://example.com/a b") { Issue.record("whitespace should be rejected") }
        if case .valid = UrlValidation.normalize("") { Issue.record("empty should be rejected") }
    }
}
