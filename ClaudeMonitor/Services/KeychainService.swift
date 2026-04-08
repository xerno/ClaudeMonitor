import CryptoKit
import Foundation
import IOKit
import Security

/// Encrypted credential storage using UserDefaults + AES-GCM.
/// Encryption key is derived from the machine's hardware UUID,
/// so the data is unreadable on other machines or by simple plist readers.
/// Can be swapped to Keychain when the app is properly code-signed.
nonisolated enum KeychainService {
    nonisolated(unsafe) private static let defaults = UserDefaults.standard

    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let plaintext = value.data(using: .utf8) else { return false }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: cachedEncryptionKey)
            guard let combined = sealed.combined else { return false }
            defaults.set(combined, forKey: key)
            return true
        } catch {
            return false
        }
    }

    static func load(key: String) -> String? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(box, using: cachedEncryptionKey)
            return String(data: decrypted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static let keySalt = ".com.claudemonitor"

    private static let cachedEncryptionKey: SymmetricKey = {
        let material = hardwareUUID() + keySalt
        let hash = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: hash)
    }()

    private static func hardwareUUID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        if let property = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0),
           let uuid = property.takeRetainedValue() as? String {
            return uuid
        }
        return persistedFallbackUUID()
    }

    private static func persistedFallbackUUID() -> String {
        let service = "com.claudemonitor.encryption"
        let account = "fallbackUUID"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let uuid = String(data: data, encoding: .utf8) {
            return uuid
        }
        let uuid = UUID().uuidString
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(uuid.utf8),
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
        return uuid
    }
}
