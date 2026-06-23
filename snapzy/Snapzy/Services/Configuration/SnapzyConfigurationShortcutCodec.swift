//
//  SnapzyConfigurationShortcutCodec.swift
//  Snapzy
//
//  Friendly TOML shortcut key/modifier conversion.
//

import Carbon.HIToolbox
import Foundation

enum SnapzyConfigurationShortcutCodec {
  static func exportKey(_ config: ShortcutConfig) -> String {
    ShortcutConfig.keyCodeToString(config.keyCode)
  }

  static func exportModifiers(_ config: ShortcutConfig) -> [String] {
    var values: [String] = []
    if config.modifiers & UInt32(cmdKey) != 0 { values.append("command") }
    if config.modifiers & UInt32(shiftKey) != 0 { values.append("shift") }
    if config.modifiers & UInt32(optionKey) != 0 { values.append("option") }
    if config.modifiers & UInt32(controlKey) != 0 { values.append("control") }
    return values
  }

  static func shortcut(key: String, modifiers: [String], requireModifier: Bool) -> ShortcutConfig? {
    guard let keyCode = keyCode(for: key) else { return nil }
    guard let carbonModifiers = self.carbonModifiers(from: modifiers) else { return nil }
    guard !requireModifier || carbonModifiers != 0 else { return nil }
    return ShortcutConfig(keyCode: keyCode, modifiers: carbonModifiers)
  }

  static func overlayShortcut(key: String, modifiers: [String]) -> CaptureOverlayShortcut? {
    guard let keyCode = keyCode(for: key) else { return nil }
    guard let carbonModifiers = carbonModifiers(from: modifiers) else { return nil }
    return CaptureOverlayShortcut(keyCode: keyCode, modifiers: carbonModifiers)
  }

  private static func carbonModifiers(from modifiers: [String]) -> UInt32? {
    var carbonModifiers: UInt32 = 0
    for modifier in modifiers.map({ $0.lowercased() }) {
      switch modifier {
      case "command", "cmd":
        carbonModifiers |= UInt32(cmdKey)
      case "shift":
        carbonModifiers |= UInt32(shiftKey)
      case "option", "alt":
        carbonModifiers |= UInt32(optionKey)
      case "control", "ctrl":
        carbonModifiers |= UInt32(controlKey)
      default:
        return nil
      }
    }
    return carbonModifiers
  }

  private static func keyCode(for key: String) -> UInt32? {
    switch key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "0": return UInt32(kVK_ANSI_0)
    case "1": return UInt32(kVK_ANSI_1)
    case "2": return UInt32(kVK_ANSI_2)
    case "3": return UInt32(kVK_ANSI_3)
    case "4": return UInt32(kVK_ANSI_4)
    case "5": return UInt32(kVK_ANSI_5)
    case "6": return UInt32(kVK_ANSI_6)
    case "7": return UInt32(kVK_ANSI_7)
    case "8": return UInt32(kVK_ANSI_8)
    case "9": return UInt32(kVK_ANSI_9)
    case "A": return UInt32(kVK_ANSI_A)
    case "B": return UInt32(kVK_ANSI_B)
    case "C": return UInt32(kVK_ANSI_C)
    case "D": return UInt32(kVK_ANSI_D)
    case "E": return UInt32(kVK_ANSI_E)
    case "F": return UInt32(kVK_ANSI_F)
    case "G": return UInt32(kVK_ANSI_G)
    case "H": return UInt32(kVK_ANSI_H)
    case "I": return UInt32(kVK_ANSI_I)
    case "J": return UInt32(kVK_ANSI_J)
    case "K": return UInt32(kVK_ANSI_K)
    case "L": return UInt32(kVK_ANSI_L)
    case "M": return UInt32(kVK_ANSI_M)
    case "N": return UInt32(kVK_ANSI_N)
    case "O": return UInt32(kVK_ANSI_O)
    case "P": return UInt32(kVK_ANSI_P)
    case "Q": return UInt32(kVK_ANSI_Q)
    case "R": return UInt32(kVK_ANSI_R)
    case "S": return UInt32(kVK_ANSI_S)
    case "T": return UInt32(kVK_ANSI_T)
    case "U": return UInt32(kVK_ANSI_U)
    case "V": return UInt32(kVK_ANSI_V)
    case "W": return UInt32(kVK_ANSI_W)
    case "X": return UInt32(kVK_ANSI_X)
    case "Y": return UInt32(kVK_ANSI_Y)
    case "Z": return UInt32(kVK_ANSI_Z)
    case "SPACE": return UInt32(kVK_Space)
    default: return nil
    }
  }
}
