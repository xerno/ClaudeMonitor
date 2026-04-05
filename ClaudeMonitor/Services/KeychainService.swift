import CryptoKit
import Foundation
import IOKit

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
            let sealed = try AES.GCM.seal(plaintext, using: encryptionKey())
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
            let decrypted = try AES.GCM.open(box, using: encryptionKey())
            return String(data: decrypted, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func encryptionKey() -> SymmetricKey {
        let material = hardwareUUID() + ".com.claudemonitor"
        let hash = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: hash)
    }

    private static func hardwareUUID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0) else {
            return "fallback"
        }
        return property.takeRetainedValue() as? String ?? "fallback"
    }
}
