import CryptoKit
import Foundation

// Verify with the public key embedded in the distributed app, not the signing key.
let args = CommandLine.arguments
guard args.count == 4,
       let publicKeyData = Data(base64Encoded: args[2]),
       let signature = Data(base64Encoded: args[3]) else {
    fputs("Usage: swift verify_update.swift <archive> <public-key> <signature>\n", stderr)
    exit(2)
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        fputs("Update signature does not match the app's public key.\n", stderr)
        exit(1)
    }
} catch {
    fputs("Update signature verification failed.\n", stderr)
    exit(1)
}
