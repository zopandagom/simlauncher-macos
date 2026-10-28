import Foundation

/// 구성 요소 하나의 상태.
public enum AndroidComponentStatus: Hashable, Sendable {
  /// 쓸 수 있다. revision 은 그 폴더 `source.properties` 의 `Pkg.Revision` (없거나 읽지 못하면 nil).
  /// 시스템 이미지의 revision 은 XML 과 다를 수 있어(`Pkg.Revision=7`, XML rev 8) 화면에 보이지 않는다.
  case installed(AndroidRevision?)
  case missing
  /// 무엇인가 있지만 쓸 수 없다. 덮어쓰지 않으므로 설치 계획에 넣지 않는다.
  case unusable(AndroidComponentProblem)
}

public enum AndroidComponentProblem: Hashable, Sendable {
  /// 폴더는 있는데 실행 파일(`adb`·`emulator`)이 없다, 또는 폴더 자리에 파일이 있다.
  case executableMissing
  /// 실행 파일에 실행 권한이 없다.
  case notExecutable
  /// 호스트 abi 이미지 폴더는 있는데 모두 `system.img` 가 없다.
  case imageFilesMissing
  /// 읽지 못했다 (권한).
  case unreadable
}

public enum AndroidSDKLocationProblem: Hashable, Sendable {
  /// 고른 폴더가 없다 (외장 디스크 분리·삭제·이름 바뀜). 기본 위치에는 쓰지 않는다 (기본은 `.absent`). 만들지 않는다.
  case missing
  /// 파일이거나, 디렉터리가 아닌 것을 가리키는 링크.
  case notDirectory
  /// 가리키는 대상이 없는 링크.
  case brokenLink
  /// 읽지 못했다 (권한).
  case unreadable
  /// 저장된 설정 값이 경로로 읽히지 않는다.
  case invalidSetting
}

/// SDK 위치의 상태.
public enum AndroidSDKLocation: Hashable, Sendable {
  /// 기본 위치가 아직 없다 → 셋 다 없음, 설치가 만든다.
  case absent(AndroidSDKRoot)
  /// 디렉터리, 또는 디렉터리를 가리키는 링크 (링크 경로로 보이고 실제 폴더에 쓴다). writable 은 `access(W_OK)`.
  case folder(AndroidSDKRoot, writable: Bool)
  /// 쓸 수 없는 위치. 설정 값이 잘못됐으면 root 가 nil.
  case unusable(AndroidSDKRoot?, AndroidSDKLocationProblem)

  public var root: AndroidSDKRoot? {
    switch self {
    case let .absent(root), let .folder(root, _): root
    case let .unusable(root, _): root
    }
  }
}

/// 구성 요소는 판정해 보이지만 설치를 막는 이유.
public enum AndroidSDKInstallBlocker: Hashable, Sendable {
  /// 이 폴더에 쓸 수 없다 (SDK 위치, 없으면 가장 가까운 있는 조상, 또는 `system-images`).
  case notWritable(URL)
  /// 심볼릭 링크를 지원하지 않는 볼륨(exFAT·FAT·SMB 등)이다.
  case unsupportedVolume
}

/// 파일 사실에서 판정한 SDK 상태. 판정은 순수 함수(`judge`), 사실 모으기는 AndroidSDK Impl 이 한다.
public struct AndroidSDKStatus: Hashable, Sendable {
  public let location: AndroidSDKLocation
  /// 세 구성 요소 모두. `location` 이 `.unusable` 이면 비어 있다.
  public let components: [AndroidSDKComponent: AndroidComponentStatus]
  /// 설치를 막는 이유. `location` 이 `.unusable` 이면 nil (위치 문제가 이유다).
  public let installBlocker: AndroidSDKInstallBlocker?
  /// `system.img` 가 있는 호스트 abi 이미지의 API 폴더 이름 (`android-37.0`), 이름순·중복 없음. 화면이 이미지 줄에 보인다.
  public let installedSystemImages: [String]

  public init(
    location: AndroidSDKLocation,
    components: [AndroidSDKComponent: AndroidComponentStatus],
    installBlocker: AndroidSDKInstallBlocker?,
    installedSystemImages: [String]
  ) {
    self.location = location
    self.components = components
    self.installBlocker = installBlocker
    self.installedSystemImages = installedSystemImages
  }

  /// 상태가 `.missing` 인 구성 요소 (설치 대상).
  public var missing: Set<AndroidSDKComponent> {
    Set(self.components.filter { $0.value == .missing }.keys)
  }

  /// 셋 다 설치됨 (7-B 의 진입 조건).
  public var isReady: Bool {
    AndroidSDKComponent.allCases.allSatisfy {
      if case .installed = self.components[$0] {
        return true
      }
      return false
    }
  }

  /// 위치가 쓸 수 있고, 막는 이유가 없고, 없는 구성 요소가 있다.
  public var canInstallMissing: Bool {
    if case .unusable = self.location {
      return false
    }
    return self.installBlocker == nil && !self.missing.isEmpty
  }

  /// 설치된 emulator 의 revision (계획의 의존 판정에 쓴다). 없거나 모르면 nil.
  public var installedEmulatorRevision: AndroidRevision? {
    if case let .installed(revision) = self.components[.emulator] {
      return revision
    }
    return nil
  }

  /// - 설정 값이 잘못됨 → `.unusable(nil, .invalidSetting)`.
  /// - 위치 없음: 기본 위치면 `.absent`(셋 다 없음), 고른 폴더면 `.unusable(.missing)` (만들지 않는다).
  /// - 파일·디렉터리가 아닌 것을 가리키는 링크 → `.notDirectory`, 깨진 링크 → `.brokenLink`, 읽지 못함 → `.unreadable`.
  /// - 디렉터리: 구성 요소마다 판정 (ARCHITECTURE·설계 §3 표).
  /// 막는 이유 순서: 링크를 지원하지 않는 볼륨(false 일 때만, nil 은 지원으로 본다) → 위치(또는 조상)에 쓸 수 없음 →
  /// `system-images` 에 쓸 수 없음.
  public static func judge(_ facts: AndroidSDKFileFacts) -> AndroidSDKStatus {
    guard case let .root(root) = facts.root else {
      return self.unusable(nil, .invalidSetting)
    }
    let location: AndroidSDKLocation
    switch facts.rootKind {
    case .absent:
      guard root.isDefault else {
        return Self.unusable(root, .missing)
      }
      location = .absent(root)
    case .directory:
      location = .folder(root, writable: facts.rootWritable)
    case .notDirectory:
      return Self.unusable(root, .notDirectory)
    case .brokenLink:
      return Self.unusable(root, .brokenLink)
    case .unreadable:
      return Self.unusable(root, .unreadable)
    }
    let blocker: AndroidSDKInstallBlocker? = if facts.volumeSupportsSymbolicLinks == false {
      .unsupportedVolume
    } else if !facts.rootWritable {
      .notWritable(facts.writeCheckedFolder ?? root.url)
    } else if !facts.systemImagesWritable {
      .notWritable(root.folder(for: .systemImage))
    } else {
      nil
    }
    let images = facts.systemImageFolders.filter(\.hasSystemImage)
    return AndroidSDKStatus(
      location: location,
      components: [
        .platformTools: Self.toolStatus(facts.platformTools),
        .emulator: Self.toolStatus(facts.emulator),
        .systemImage: Self.imageStatus(folder: facts.systemImagesFolder, images: facts.systemImageFolders),
      ],
      installBlocker: blocker,
      installedSystemImages: Array(Set(images.map(\.apiFolder))).sorted()
    )
  }

  private static func unusable(_ root: AndroidSDKRoot?, _ problem: AndroidSDKLocationProblem) -> AndroidSDKStatus {
    AndroidSDKStatus(
      location: .unusable(root, problem),
      components: [:],
      installBlocker: nil,
      installedSystemImages: []
    )
  }

  /// platform-tools·emulator: 폴더 없음 → 없음, 폴더 자리에 파일 → 실행 파일 없음, 폴더면 실행 파일을 본다.
  private static func toolStatus(_ facts: AndroidToolFolderFacts) -> AndroidComponentStatus {
    switch facts.folder {
    case .absent:
      return .missing
    case .unreadable:
      return .unusable(.unreadable)
    case .file, .executableFile:
      return .unusable(.executableMissing)
    case .directory:
      break
    }
    switch facts.executable {
    case .executableFile:
      return .installed(facts.revision)
    case .file:
      return .unusable(.notExecutable)
    case .unreadable:
      return .unusable(.unreadable)
    case .absent, .directory:
      return .unusable(.executableMissing)
    }
  }

  /// 시스템 이미지: `system.img` 가 있는 호스트 abi 폴더가 하나라도 있으면 설치됨 (태그 무관), 호스트 abi 폴더가 없으면 없음,
  /// 있는데 모두 `system.img` 가 없으면 쓸 수 없음. `system-images` 를 읽지 못하면 쓸 수 없음(읽기), 자리에 파일이면 이미지 없음.
  private static func imageStatus(
    folder: AndroidFileKind,
    images: [AndroidSystemImageFolderFacts]
  ) -> AndroidComponentStatus {
    switch folder {
    case .absent:
      return .missing
    case .unreadable:
      return .unusable(.unreadable)
    case .file, .executableFile:
      return .unusable(.imageFilesMissing)
    case .directory:
      break
    }
    if let installed = images.first(where: \.hasSystemImage) {
      return .installed(installed.revision)
    }
    if images.isEmpty {
      return .missing
    }
    return images.allSatisfy(\.unreadable) ? .unusable(.unreadable) : .unusable(.imageFilesMissing)
  }
}

/// Impl 이 모은 파일 하나의 종류. 링크는 따라간 대상의 종류이고, 깨진 링크는 `.file` (무엇인가 있지만 쓸 수 없다).
public enum AndroidFileKind: Hashable, Sendable {
  case absent
  case directory
  /// 일반 파일이고 실행 권한이 있다 (`access(X_OK)`).
  case executableFile
  /// 일반 파일(실행 권한 없음)이거나 그 밖의 무엇 (깨진 링크·FIFO 등).
  case file
  case unreadable
}

/// SDK 위치 자체의 종류 (링크는 따라간다).
public enum AndroidSDKRootKind: Hashable, Sendable {
  case absent, directory, notDirectory, brokenLink, unreadable
}

/// platform-tools·emulator 폴더의 사실.
public struct AndroidToolFolderFacts: Hashable, Sendable {
  /// `<root>/platform-tools` 등.
  public let folder: AndroidFileKind
  /// `<folder>/adb`·`<folder>/emulator`.
  public let executable: AndroidFileKind
  /// `<folder>/source.properties` 의 `Pkg.Revision`.
  public let revision: AndroidRevision?

  public init(folder: AndroidFileKind, executable: AndroidFileKind, revision: AndroidRevision?) {
    self.folder = folder
    self.executable = executable
    self.revision = revision
  }

  /// 폴더 없음.
  public static let absent = AndroidToolFolderFacts(folder: .absent, executable: .absent, revision: nil)
}

/// `system-images/<api>/<tag>/<호스트 abi>` 폴더 하나의 사실.
public struct AndroidSystemImageFolderFacts: Hashable, Sendable {
  /// `android-37.0`.
  public let apiFolder: String
  /// `google_apis`.
  public let tagFolder: String
  /// `system.img` 가 일반 파일로 있다.
  public let hasSystemImage: Bool
  /// 폴더를 읽지 못했다.
  public let unreadable: Bool
  /// `source.properties` 의 `Pkg.Revision`.
  public let revision: AndroidRevision?

  public init(
    apiFolder: String,
    tagFolder: String,
    hasSystemImage: Bool,
    unreadable: Bool,
    revision: AndroidRevision?
  ) {
    self.apiFolder = apiFolder
    self.tagFolder = tagFolder
    self.hasSystemImage = hasSystemImage
    self.unreadable = unreadable
    self.revision = revision
  }
}

/// AndroidSDK Impl 이 파일만 읽어 모은 사실 (네트워크·명령 없음).
public struct AndroidSDKFileFacts: Hashable, Sendable {
  public let root: AndroidSDKRootChoice
  public let rootKind: AndroidSDKRootKind
  /// 위치(없으면 가장 가까운 있는 조상)에 `access(W_OK)`.
  public let rootWritable: Bool
  /// 쓰기를 확인한 폴더 (위치가 없을 때의 조상). nil 이면 위치 자체.
  public let writeCheckedFolder: URL?
  /// `system-images` 가 있으면 그 `access(W_OK)`, 없으면 true.
  public let systemImagesWritable: Bool
  /// 위치(없으면 가장 가까운 있는 조상) 볼륨의 `volumeSupportsSymbolicLinks`. 읽지 못하면 nil (지원으로 본다).
  public let volumeSupportsSymbolicLinks: Bool?
  public let platformTools: AndroidToolFolderFacts
  public let emulator: AndroidToolFolderFacts
  /// `<root>/system-images`.
  public let systemImagesFolder: AndroidFileKind
  /// `system-images/*/*/<호스트 abi>` 로 있는 폴더 (링크는 따라간다), 경로순.
  public let systemImageFolders: [AndroidSystemImageFolderFacts]

  public init(
    root: AndroidSDKRootChoice,
    rootKind: AndroidSDKRootKind,
    rootWritable: Bool,
    writeCheckedFolder: URL?,
    systemImagesWritable: Bool,
    volumeSupportsSymbolicLinks: Bool?,
    platformTools: AndroidToolFolderFacts,
    emulator: AndroidToolFolderFacts,
    systemImagesFolder: AndroidFileKind,
    systemImageFolders: [AndroidSystemImageFolderFacts]
  ) {
    self.root = root
    self.rootKind = rootKind
    self.rootWritable = rootWritable
    self.writeCheckedFolder = writeCheckedFolder
    self.systemImagesWritable = systemImagesWritable
    self.volumeSupportsSymbolicLinks = volumeSupportsSymbolicLinks
    self.platformTools = platformTools
    self.emulator = emulator
    self.systemImagesFolder = systemImagesFolder
    self.systemImageFolders = systemImageFolders
  }
}
