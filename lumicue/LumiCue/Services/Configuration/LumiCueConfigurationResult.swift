//
//  LumiCueConfigurationResult.swift
//  LumiCue
//
//  Import/export result models for TOML configuration.
//

import Foundation

enum LumiCueConfigurationIssueSeverity: Sendable {
  case warning
  case error
}

struct LumiCueConfigurationIssue: Identifiable, Sendable {
  let id = UUID()
  let severity: LumiCueConfigurationIssueSeverity
  let message: String
}

struct LumiCueConfigurationImportResult: Sendable {
  let appliedChangeCount: Int
  let issues: [LumiCueConfigurationIssue]

  var hasErrors: Bool {
    issues.contains { $0.severity == .error }
  }
}

enum LumiCueConfigurationSyncDecision: Equatable, Sendable {
  case alreadyCurrent
  case syncAutomatically
  case askBeforeReplacing
}

enum LumiCueConfigurationSyncStatus: Equatable, Sendable {
  case alreadyCurrent
  case synced
  case needsConfirmation
  case permissionRequired
}

struct LumiCueConfigurationSyncResult: Sendable {
  let status: LumiCueConfigurationSyncStatus
  let fileURL: URL
  let observedFileSignature: String?
  let exportedSettingsSignature: String?

  nonisolated init(
    status: LumiCueConfigurationSyncStatus,
    fileURL: URL,
    observedFileSignature: String? = nil,
    exportedSettingsSignature: String? = nil
  ) {
    self.status = status
    self.fileURL = fileURL
    self.observedFileSignature = observedFileSignature
    self.exportedSettingsSignature = exportedSettingsSignature
  }
}

enum LumiCueConfigurationSyncError: LocalizedError, Sendable {
  case fileChangedSinceConfirmation

  var errorDescription: String? {
    switch self {
    case .fileChangedSinceConfirmation:
      return "config.toml changed. Review it and try again."
    }
  }
}
