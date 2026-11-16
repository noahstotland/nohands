import Foundation
import NoHandsCore
import NoHandsMac

/// `nohands-cli registry keygen|sign`: what a registry's publisher runs. No network: the files are read and written locally.
func registryCommand(_ args: [String]) {
    switch (args.first, args.count) {
    case ("keygen", 2): keygen(path: args[1])
    case ("sign", 4), ("sign", 6): sign(Array(args.dropFirst()))
    default: usage()
    }
}

private func keygen(path: String) {
    do {
        let made = try RegistrySigner.keygen(to: path)
        print("private key written to \(path) (mode 600). Keep it off any server and never commit it.")
        print("public key (users put this in packRegistryKey): \(made.publicKeyBase64)")
        print("key id: \(made.keyID)")
    } catch { fail("error: \(describe(error))") }
}

/// `sign <index.json> --key <path> [--packs <dir>]`, the two flags in either order.
private func sign(_ args: [String]) {
    var flags: [String: String] = [:]
    var rest = Array(args.dropFirst())
    while !rest.isEmpty {
        guard rest.count >= 2, ["--key", "--packs"].contains(rest[0]), flags[rest[0]] == nil else { usage() }
        flags[rest[0]] = rest[1]
        rest.removeFirst(2)
    }
    guard let keyPath = flags["--key"] else { usage() }
    do {
        let key = try RegistrySigner.readPrivateKey(at: keyPath)
        let signed = try RegistrySigner.signAndRead(indexJSON: readLimitedFile(args[0], limit: RegistryIndex.maxEnvelopeBytes), privateKey: key)
        if let dir = flags["--packs"] {
            let problems = RegistrySigner.checkPacks(signed.index, directory: URL(fileURLWithPath: dir, isDirectory: true))
            guard problems.isEmpty else { fail("not signed; pack files don't match the index:\n" + problems.map { "  " + $0 }.joined(separator: "\n")) }
        }
        print(String(decoding: signed.envelope, as: UTF8.self))
    } catch { fail("error: \(describe(error))") }
}

private func describe(_ error: any Error) -> String {
    (error as? RegistrySigner.SignerError)?.reason ?? "\(error)"
}
