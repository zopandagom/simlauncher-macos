import Foundation

/// Android SDK 위치 하나. 경로는 링크를 풀지 않은 값이다 (화면에 보이는 경로. 쓰기는 Impl 이 링크를 따라간 실제 폴더에 한다).
public struct AndroidSDKRoot: Hashable, Sendable {
  /// 폴더 파일 URL (`directoryHint: .isDirectory`, `standardizedFileURL`).
  public let url: URL
  /// 기본 위치(`~/Library/Android/sdk`)다. 기본 위치가 없으면 설치가 만들고, 고른 폴더가 없으면 만들지 않는다.
  public let isDefault: Bool

  public init(url: URL, isDefault: Bool) {
    self.url = url
    self.isDefault = isDefault
  }

  /// `home/Library/Android/sdk`. Android Studio 의 기본 SDK 위치와 같다.
  public static func defaultURL(home: URL) -> URL {
    self.folderURL(home.path(percentEncoded: false)).appending(path: "Library/Android/sdk", directoryHint: .isDirectory)
      .standardizedFileURL
  }

  /// 구성 요소의 맨 위 폴더 (`<root>/platform-tools`·`<root>/emulator`·`<root>/system-images`).
  public func folder(for component: AndroidSDKComponent) -> URL {
    self.url.appending(path: component.folderName, directoryHint: .isDirectory)
  }

  /// 패키지 경로의 구성 요소로 만든 최종 경로 (`<root>/system-images/android-37.0/google_apis/arm64-v8a`).
  /// 구성 요소는 `AndroidPackagePath` 가 검사한 값만 쓴다 (빈 것·`.`·`..`·`/`·NUL 없음).
  public func destination(for path: AndroidPackagePath) -> URL {
    var url = self.url
    for component in path.components {
      url = url.appending(path: component, directoryHint: .isDirectory)
    }
    return url
  }

  static func folderURL(_ path: String) -> URL {
    URL(filePath: path, directoryHint: .isDirectory)
  }
}

/// 설정에 저장된 Android SDK 위치 (Preferences 키 `AndroidSDKPath`)와 잠금 여부.
/// Core `AndroidSDKRootChoice.resolve` 의 입력이라 PreferencesInterface 가 아니라 Core 에 둔다.
public struct AndroidSDKPathSetting: Hashable, Sendable {
  public enum Value: Hashable, Sendable {
    /// 키가 없다 (기본 위치).
    case absent
    /// 저장된 문자열 그대로. 형식 검사는 하지 않는다.
    case path(String)
    /// 문자열이 아닌 값 (관리자가 `defaults write` 로 숫자·배열 등을 넣은 경우).
    case malformed
  }

  /// 키 없음, 잠기지 않음.
  public static let absent = AndroidSDKPathSetting(value: .absent, isLocked: false)

  public let value: Value
  /// 관리자가 이 키를 강제했다 (`objectIsForced`). 바꿀 수 없다.
  public let isLocked: Bool

  public init(value: Value, isLocked: Bool) {
    self.value = value
    self.isLocked = isLocked
  }
}

/// 설정 값으로 정한 Android SDK 위치. ANDROID_HOME·ANDROID_SDK_ROOT 는 보지 않는다.
public enum AndroidSDKRootChoice: Hashable, Sendable {
  case root(AndroidSDKRoot)
  /// 저장 값이 경로로 읽히지 않는다 (관리자가 넣은 잘못된 값 등).
  case invalidSetting

  /// - `.absent` → 기본 위치(`home/Library/Android/sdk`, isDefault true).
  /// - `.path`: 앞뒤 공백·개행을 뺀 뒤 `/` 로 시작하면 그 절대 경로, `~/` 로 시작하면 `~` 를 home 으로 바꾼다.
  ///   빈 문자열·그 밖의 상대 경로(`~user/…`·`~` 하나 포함)·NUL 이 든 문자열은 `.invalidSetting`.
  ///   `URL(filePath:).standardizedFileURL` 로 `.`·`..` 는 풀되 링크는 풀지 않는다. 결과가 기본 경로와 같으면 isDefault true.
  /// - `.malformed` → `.invalidSetting`.
  public static func resolve(_ stored: AndroidSDKPathSetting.Value, home: URL) -> AndroidSDKRootChoice {
    let defaultURL = AndroidSDKRoot.defaultURL(home: home)
    switch stored {
    case .absent:
      return .root(AndroidSDKRoot(url: defaultURL, isDefault: true))
    case .malformed:
      return .invalidSetting
    case let .path(raw):
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.contains("\0") else {
        return .invalidSetting
      }
      let url: URL
      if trimmed.hasPrefix("/") {
        url = AndroidSDKRoot.folderURL(trimmed).standardizedFileURL
      } else if trimmed.hasPrefix("~/") {
        let rest = String(trimmed.dropFirst(2))
        let homeURL = AndroidSDKRoot.folderURL(home.path(percentEncoded: false))
        url = (rest.isEmpty ? homeURL : homeURL.appending(path: rest, directoryHint: .isDirectory)).standardizedFileURL
      } else {
        return .invalidSetting
      }
      let isDefault = Self.comparablePath(url) == Self.comparablePath(defaultURL)
      return .root(AndroidSDKRoot(url: isDefault ? defaultURL : url, isDefault: isDefault))
    }
  }

  /// 끝 `/` 를 뺀 경로 (루트 `/` 는 그대로).
  static func comparablePath(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    guard path.count > 1, path.hasSuffix("/") else {
      return path
    }
    return String(path.dropLast())
  }
}
