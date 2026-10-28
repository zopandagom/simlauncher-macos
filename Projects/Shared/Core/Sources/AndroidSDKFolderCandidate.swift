/// 설정 창에서 고른 폴더의 판정. 사용자 파일 사이에 SDK 구성 요소가 섞이지 않게, 빈 폴더와 SDK 폴더만 저장한다.
public enum AndroidSDKFolderCandidate: Hashable, Sendable {
  /// 항목이 없다 (`.DS_Store`·`.localized`·`.simlauncher-staging-*` 는 세지 않는다).
  case empty
  /// 맨 위에 SDK 폴더 이름(`sdkFolderNames`) 중 하나가 디렉터리로 있다. 다른 항목이 함께 있어도 SDK 다.
  case sdk
  /// 그 밖의 내용이 있다 → 저장하지 않는다.
  case otherContents
  case notDirectory
  case missing
  case unreadable
  /// 심볼릭 링크를 지원하지 않는 볼륨이다 → 저장하지 않는다.
  case unsupportedVolume

  /// Android Studio·sdkmanager 가 SDK 루트에 만드는 폴더 중 Android SDK 에만 쓰는 이름.
  /// `tools`·`licenses`·`ndk`·`sources`·`platforms`(Cordova·Ionic 프로젝트)·`emulator` 처럼 다른 폴더에도 흔한 이름은
  /// 넣지 않는다 (그런 폴더가 있는 프로젝트·작업 폴더를 SDK 로 보고 사용자 파일 사이에 설치하지 않게).
  /// Studio·SimLauncher 가 설치한 SDK 에는 `platform-tools` 가 있다.
  public static let sdkFolderNames: Set<String> = [
    "platform-tools", "system-images", "build-tools", "cmdline-tools",
  ]

  /// 내용 판정에서 세지 않는 이름 (Finder 메타데이터와 이 앱의 남은 스테이징).
  static func isIgnored(_ name: String) -> Bool {
    name == ".DS_Store" || name == ".localized" || name.hasPrefix(".simlauncher-staging-")
  }

  /// empty·sdk.
  public var canSave: Bool {
    self == .empty || self == .sdk
  }

  /// 저장할지: SDK 폴더는 쓸 수 없어도 저장한다 (있는 도구는 쓴다, 설치만 막힌다). 빈 폴더는 쓸 수 있을 때만 (쓸 데가 없다).
  public func shouldSave(writable: Bool) -> Bool {
    switch self {
    case .sdk: true
    case .empty: writable
    default: false
    }
  }

  /// 종류 → 읽지 못함 → 링크 미지원 볼륨(false 일 때만) → 내용. 깨진 링크는 `.missing`.
  public static func judge(_ facts: AndroidSDKFolderFacts) -> AndroidSDKFolderCandidate {
    switch facts.kind {
    case .absent, .brokenLink: return .missing
    case .notDirectory: return .notDirectory
    case .unreadable: return .unreadable
    case .directory: break
    }
    guard let entries = facts.entries else {
      return .unreadable
    }
    if facts.volumeSupportsSymbolicLinks == false {
      return .unsupportedVolume
    }
    let counted = entries.filter { !Self.isIgnored($0.name) }
    if counted.contains(where: { $0.isDirectory && Self.sdkFolderNames.contains($0.name) }) {
      return .sdk
    }
    return counted.isEmpty ? .empty : .otherContents
  }
}

/// 고른 폴더의 맨 위 항목 하나.
public struct AndroidSDKFolderEntry: Hashable, Sendable {
  public let name: String
  /// 디렉터리, 또는 디렉터리를 가리키는 링크.
  public let isDirectory: Bool

  public init(name: String, isDirectory: Bool) {
    self.name = name
    self.isDirectory = isDirectory
  }
}

/// AndroidSDK Impl 이 고른 폴더에서 모은 사실 (파일만 읽는다).
public struct AndroidSDKFolderFacts: Hashable, Sendable {
  /// 링크는 따라간 종류.
  public let kind: AndroidSDKRootKind
  /// 맨 위 항목. 디렉터리가 아니거나 읽지 못하면 nil.
  public let entries: [AndroidSDKFolderEntry]?
  /// 볼륨의 `volumeSupportsSymbolicLinks`. 읽지 못하면 nil (지원으로 본다).
  public let volumeSupportsSymbolicLinks: Bool?

  public init(kind: AndroidSDKRootKind, entries: [AndroidSDKFolderEntry]?, volumeSupportsSymbolicLinks: Bool?) {
    self.kind = kind
    self.entries = entries
    self.volumeSupportsSymbolicLinks = volumeSupportsSymbolicLinks
  }
}
