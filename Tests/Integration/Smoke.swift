import AppKit
import Foundation
import PathBridgeCore

/// Opt-in integration harness. No network/filesystem writes to SMB shares.
/// Credentials are accepted through stdin only; they are never logged.
@main
struct Smoke {
    @MainActor static func main() async {
        _ = NSApplication.shared
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 2 else { throw AppError.message("Usage: smoke seed <configuration.json> | inspect | mount <storage-id>") }
            if arguments[1] == "mount-table-tests" {
                let fixtures: [(String, String, String)] = [
                    ("//DOMAIN;test@example.com/share", "example.com", "share"),
                    ("//test%40example.com@example.com/中文%20目录", "example.com", "中文 目录"),
                    ("//example.com/a%2520b", "example.com", "a%20b"),
                    ("//test@[2001:db8::1]/share", "[2001:db8::1]", "share")
                ]
                for (source, server, share) in fixtures {
                    let parsed = SMBMountSnapshot.parse(source: source, mountPath: "/Volumes/literal%20name")
                    guard parsed?.server == server, parsed?.share == share, parsed?.path == "/Volumes/literal%20name" else {
                        throw AppError.message("Mount table decoding fixture failed.")
                    }
                }
                for source in ["//example.com/share/subdir", "//example.com/a%2Fb", "//example.com/%FF", "//example.com/..", "//example.com/"] {
                    guard SMBMountSnapshot.parse(source: source, mountPath: "/Volumes/test") == nil else {
                        throw AppError.message("Invalid mount source was accepted.")
                    }
                }
                print("PASS: mount table decoding, credential removal, literal mount names and invalid sources")
                return
            }
            let store = SettingsStore()
            if arguments[1] == "primary-from-storage" {
                guard arguments.count == 3, let saved = try CredentialStore.read(storageID: arguments[2]) else {
                    throw AppError.message("A saved test credential is required.")
                }
                let primary = PrimaryCredential(username: saved.username, password: saved.password)
                if let existing = try CredentialStore.readPrimary(), existing != primary {
                    throw AppError.message("Refusing to replace a different primary credential.")
                }
                try CredentialStore.savePrimary(primary)
                guard try CredentialStore.readPrimary() == primary else { throw AppError.message("Primary Keychain round trip failed.") }
                let unknown = try CredentialStore.connectionCredential(storageID: nil, server: "unknown.example.com", share: "share")
                guard unknown?.username == primary.username, unknown?.password == primary.password else {
                    throw AppError.message("Unmapped path did not select primary credential.")
                }
                let testID = "credential-priority-test-" + UUID().uuidString
                defer { try? CredentialStore.save(nil, storageID: testID) }
                let scoped = SMBCredential(username: "scoped-test", password: "integration-only", server: "configured.example.com", share: "share")
                try CredentialStore.save(scoped, storageID: testID)
                guard try CredentialStore.connectionCredential(storageID: testID, server: scoped.server, share: scoped.share) == scoped else {
                    throw AppError.message("Scoped credential did not take priority.")
                }
                let mismatch = try CredentialStore.connectionCredential(storageID: testID, server: "other.example.com", share: "share")
                guard mismatch?.username == primary.username, mismatch?.password == primary.password else {
                    throw AppError.message("Changed endpoint did not select primary credential.")
                }
                try CredentialStore.save(nil, storageID: testID)
                let missing = try CredentialStore.connectionCredential(storageID: testID, server: scoped.server, share: scoped.share)
                guard missing?.username == primary.username else { throw AppError.message("Missing scoped credential did not fall back.") }
                print("PASS: primary Keychain round trip; scoped > primary; unmapped/missing/mismatched scope uses primary; temporary credential removed")
                return
            }
            if arguments[1] == "seed" {
                guard arguments.count == 3 else { throw AppError.message("A configuration file is required.") }
                let configuration = try SettingsStore.decode(Data(contentsOf: URL(fileURLWithPath: arguments[2])))
                guard store.configuration.storages.isEmpty else { throw AppError.message("Refusing to replace existing configuration.") }
                let input = FileHandle.standardInput.readDataToEndOfFile()
                struct Login: Decodable { let username: String; let password: String }
                let login = try JSONDecoder().decode(Login.self, from: input)
                for mapping in configuration.storages {
                    try CredentialStore.save(SMBCredential(username: login.username, password: login.password, server: mapping.server, share: mapping.share), storageID: mapping.id)
                    guard let saved = try CredentialStore.read(storageID: mapping.id), saved.username == login.username, saved.password == login.password else { throw AppError.message("Credential round trip failed.") }
                }
                try store.save(configuration)
                print("PASS: configuration saved; Keychain credential round trip verified; no credentials exported")
                return
            }
            let volumes = VolumeManager()
            await volumes.refresh()
            if arguments[1] == "prepare-unmapped" {
                guard arguments.count == 3 else { throw AppError.message("An SMB URL is required.") }
                let url = try PathResolver(mappings: []).smbURL(for: arguments[2])
                let share = url.pathComponents.dropFirst().first ?? ""
                let reused = volumes.mounted.contains { $0.server.caseInsensitiveCompare(url.host ?? "") == .orderedSame && $0.share.caseInsensitiveCompare(share) == .orderedSame }
                guard try CredentialStore.readPrimary() != nil else { throw AppError.message("A primary credential is required for this integration check.") }
                try await volumes.prepareUnmappedURL(url)
                print("PASS: unmapped SMB prepared with primary credential; prior matching mount = \(reused)")
                return
            }
            for mapping in store.configuration.storages {
                print("Storage \(mapping.id): \(volumes.mountPath(for: mapping) ?? "not mounted")")
            }
            if arguments[1] == "mount" {
                guard arguments.count == 3, let mapping = store.configuration.storages.first(where: { $0.id == arguments[2] }) else { throw AppError.message("Unknown Storage ID") }
                let path = try await volumes.ensureMounted(mapping)
                let isDirectory = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                guard isDirectory == true else { throw AppError.message("Storage root is not a directory") }
                print("PASS: SMB mounted and directory readable at \(path)")
            }
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
}
