import AppBundleInterface
import Testing
@testable import AppBundleImpl

/// 풀기 전 목록 검사. 목록은 직접 만든다 (zipinfo 출력 형식은 ZipListingTests 가 본다).
struct ZipListingCheckTests {
  private static func listing(_ entries: [(String, ZipListing.Kind)]) -> ZipListing {
    ZipListing(
      declaredCount: entries.count,
      entries: entries.map { ZipListing.Entry(name: $0.0, size: 1, kind: $0.1) }
    )
  }

  private static func check(_ entries: [(String, ZipListing.Kind)]) -> AppBundleError? {
    do throws(AppBundleError) {
      try ZipListingCheck.check(Self.listing(entries))
      return nil
    } catch {
      return error
    }
  }

  @Test("맨 위 .app 하나면 통과: 폴더 항목, ./ 접두, 하위 항목만, .APP, 메타데이터·README·dSYM 이 함께 있어도")
  func oneApp() {
    let cases: [[(String, ZipListing.Kind)]] = [
      [("Sample.app/", .directory), ("Sample.app/Info.plist", .file)],
      [("./Sample.app/", .directory), ("./Sample.app/Sample", .file)],
      [("Sample.app/Info.plist", .file)],
      [("SAMPLE.APP/", .directory)],
      [
        ("Sample.app/", .directory),
        ("__MACOSX/", .directory),
        ("__MACOSX/Other.app/x", .file),
        ("._Other.app", .file),
        ("._Other.app/x", .file),
        ("README.txt", .file),
        ("Sample.app.dSYM/", .directory),
        ("Sample.app.dSYM/Contents/x", .file),
      ],
      [(".app/", .directory), ("Sample.app/", .directory)],
      [("Sample.app/", .directory), ("SAMPLE.APP/extra", .file)],
    ]
    for entries in cases {
      #expect(Self.check(entries) == nil, "\(entries.map(\.0))")
    }
  }

  @Test("맨 위 .app 폴더가 없으면 withoutApp: 하위 폴더에만, 파일인 X.app, 빈 목록, 이름이 정확히 .app")
  func noApp() {
    let cases: [[(String, ZipListing.Kind)]] = [
      [("Payload/", .directory), ("Payload/Sample.app/", .directory), ("Payload/Sample.app/Info.plist", .file)],
      [("Sample.app", .file)],
      [],
      [(".app/", .directory), (".app/Info.plist", .file)],
      [("__MACOSX/Sample.app/", .directory)],
    ]
    for entries in cases {
      #expect(Self.check(entries) == .zipWithoutApp, "\(entries.map(\.0))")
    }
  }

  @Test("맨 위 .app 이 둘 이상이면 withMultipleApps (./ 접두 포함)")
  func multipleApps() {
    #expect(Self.check([("A.app/", .directory), ("B.app/", .directory)]) == .zipWithMultipleApps)
    #expect(Self.check([("A.app/x", .file), ("./Other.app/y", .file)]) == .zipWithMultipleApps)
  }

  @Test("맨 앞·중간 .. 와 절대 경로는 unsafe (__MACOSX 아래나 README 같은 무시 항목이어도)")
  func escapingNames() {
    let names = [
      "../escape",
      "Sample.app/../../escape-mid",
      "/abs/Sample.app/x",
      "__MACOSX/../x",
      "README/../../x",
      "Sample.app/..",
    ]
    for name in names {
      #expect(Self.check([("Sample.app/", .directory), (name, .file)]) == .zipUnsafeEntry, "\(name)")
    }
  }

  @Test("경로 검사는 .app 개수 판정보다 먼저다")
  func escapeBeforeCount() {
    #expect(Self.check([("../x", .file)]) == .zipUnsafeEntry)
  }

  @Test("맨 위 .app 이 링크면 unsafe")
  func topLevelAppLink() {
    #expect(Self.check([("Sample.app", .symlink)]) == .zipUnsafeEntry)
    #expect(Self.check([("./Sample.app", .symlink)]) == .zipUnsafeEntry)
  }

  @Test("백슬래시와 ..x 같은 이름은 경로 탈출이 아니다")
  func notEscaping() {
    #expect(Self.check([("Sample.app/", .directory), (#"Sample.app/..\x"#, .file)]) == nil)
    #expect(Self.check([("Sample.app/", .directory), ("Sample.app/..x", .file)]) == nil)
  }

  @Test("isAppName: A.app·a.APP 은 .app 이름, .app·app·A.app.dSYM 은 아니다")
  func isAppName() {
    #expect(ZipNames.isAppName("A.app"))
    #expect(ZipNames.isAppName("a.APP"))
    #expect(!ZipNames.isAppName(".app"))
    #expect(!ZipNames.isAppName("app"))
    #expect(!ZipNames.isAppName("A.app.dSYM"))
  }
}
