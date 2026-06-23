//
//  AnnotationSessionStore.swift
//  Snapzy
//
//  Sidecar persistence for committed editable annotation sessions.
//

import CryptoKit
import Foundation

@MainActor
final class AnnotationSessionStore {
  static let shared = AnnotationSessionStore()

  private let fileManager: FileManager
  private let rootDirectory: URL

  init(
    rootDirectory: URL = AnnotationSessionStore.defaultRootDirectory(),
    fileManager: FileManager = .default
  ) {
    self.rootDirectory = rootDirectory
    self.fileManager = fileManager
  }

  func load(for sourceURL: URL) -> AnnotationSessionData? {
    let normalizedPath = Self.normalizedPath(for: sourceURL)
    let pathHash = Self.pathHash(for: normalizedPath)
    let directory = sessionDirectory(pathHash: pathHash)
    let manifestURL = directory.appendingPathComponent("manifest.json")

    guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
    guard let manifest = readManifest(at: manifestURL),
          manifest.schemaVersion == PersistedAnnotationSession.currentSchemaVersion,
          manifest.sourceFilePathHash == pathHash,
          manifest.sourceFilePath == normalizedPath,
          let currentSignature = fileSignature(for: sourceURL),
          currentSignature == manifest.sourceSignature else {
      return nil
    }

    do {
      let originalData = try Data(contentsOf: directory.appendingPathComponent(manifest.originalFileName))
      let cutoutData = try manifest.cutoutFileName.map {
        try Data(contentsOf: directory.appendingPathComponent($0))
      }
      let assetsDirectory = directory.appendingPathComponent("assets", isDirectory: true)
      var embeddedAssets: [UUID: Data] = [:]
      for (assetIdString, fileName) in manifest.embeddedAssetFileNames {
        guard let assetId = UUID(uuidString: assetIdString) else { continue }
        let data = try Data(contentsOf: assetsDirectory.appendingPathComponent(fileName))
        embeddedAssets[assetId] = data
      }
      return manifest.sessionData(
        originalImageData: originalData,
        cutoutImageData: cutoutData,
        embeddedImageAssetsData: embeddedAssets
      )
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar load failed")
      return nil
    }
  }

  @discardableResult
  func persist(_ sessionData: AnnotationSessionData, for sourceURL: URL) -> Bool {
    let normalizedPath = Self.normalizedPath(for: sourceURL)
    let pathHash = Self.pathHash(for: normalizedPath)
    guard let signature = fileSignature(for: sourceURL) else { return false }

    let directory = sessionDirectory(pathHash: pathHash)
    let previousCreatedAt = readManifest(
      at: directory.appendingPathComponent("manifest.json")
    )?.createdAt ?? Date()
    let manifest = PersistedAnnotationSession(
      sessionData: sessionData,
      sourceFilePath: normalizedPath,
      sourceFilePathHash: pathHash,
      sourceSignature: signature,
      createdAt: previousCreatedAt
    )

    do {
      try writePackage(
        manifest: manifest,
        sessionData: sessionData,
        to: directory
      )
      DiagnosticLogger.shared.log(
        .debug,
        .annotate,
        "Annotation sidecar persisted",
        context: ["fileName": sourceURL.lastPathComponent, "annotations": "\(sessionData.annotations.count)"]
      )
      return true
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar persist failed")
      return false
    }
  }

  @discardableResult
  func moveSession(from oldURL: URL, to newURL: URL) -> Bool {
    let oldPath = Self.normalizedPath(for: oldURL)
    let oldHash = Self.pathHash(for: oldPath)
    let oldDirectory = sessionDirectory(pathHash: oldHash)
    guard fileManager.fileExists(atPath: oldDirectory.path) else { return false }

    let newPath = Self.normalizedPath(for: newURL)
    let newHash = Self.pathHash(for: newPath)
    let newDirectory = sessionDirectory(pathHash: newHash)
    guard oldDirectory.standardizedFileURL != newDirectory.standardizedFileURL else { return true }
    guard let signature = fileSignature(for: newURL),
          var manifest = readManifest(at: oldDirectory.appendingPathComponent("manifest.json")) else {
      return false
    }

    manifest.sourceFilePath = newPath
    manifest.sourceFilePathHash = newHash
    manifest.sourceSignature = signature
    manifest.updatedAt = Date()

    do {
      try ensureRootDirectory()
      if fileManager.fileExists(atPath: newDirectory.path) {
        try fileManager.removeItem(at: newDirectory)
      }
      try fileManager.moveItem(at: oldDirectory, to: newDirectory)
      try writeManifest(manifest, to: newDirectory.appendingPathComponent("manifest.json"))
      return true
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar move failed")
      return false
    }
  }

  func deleteSession(for sourceURL: URL) {
    let pathHash = Self.pathHash(for: Self.normalizedPath(for: sourceURL))
    let directory = sessionDirectory(pathHash: pathHash)
    guard fileManager.fileExists(atPath: directory.path) else { return }
    do {
      try fileManager.removeItem(at: directory)
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar delete failed")
    }
  }

  func cleanup(keepingScreenshotFilePaths paths: Set<String>) {
    guard let contents = try? fileManager.contentsOfDirectory(
      at: rootDirectory,
      includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return }

    let activePaths = Set(paths.map(Self.normalizedPath(forPath:)))
    for directory in contents {
      let manifestURL = directory.appendingPathComponent("manifest.json")
      guard let manifest = readManifest(at: manifestURL) else {
        try? fileManager.removeItem(at: directory)
        continue
      }

      let sourceURL = URL(fileURLWithPath: manifest.sourceFilePath)
      let shouldKeep = activePaths.contains(manifest.sourceFilePath)
        && fileManager.fileExists(atPath: manifest.sourceFilePath)
        && fileSignature(for: sourceURL) == manifest.sourceSignature
      if !shouldKeep {
        try? fileManager.removeItem(at: directory)
      }
    }
  }

  func deleteAllSessions() {
    guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
    do {
      try fileManager.removeItem(at: rootDirectory)
    } catch {
      DiagnosticLogger.shared.logError(.annotate, error, "Annotation sidecar clear failed")
    }
  }

  func shouldPersist(for sourceURL: URL) -> Bool {
    let historyEnabled = CaptureHistoryStore.shared.userDefaults.bool(forKey: PreferencesKeys.historyEnabled)
    return historyEnabled || CaptureHistoryStore.shared.hasRecord(forFilePath: sourceURL.path)
  }

  nonisolated static func normalizedPath(for sourceURL: URL) -> String {
    normalizedPath(forPath: sourceURL.standardizedFileURL.path)
  }

  nonisolated static func normalizedPath(forPath path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }

  nonisolated static func pathHash(for normalizedPath: String) -> String {
    let digest = SHA256.hash(data: Data(normalizedPath.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  nonisolated private static func defaultRootDirectory() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("AnnotationSessions", isDirectory: true)
  }

  private func sessionDirectory(pathHash: String) -> URL {
    rootDirectory.appendingPathComponent(pathHash, isDirectory: true)
  }

  private func ensureRootDirectory() throws {
    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
  }

  private func fileSignature(for sourceURL: URL) -> PersistedFileSignature? {
    let scopedAccess = SandboxFileAccessManager.shared.beginAccessingURL(sourceURL)
    defer { scopedAccess.stop() }

    guard let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path) else {
      return nil
    }
    let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let modifiedAtMs = Int64((modifiedAt * 1000).rounded())
    let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    return PersistedFileSignature(
      fileSize: fileSize,
      modifiedAtMilliseconds: modifiedAtMs,
      pathExtension: sourceURL.pathExtension.lowercased()
    )
  }

  private func readManifest(at url: URL) -> PersistedAnnotationSession? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(PersistedAnnotationSession.self, from: data)
  }

  private func writePackage(
    manifest: PersistedAnnotationSession,
    sessionData: AnnotationSessionData,
    to directory: URL
  ) throws {
    try ensureRootDirectory()
    let tempDirectory = rootDirectory.appendingPathComponent(".\(directory.lastPathComponent).\(UUID().uuidString)", isDirectory: true)
    let assetsDirectory = tempDirectory.appendingPathComponent("assets", isDirectory: true)
    try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    do {
      try sessionData.originalImageData.write(to: tempDirectory.appendingPathComponent(manifest.originalFileName), options: .atomic)
      if let cutoutFileName = manifest.cutoutFileName, let cutoutImageData = sessionData.cutoutImageData {
        try cutoutImageData.write(to: tempDirectory.appendingPathComponent(cutoutFileName), options: .atomic)
      }
      for (assetIdString, fileName) in manifest.embeddedAssetFileNames {
        guard let assetId = UUID(uuidString: assetIdString),
              let data = sessionData.embeddedImageAssetsData[assetId] else { continue }
        try data.write(to: assetsDirectory.appendingPathComponent(fileName), options: .atomic)
      }
      try writeManifest(manifest, to: tempDirectory.appendingPathComponent("manifest.json"))
      if fileManager.fileExists(atPath: directory.path) {
        try fileManager.removeItem(at: directory)
      }
      try fileManager.moveItem(at: tempDirectory, to: directory)
    } catch {
      try? fileManager.removeItem(at: tempDirectory)
      throw error
    }
  }

  private func writeManifest(_ manifest: PersistedAnnotationSession, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(manifest).write(to: url, options: .atomic)
  }
}
