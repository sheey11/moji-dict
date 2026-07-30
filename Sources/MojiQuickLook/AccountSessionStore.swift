import Foundation
import Security

struct PersistedAccountSession: Codable, Equatable, Sendable {
    let sessionToken: String
    let deviceID: String
    let displayName: String
    let email: String?
}

enum AccountSessionStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain:
            "无法写入 macOS 钥匙串。"
        }
    }
}

enum AccountSessionStore {
    private static let service = "local.codex.mojiquicklook.account-session"
    private static let account = "MOJi"

    static func load() -> PersistedAccountSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let session = try? JSONDecoder().decode(
                PersistedAccountSession.self,
                from: data
            )
        else {
            return nil
        }
        return session
    }

    static func save(_ session: PersistedAccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AccountSessionStoreError.keychain(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw AccountSessionStoreError.keychain(updateStatus)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
