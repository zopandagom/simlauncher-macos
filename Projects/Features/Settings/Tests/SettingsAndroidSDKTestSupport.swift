import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

/// "Android SDK 위치" 절 테스트가 함께 쓰는 값과 호출 세기.
@MainActor
protocol SettingsAndroidSDKTesting: SettingsModelTesting {}

@MainActor
extension SettingsAndroidSDKTesting {
  static var chosen: URL {
    URL(filePath: "/Volumes/Tools/AndroidSDK", directoryHint: .isDirectory)
  }

  static var other: URL {
    URL(filePath: "/Users/tester/Documents", directoryHint: .isDirectory)
  }

  static var defaultURL: URL {
    AndroidSDKRoot.defaultURL(home: testHome)
  }

  static var chosenPath: String {
    chosen.path(percentEncoded: false)
  }

  static func stored(_ path: String, isLocked: Bool = false) -> AndroidSDKPathSetting {
    AndroidSDKPathSetting(value: .path(path), isLocked: isLocked)
  }

  /// `setAndroidSDKPath` 호출들.
  static func sdkWrites(_ preferences: PreferencesClientFake) -> [String?] {
    preferences.calls.compactMap {
      if case let .setAndroidSDKPath(path) = $0 {
        path
      } else {
        nil
      }
    }
  }

  static func sdkWriteCount(_ preferences: PreferencesClientFake) -> Int {
    preferences.calls.filter {
      if case .setAndroidSDKPath = $0 {
        true
      } else {
        false
      }
    }.count
  }

  static func inspectCount(_ androidSDK: AndroidSDKClientFake) -> Int {
    androidSDK.calls.filter {
      if case .inspectCandidateFolder = $0 {
        true
      } else {
        false
      }
    }.count
  }
}
