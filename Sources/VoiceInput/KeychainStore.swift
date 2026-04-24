import Foundation
import Security

struct KeychainStore {
    let service: String
    let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainStoreError.unexpectedData
            }
            guard let value = String(data: data, encoding: .utf8) else {
                throw KeychainStoreError.unexpectedData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.osStatus(status)
        }
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemCopyMatching(baseQuery() as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            let attributes = [kSecValueData as String: data] as CFDictionary
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes)
            guard updateStatus == errSecSuccess else {
                throw KeychainStoreError.osStatus(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.osStatus(addStatus)
            }
        default:
            throw KeychainStoreError.osStatus(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.osStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum KeychainStoreError: LocalizedError, Equatable {
    case unexpectedData
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Keychain returned unexpected data."
        case .osStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error: \(message)"
            }
            return "Keychain error: \(status)"
        }
    }
}
