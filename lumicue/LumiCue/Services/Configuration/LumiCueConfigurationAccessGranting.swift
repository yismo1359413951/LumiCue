//
//  LumiCueConfigurationAccessGranting.swift
//  LumiCue
//
//  Shared macOS folder-grant flow for the user-managed TOML configuration file.
//

import AppKit
import Foundation

struct LumiCueConfigurationAccessGrantResult {
  let configURL: URL
  let autoImportResult: LumiCueConfigurationAutoImportResult
}

enum LumiCueConfigurationAccessGrantError: LocalizedError {
  case unexpectedDirectory(expectedPath: String)

  var errorDescription: String? {
    switch self {
    case .unexpectedDirectory(let expectedPath):
      return L10n.PreferencesAdvanced.configDirectoryMismatch(expectedPath)
    }
  }
}

@MainActor
enum LumiCueConfigurationAccessGranting {
  static func grantSuggestedConfigAccess(
    title: String? = nil,
    message: String? = nil,
    prompt: String? = nil
  ) throws -> LumiCueConfigurationAccessGrantResult? {
    try grantSuggestedConfigAccess(
      service: .shared,
      title: title,
      message: message,
      prompt: prompt
    )
  }

  static func grantSuggestedConfigAccess(
    service: LumiCueConfigurationService,
    title: String? = nil,
    message: String? = nil,
    prompt: String? = nil
  ) throws -> LumiCueConfigurationAccessGrantResult? {
    try? FileManager.default.createDirectory(
      at: service.suggestedConfigDirectoryURL,
      withIntermediateDirectories: true
    )

    let panel = NSOpenPanel()
    panel.title = title ?? L10n.PreferencesAdvanced.configDirectoryPanelTitle
    panel.message = message ?? L10n.PreferencesAdvanced.configDirectoryPanelMessage(
      service.suggestedConfigDirectoryURL.path
    )
    panel.prompt = prompt ?? L10n.PreferencesAdvanced.configDirectoryPanelPrompt
    panel.directoryURL = initialDirectoryURL(for: service)
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true

    guard panel.runModal() == .OK, let selectedURL = panel.url?.standardizedFileURL else {
      return nil
    }

    let didStartAccessingSelection = selectedURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccessingSelection {
        selectedURL.stopAccessingSecurityScopedResource()
      }
    }

    let configDirectoryURL = try resolvedConfigDirectory(from: selectedURL, service: service)
    try FileManager.default.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)
    try service.rememberConfigDirectoryAccess(configDirectoryURL)
    let configURL = try service.ensureConfigExists(at: service.configFileURL(inDirectory: configDirectoryURL))
    let autoImportResult = LumiCueConfigurationAutoImporter.applyIfNeeded(from: configURL)

    return LumiCueConfigurationAccessGrantResult(
      configURL: configURL,
      autoImportResult: autoImportResult
    )
  }

  private static func initialDirectoryURL(for service: LumiCueConfigurationService) -> URL {
    let fileManager = FileManager.default
    let suggestedDirectory = service.suggestedConfigDirectoryURL
    if fileManager.fileExists(atPath: suggestedDirectory.path) {
      return suggestedDirectory
    }

    let parentDirectory = service.suggestedConfigParentDirectoryURL
    if fileManager.fileExists(atPath: parentDirectory.path) {
      return parentDirectory
    }

    return service.suggestedConfigRootDirectoryURL
  }

  private static func resolvedConfigDirectory(
    from selectedURL: URL,
    service: LumiCueConfigurationService
  ) throws -> URL {
    if service.isSuggestedConfigDirectory(selectedURL) {
      return selectedURL
    }

    if service.isSuggestedConfigParentDirectory(selectedURL) {
      return service.suggestedConfigDirectoryURL
    }

    if service.isSuggestedConfigRootDirectory(selectedURL) {
      return service.suggestedConfigDirectoryURL
    }

    throw LumiCueConfigurationAccessGrantError.unexpectedDirectory(
      expectedPath: service.suggestedConfigDirectoryURL.path
    )
  }
}
