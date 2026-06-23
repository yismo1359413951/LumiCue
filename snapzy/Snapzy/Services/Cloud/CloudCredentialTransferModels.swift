//
//  CloudCredentialTransferModels.swift
//  Snapzy
//
//  Versioned models for encrypted cloud credential transfer archives.
//

import Foundation

struct CloudCredentialTransferPayload: Codable, Equatable {
  let configuration: CloudConfiguration
  let accessKey: String
  let secretKey: String

  var providerDisplayName: String {
    configuration.providerType.displayName
  }
}

struct CloudCredentialTransferEnvelope: Codable {
  let schemaVersion: Int
  let algorithm: String
  let kdf: String
  let salt: String
  let iterations: Int
  let nonce: String
  let ciphertext: String
  let tag: String
}
