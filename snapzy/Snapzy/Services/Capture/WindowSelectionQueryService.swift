//
//  WindowSelectionQueryService.swift
//  Snapzy
//
//  Builds ordered window candidates for screenshot application mode.
//

import AppKit
import Foundation
import ScreenCaptureKit

struct WindowSelectionCandidate: Equatable {
  let target: WindowCaptureTarget
  let ownerName: String
  let windowLayer: Int

  func contains(_ point: CGPoint) -> Bool {
    target.frame.contains(point)
  }
}

struct WindowSelectionSnapshot {
  let orderedCandidates: [WindowSelectionCandidate]

  func hitTest(at point: CGPoint) -> WindowSelectionCandidate? {
    orderedCandidates.first { $0.contains(point) }
  }
}

@MainActor
enum WindowSelectionQueryService {
  static func prepareSnapshot(
    prefetchedContentTask: ShareableContentPrefetchTask?,
    excludeOwnApplication: Bool
  ) async -> WindowSelectionSnapshot? {
    do {
      let content = try await loadShareableContent(prefetchedContentTask: prefetchedContentTask)
      let shareableWindowsByID = Dictionary(
        uniqueKeysWithValues: content.windows.filter { $0.isOnScreen }.map { ($0.windowID, $0) }
      )
      let ownBundleIdentifier = Bundle.main.bundleIdentifier
      guard
        let rawWindowInfo = CGWindowListCopyWindowInfo(
          [.optionOnScreenOnly, .excludeDesktopElements],
          kCGNullWindowID
        ) as? [[String: Any]]
      else {
        return WindowSelectionSnapshot(orderedCandidates: [])
      }

      var seenWindowIDs = Set<CGWindowID>()
      var orderedCandidates: [WindowSelectionCandidate] = []

      for windowInfo in rawWindowInfo {
        guard let number = windowInfo[kCGWindowNumber as String] as? NSNumber else { continue }
        let windowID = CGWindowID(number.uint32Value)
        guard seenWindowIDs.insert(windowID).inserted else { continue }
        let shareableWindow = shareableWindowsByID[windowID]
        let windowLayer = windowLayer(from: windowInfo, shareableWindow: shareableWindow)
        guard windowLayer == 0 else { continue }
        guard let frame = windowFrame(from: windowInfo) else { continue }
        guard frame.width > 32, frame.height > 32 else { continue }
        guard let displayID = displayID(for: frame) else { continue }
        if let alpha = windowInfo[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue <= 0 {
          continue
        }

        let bundleIdentifier = bundleIdentifier(from: windowInfo, shareableWindow: shareableWindow)
        if excludeOwnApplication, bundleIdentifier == ownBundleIdentifier {
          continue
        }

        orderedCandidates.append(
          WindowSelectionCandidate(
            target: WindowCaptureTarget(
              windowID: windowID,
              frame: frame,
              displayID: displayID,
              title: windowTitle(from: windowInfo, shareableWindow: shareableWindow),
              bundleIdentifier: bundleIdentifier,
              ownerPID: (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            ),
            ownerName: ownerName(from: windowInfo, shareableWindow: shareableWindow),
            windowLayer: windowLayer
          )
        )
      }

      return WindowSelectionSnapshot(orderedCandidates: orderedCandidates)
    } catch {
      DiagnosticLogger.shared.logError(
        .capture,
        error,
        "Failed to prepare application mode window candidates"
      )
      return nil
    }
  }

  static func resolveWindow(
    windowID: CGWindowID,
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async -> SCWindow? {
    do {
      let content = try await loadShareableContent(prefetchedContentTask: prefetchedContentTask)
      if let prefetchedMatch = content.windows.first(where: { $0.windowID == windowID && $0.isOnScreen }) {
        return prefetchedMatch
      }

      let refreshedContent = try await SCShareableContent.current
      return refreshedContent.windows.first { $0.windowID == windowID && $0.isOnScreen }
    } catch {
      DiagnosticLogger.shared.logError(
        .capture,
        error,
        "Failed to resolve shareable window \(windowID)"
      )
      return nil
    }
  }

  private static func loadShareableContent(
    prefetchedContentTask: ShareableContentPrefetchTask?
  ) async throws -> SCShareableContent {
    if let prefetchedContentTask {
      return try await prefetchedContentTask.value
    }
    return try await SCShareableContent.current
  }

  private static func displayID(for frame: CGRect) -> CGDirectDisplayID? {
    let midpoint = CGPoint(x: frame.midX, y: frame.midY)
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
      return screen.displayID
    }

    var bestDisplayID: CGDirectDisplayID?
    var bestIntersectionArea: CGFloat = 0
    for screen in NSScreen.screens {
      let intersection = screen.frame.intersection(frame)
      let area = intersection.width * intersection.height
      if area > bestIntersectionArea {
        bestIntersectionArea = area
        bestDisplayID = screen.displayID
      }
    }
    return bestDisplayID
  }

  private static func windowFrame(from windowInfo: [String: Any]) -> CGRect? {
    guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
      return nil
    }
    guard let quartzRect = CGRect(dictionaryRepresentation: boundsDictionary)?.standardized else {
      return nil
    }
    return appKitGlobalRect(fromQuartzGlobalRect: quartzRect).integral
  }

  private static func windowLayer(
    from windowInfo: [String: Any],
    shareableWindow: SCWindow?
  ) -> Int {
    if let layer = windowInfo[kCGWindowLayer as String] as? NSNumber {
      return layer.intValue
    }
    return shareableWindow?.windowLayer ?? 0
  }

  private static func bundleIdentifier(
    from windowInfo: [String: Any],
    shareableWindow: SCWindow?
  ) -> String? {
    if let bundleIdentifier = shareableWindow?.owningApplication?.bundleIdentifier {
      return bundleIdentifier
    }

    guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber else {
      return nil
    }
    return NSRunningApplication(processIdentifier: ownerPID.int32Value)?.bundleIdentifier
  }

  private static func ownerName(
    from windowInfo: [String: Any],
    shareableWindow: SCWindow?
  ) -> String {
    if let applicationName = shareableWindow?.owningApplication?.applicationName, !applicationName.isEmpty {
      return applicationName
    }

    if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String {
      return ownerName
    }

    return ""
  }

  private static func windowTitle(
    from windowInfo: [String: Any],
    shareableWindow: SCWindow?
  ) -> String? {
    if let title = shareableWindow?.title, !title.isEmpty {
      return title
    }

    if let title = windowInfo[kCGWindowName as String] as? String, !title.isEmpty {
      return title
    }

    return nil
  }

  private static func appKitGlobalRect(fromQuartzGlobalRect rect: CGRect) -> CGRect {
    let mainScreenHeight = NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() })?.frame.height
      ?? CGDisplayBounds(CGMainDisplayID()).height

    return CGRect(
      x: rect.origin.x,
      y: mainScreenHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }
}
