import Testing
@testable import Core

struct AndroidSDKFolderCandidateTests {
  static func judge(
    _ entries: [AndroidSDKFolderEntry]?,
    kind: AndroidSDKRootKind = .directory,
    symlinks: Bool? = true
  ) -> AndroidSDKFolderCandidate {
    AndroidSDKFolderCandidate.judge(AndroidSDKFolderFacts(
      kind: kind,
      entries: entries,
      volumeSupportsSymbolicLinks: symlinks
    ))
  }

  static func folder(_ name: String) -> AndroidSDKFolderEntry {
    AndroidSDKFolderEntry(name: name, isDirectory: true)
  }

  static func file(_ name: String) -> AndroidSDKFolderEntry {
    AndroidSDKFolderEntry(name: name, isDirectory: false)
  }

  @Test("빈 폴더 (.DS_Store·.localized·.simlauncher-staging-* 만 있어도) → empty")
  func empty() {
    #expect(Self.judge([]) == .empty)
    #expect(Self
      .judge([Self.file(".DS_Store"), Self.file(".localized"), Self.folder(".simlauncher-staging-X")]) == .empty)
  }

  @Test("SDK 폴더 이름이 디렉터리로 있으면 sdk (다른 항목이 함께 있어도)")
  func sdk() {
    for name in AndroidSDKFolderCandidate.sdkFolderNames {
      #expect(Self.judge([Self.folder(name)]) == .sdk)
    }
    #expect(Self.judge([
      Self.folder("platform-tools"),
      Self.file(".knownPackages"),
      Self.folder(".temp"),
      Self.file("x"),
    ]) == .sdk)
  }

  @Test("platform-tools 가 파일이고 다른 파일 → otherContents, 그 밖의 내용 → otherContents")
  func otherContents() {
    #expect(Self.judge([Self.file("platform-tools"), Self.file("notes.txt")]) == .otherContents)
    #expect(Self.judge([Self.folder("Documents")]) == .otherContents)
    #expect(Self.judge([Self.file(".hidden")]) == .otherContents)
  }

  @Test("다른 폴더에도 흔한 이름(tools·licenses·ndk·sources·platforms·emulator)만으로는 SDK 가 아니다 → otherContents")
  func commonNamesAreNotSDK() {
    #expect(Self.judge([Self.folder("platforms"), Self.folder("www"), Self.folder("plugins")]) == .otherContents)
    for name in ["tools", "licenses", "ndk", "sources", "platforms", "emulator"] {
      #expect(!AndroidSDKFolderCandidate.sdkFolderNames.contains(name))
      #expect(Self.judge([Self.folder(name)]) == .otherContents)
      #expect(Self.judge([Self.folder(name), Self.file("README.md"), Self.folder("src")]) == .otherContents)
    }
    #expect(Self.judge([Self.folder("tools"), Self.folder("platform-tools")]) == .sdk)
  }

  @Test("종류: 없음·깨진 링크 → missing, 파일 → notDirectory, 읽기 실패·항목을 읽지 못함 → unreadable")
  func kinds() {
    #expect(Self.judge(nil, kind: .absent) == .missing)
    #expect(Self.judge(nil, kind: .brokenLink) == .missing)
    #expect(Self.judge(nil, kind: .notDirectory) == .notDirectory)
    #expect(Self.judge(nil, kind: .unreadable) == .unreadable)
    #expect(Self.judge(nil) == .unreadable)
  }

  @Test("링크를 지원하지 않는 볼륨이면 unsupportedVolume (SDK 폴더여도), nil 은 지원으로 본다")
  func unsupportedVolume() {
    #expect(Self.judge([Self.folder("platform-tools")], symlinks: false) == .unsupportedVolume)
    #expect(Self.judge([], symlinks: false) == .unsupportedVolume)
    #expect(Self.judge([], symlinks: nil) == .empty)
  }

  @Test("저장: canSave 는 empty·sdk, shouldSave 는 sdk 는 항상·empty 는 쓸 수 있을 때만")
  func saving() {
    #expect(AndroidSDKFolderCandidate.empty.canSave)
    #expect(AndroidSDKFolderCandidate.sdk.canSave)
    let others: [AndroidSDKFolderCandidate] = [.otherContents, .notDirectory, .missing, .unreadable, .unsupportedVolume]
    for candidate in others {
      #expect(!candidate.canSave)
      #expect(!candidate.shouldSave(writable: true))
    }
    #expect(AndroidSDKFolderCandidate.sdk.shouldSave(writable: false))
    #expect(AndroidSDKFolderCandidate.empty.shouldSave(writable: true))
    #expect(!AndroidSDKFolderCandidate.empty.shouldSave(writable: false))
  }
}
