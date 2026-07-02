//
//  LumiCueConfigurationAutoImporter.swift
//  LumiCue
//
//  Applies user-edited TOML configuration on app launch when the file changes.
//

import CryptoKit
import Foundation

enum LumiCueConfigurationAutoImportStatus: Equatable {
  case applied
  case failed
  case skippedMissingFile
  case skippedPermissionRequired
  case skippedUnchanged
}

struct LumiCueConfigurationAutoImportResult {
  let status: LumiCueConfigurationAutoImportStatus
  let fileURL: URL
  let importResult: LumiCueConfigurationImportResult?
  let errorMessage: String?

  var appliedChangeCount: Int {
    importResult?.appliedChangeCount ?? 0
  }

  var warningCount: Int {
    importResult?.issues.filter { $0.severity == .warning }.count ?? 0
  }

  var errorCount: Int {
    importResult?.issues.filter { $0.severity == .error }.count ?? 0
  }
}

@MainActor
enum LumiCueConfigurationAutoImporter {
  static func applyIfNeededOnLaunch(
    defaults: UserDefaults = .standard
  ) -> LumiCueConfigurationAutoImportResult {
    applyIfNeededOnLaunch(service: .shared, defaults: defaults)
  }

  static func applyIfNeededOnLaunch(
    service: LumiCueConfigurationService,
    defaults: UserDefaults = .standard
  ) -> LumiCueConfigurationAutoImportResult {
    if service.needsUserSelectedConfigAccess {
      return LumiCueConfigurationAutoImportResult(
        status: .skippedPermissionRequired,
        fileURL: service.resolvedConfigFileURL,
        importResult: nil,
        errorMessage: nil
      )
    }

    let access = service.beginAccessingConfigFile()
    defer { access.stop() }

    return applyIfNeeded(from: access.url, defaults: defaults)
  }

  static func applyIfNeeded(
    from fileURL: URL,
    defaults: UserDefaults = .standard
  ) -> LumiCueConfigurationAutoImportResult {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return LumiCueConfigurationAutoImportResult(
        status: .skippedMissingFile,
        fileURL: fileURL,
        importResult: nil,
        errorMessage: nil
      )
    }

    let source: String
    do {
      source = try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
      return LumiCueConfigurationAutoImportResult(
        status: .failed,
        fileURL: fileURL,
        importResult: nil,
        errorMessage: error.localizedDescription
      )
    }

    let signature = contentSignature(for: source)
    if defaults.string(forKey: PreferencesKeys.configurationLastAppliedSignature) == signature {
      return LumiCueConfigurationAutoImportResult(
        status: .skippedUnchanged,
        fileURL: fileURL,
        importResult: nil,
        errorMessage: nil
      )
    }

    let importResult = LumiCueConfigurationImporter.importTOML(source, defaults: defaults)
    if importResult.hasErrors {
      return LumiCueConfigurationAutoImportResult(
        status: .failed,
        fileURL: fileURL,
        importResult: importResult,
        errorMessage: nil
      )
    }

    defaults.set(signature, forKey: PreferencesKeys.configurationLastAppliedSignature)
    return LumiCueConfigurationAutoImportResult(
      status: .applied,
      fileURL: fileURL,
      importResult: importResult,
      errorMessage: nil
    )
  }

  static func markCurrentFileApplied(_ source: String, defaults: UserDefaults = .standard) {
    let signature = contentSignature(for: source)
    guard defaults.string(forKey: PreferencesKeys.configurationLastAppliedSignature) != signature else { return }
    defaults.set(signature, forKey: PreferencesKeys.configurationLastAppliedSignature)
  }

  static func isCurrentFileApplied(_ source: String, defaults: UserDefaults = .standard) -> Bool {
    defaults.string(forKey: PreferencesKeys.configurationLastAppliedSignature) == contentSignature(for: source)
  }

  nonisolated static func contentSignature(for source: String) -> String {
    let digest = SHA256.hash(data: Data(source.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
