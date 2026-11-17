import CryptoKit
import Foundation

/// SHA-256 / 表单编码。胖乖生活所有接口的 sign 都是 SHA-256 十六进制小写。
enum Crypto {
    static func sha256Hex(_ raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        var out = ""
        out.reserveCapacity(64)
        for byte in digest {
            let hex = String(byte, radix: 16)
            if hex.count == 1 { out += "0" }
            out += hex
        }
        return out
    }

    /// application/x-www-form-urlencoded，空格编成 %20（与 Java URLEncoder 的 + 不同，
    /// 服务端两者都收，这里用 %20 更稳）。
    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        let body = fields
            .map { "\(formEncode($0.0))=\(formEncode($0.1))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}
