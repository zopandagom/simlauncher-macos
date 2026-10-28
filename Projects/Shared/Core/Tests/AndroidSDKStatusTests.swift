import Foundation
import Testing
@testable import Core

/// Impl 이 모은 파일 사실 → 구성 요소 상태·SDK 위치 상태 (설계 §3 표).
struct AndroidSDKStatusTests {
  static let root = AndroidFixture.root
  static let chosen = AndroidSDKRoot(
    url: URL(filePath: "/Volumes/T/sdk", directoryHint: .isDirectory),
    isDefault: false
  )
  static let installedTool = AndroidToolFolderFacts(
    folder: .directory,
    executable: .executableFile,
    revision: .v("37.0.1")
  )

  static func image(
    _ api: String = "android-37.0",
    tag: String = "google_apis",
    has: Bool = true,
    unreadable: Bool = false
  ) -> AndroidSystemImageFolderFacts {
    AndroidSystemImageFolderFacts(
      apiFolder: api,
      tagFolder: tag,
      hasSystemImage: has,
      unreadable: unreadable,
      revision: .v("7")
    )
  }

  static func facts(
    root: AndroidSDKRootChoice = .root(Self.root),
    kind: AndroidSDKRootKind = .directory,
    writable: Bool = true,
    checked: URL? = nil,
    systemImagesWritable: Bool = true,
    symlinks: Bool? = true,
    platformTools: AndroidToolFolderFacts = Self.installedTool,
    emulator: AndroidToolFolderFacts = Self.installedTool,
    systemImagesFolder: AndroidFileKind = .directory,
    images: [AndroidSystemImageFolderFacts] = [Self.image()]
  ) -> AndroidSDKFileFacts {
    AndroidSDKFileFacts(
      root: root,
      rootKind: kind,
      rootWritable: writable,
      writeCheckedFolder: checked,
      systemImagesWritable: systemImagesWritable,
      volumeSupportsSymbolicLinks: symlinks,
      platformTools: platformTools,
      emulator: emulator,
      systemImagesFolder: systemImagesFolder,
      systemImageFolders: images
    )
  }

  static func status(_ facts: AndroidSDKFileFacts) -> AndroidSDKStatus {
    AndroidSDKStatus.judge(facts)
  }

  @Test("셋 다 설치됨: isReady, missing 없음, revision·이미지 API 이름")
  func ready() {
    let status = Self.status(Self.facts(images: [
      Self.image("android-37.0"),
      Self.image("android-36", tag: "google_apis_playstore"),
    ]))
    #expect(status.location == .folder(Self.root, writable: true))
    #expect(status.components == [
      .platformTools: .installed(.v("37.0.1")),
      .emulator: .installed(.v("37.0.1")),
      .systemImage: .installed(.v("7")),
    ])
    #expect(status.isReady)
    #expect(status.missing.isEmpty)
    #expect(!status.canInstallMissing)
    #expect(status.installBlocker == nil)
    #expect(status.installedSystemImages == ["android-36", "android-37.0"])
    #expect(status.installedEmulatorRevision == .v("37.0.1"))
  }

  @Test("platform-tools·emulator: 폴더 없음 → missing, 폴더 자리에 파일 → executableMissing, 읽지 못함 → unreadable")
  func toolFolder() {
    let cases: [(AndroidFileKind, AndroidComponentStatus)] = [
      (.absent, .missing),
      (.file, .unusable(.executableMissing)),
      (.executableFile, .unusable(.executableMissing)),
      (.unreadable, .unusable(.unreadable)),
    ]
    for (kind, expected) in cases {
      let tool = AndroidToolFolderFacts(folder: kind, executable: .absent, revision: nil)
      let status = Self.status(Self.facts(platformTools: tool, emulator: tool))
      #expect(status.components[.platformTools] == expected)
      #expect(status.components[.emulator] == expected)
    }
  }

  @Test("실행 파일: 없음·폴더 → executableMissing, 실행 권한 없음 → notExecutable, 읽지 못함 → unreadable, 실행 파일 → installed")
  func toolExecutable() {
    let cases: [(AndroidFileKind, AndroidComponentStatus)] = [
      (.absent, .unusable(.executableMissing)),
      (.directory, .unusable(.executableMissing)),
      (.file, .unusable(.notExecutable)),
      (.unreadable, .unusable(.unreadable)),
      (.executableFile, .installed(nil)),
    ]
    for (kind, expected) in cases {
      let tool = AndroidToolFolderFacts(folder: .directory, executable: kind, revision: nil)
      #expect(Self.status(Self.facts(platformTools: tool)).components[.platformTools] == expected)
    }
  }

  @Test("시스템 이미지: system.img 가 있는 호스트 abi 폴더가 하나라도 → installed, 없으면 missing, 모두 system.img 없음 → imageFilesMissing")
  func systemImage() {
    let cases: [([AndroidSystemImageFolderFacts], AndroidComponentStatus)] = [
      ([], .missing),
      ([Self.image(has: false), Self.image("android-36", has: true)], .installed(.v("7"))),
      ([Self.image(has: false)], .unusable(.imageFilesMissing)),
      ([Self.image(has: false), Self.image("android-36", has: false, unreadable: true)], .unusable(.imageFilesMissing)),
      ([Self.image(has: false, unreadable: true)], .unusable(.unreadable)),
    ]
    for (images, expected) in cases {
      #expect(Self.status(Self.facts(images: images)).components[.systemImage] == expected)
    }
  }

  @Test("system-images 폴더: 없음 → missing, 파일 → imageFilesMissing, 읽지 못함 → unreadable")
  func systemImagesFolder() {
    #expect(Self.status(Self.facts(systemImagesFolder: .absent, images: [])).components[.systemImage] == .missing)
    #expect(Self.status(Self.facts(systemImagesFolder: .file, images: [])).components[.systemImage]
      == .unusable(.imageFilesMissing))
    #expect(Self.status(Self.facts(systemImagesFolder: .unreadable, images: [])).components[.systemImage]
      == .unusable(.unreadable))
  }

  @Test("missing 은 없음인 구성 요소만 (쓸 수 없음은 넣지 않는다), canInstallMissing")
  func missing() {
    let status = Self.status(Self.facts(
      platformTools: .absent,
      emulator: AndroidToolFolderFacts(folder: .directory, executable: .file, revision: nil),
      images: []
    ))
    #expect(status.missing == [.platformTools, .systemImage])
    #expect(!status.isReady)
    #expect(status.canInstallMissing)
    #expect(status.installedEmulatorRevision == nil)
  }

  @Test("기본 위치 없음 → absent, 셋 다 missing, 설치 가능")
  func defaultAbsent() {
    let status = Self.status(Self.facts(
      kind: .absent,
      platformTools: .absent,
      emulator: .absent,
      systemImagesFolder: .absent,
      images: []
    ))
    #expect(status.location == .absent(Self.root))
    #expect(status.missing == Set(AndroidSDKComponent.allCases))
    #expect(status.canInstallMissing)
  }

  @Test("고른 폴더 없음 → unusable(.missing) (absent 아님), 구성 요소 없음")
  func chosenMissing() {
    let status = Self.status(Self.facts(root: .root(Self.chosen), kind: .absent))
    #expect(status.location == .unusable(Self.chosen, .missing))
    #expect(status.components.isEmpty)
    #expect(status.missing.isEmpty)
    #expect(!status.canInstallMissing)
    #expect(status.location.root == Self.chosen)
  }

  @Test("위치 문제: 파일 → notDirectory, 깨진 링크 → brokenLink, 읽지 못함 → unreadable, 잘못된 설정 → invalidSetting(root nil)")
  func locationProblems() {
    #expect(Self.status(Self.facts(kind: .notDirectory)).location == .unusable(Self.root, .notDirectory))
    #expect(Self.status(Self.facts(kind: .brokenLink)).location == .unusable(Self.root, .brokenLink))
    #expect(Self.status(Self.facts(kind: .unreadable)).location == .unusable(Self.root, .unreadable))
    let invalid = Self.status(Self.facts(root: .invalidSetting))
    #expect(invalid.location == .unusable(nil, .invalidSetting))
    #expect(invalid.components.isEmpty)
    #expect(invalid.installBlocker == nil)
    #expect(!invalid.canInstallMissing)
  }

  @Test("쓸 수 없음: 구성 요소는 판정하고 설치는 막는다 (위치 → system-images 순서)")
  func notWritable() {
    let status = Self.status(Self.facts(writable: false, platformTools: .absent))
    #expect(status.location == .folder(Self.root, writable: false))
    #expect(status.components[.platformTools] == .missing)
    #expect(status.installBlocker == .notWritable(Self.root.url))
    #expect(!status.canInstallMissing)

    let images = Self.status(Self.facts(systemImagesWritable: false, images: []))
    #expect(images.installBlocker == .notWritable(Self.root.folder(for: .systemImage)))
    #expect(!images.canInstallMissing)
  }

  @Test("기본 위치가 없고 조상에 쓸 수 없으면 그 조상으로 막는다")
  func absentAncestorNotWritable() {
    let ancestor = URL(filePath: "/Users/u/Library/", directoryHint: .isDirectory)
    let status = Self.status(Self.facts(kind: .absent, writable: false, checked: ancestor, images: []))
    #expect(status.location == .absent(Self.root))
    #expect(status.installBlocker == .notWritable(ancestor))
  }

  @Test("링크를 지원하지 않는 볼륨: false 면 unsupportedVolume (쓰기보다 먼저), nil 은 지원으로 본다")
  func unsupportedVolume() {
    #expect(Self.status(Self.facts(writable: false, symlinks: false)).installBlocker == .unsupportedVolume)
    #expect(Self.status(Self.facts(symlinks: nil)).installBlocker == nil)
  }
}
