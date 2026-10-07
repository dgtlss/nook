import Foundation
import Security

// Developer tooling only. This file is never included in Nook.app.
let service = "dev.nathanlanger.Nook.Spaces"
let account = "nook-release-publisher"
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account
]

func fail(_ status: OSStatus) -> Never {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

switch CommandLine.arguments.dropFirst().first {
case "store":
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let credentials = try? JSONSerialization.jsonObject(with: data) as? [String: String],
          let key = credentials["accessKeyId"], !key.isEmpty,
          let secret = credentials["secretAccessKey"], !secret.isEmpty,
          credentials.count == 2 else { fail(errSecParam) }
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrLabel as String] = "Nook release uploads — nook-releases"
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { fail(status) }
    print("Nook publishing credentials saved in Keychain.")
case "read":
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { fail(status) }
    // The publisher captures this pipe internally; never log the returned data.
    FileHandle.standardOutput.write(data)
default:
    FileHandle.standardError.write(Data("Usage: spaces-keychain.swift store|read\n".utf8))
    exit(1)
}
