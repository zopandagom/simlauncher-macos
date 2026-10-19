import Testing
@testable import AppBundleImpl

/// zipinfo 실제 출력(`ZipinfoOutput`)을 읽는다.
struct ZipListingTests {
  @Test("정상 출력: 항목 수·이름·크기·종류, 선언 크기 합")
  func normal() throws {
    let listing = try #require(ZipListing.parse(ZipinfoOutput.normal))

    #expect(listing.declaredCount == 3)
    #expect(listing.entries == [
      .init(name: "Sample.app/", size: 0, kind: .directory),
      .init(name: "Sample.app/Info.plist", size: 280, kind: .file),
      .init(name: "Sample.app/Sample", size: 12, kind: .file),
    ])
    #expect(listing.declaredTotalBytes == 292)
  }

  @Test("Finder 형식: __MACOSX 폴더와 링크 줄을 읽는다")
  func dittoSequestered() throws {
    let listing = try #require(ZipListing.parse(ZipinfoOutput.dittoSequestered))

    #expect(listing.declaredCount == 25)
    #expect(listing.entries.count == 25)
    #expect(listing.entries.contains(.init(name: "__MACOSX/", size: 0, kind: .directory)))
    #expect(listing.entries.contains(
      .init(name: "Sample.app/Frameworks/F.framework/Versions/Current", size: 1, kind: .symlink)
    ))
    #expect(listing.declaredTotalBytes == 1522)
  }

  @Test("Windows 권한 열(-rw-a--)과 fat OS 도 파일로 읽는다")
  func windows() throws {
    let listing = try #require(ZipListing.parse(ZipinfoOutput.windows))

    #expect(listing.entries == [
      .init(name: "Sample.app/Info.plist", size: 1, kind: .file),
      .init(name: "Sample.app/Sample", size: 1, kind: .file),
    ])
  }

  @Test("이름의 공백·^I·^J·따옴표와 깨진 유니코드(?)를 그대로 둔다")
  func names() throws {
    let listing = try #require(ZipListing.parse(ZipinfoOutput.unicode))

    #expect(listing.entries.map(\.name) == [
      "?????? ???.app/",
      "?????? ???.app/Info.plist",
      "?????? ???.app/Sample",
      #"?????? ???.app/sp ace^Itab "q".txt"#,
      "?????? ???.app/new^Jline.txt",
    ])
  }

  @Test("이름 앞의 공백도 이름이다")
  func leadingSpace() {
    let output = ZipinfoOutput.single("-rw-r--r--  2.0 unx        1 b- defN 20240101.000000  lead.txt")

    #expect(ZipListing.parse(output)?.entries.map(\.name) == [" lead.txt"])
  }

  @Test("빈 zip: 항목 0 개, Empty zipfile 줄은 보지 않는다")
  func empty() throws {
    let listing = try #require(ZipListing.parse(ZipinfoOutput.empty))

    #expect(listing.declaredCount == 0)
    #expect(listing.entries.isEmpty)
    #expect(listing.declaredTotalBytes == 0)
  }

  @Test("4 GB 를 넘는 크기도 읽는다")
  func largeSize() {
    let output = ZipinfoOutput.single("-rw-r--r--  4.5 unx 5000000000 b- defN 20240101.000000 Sample.app/big")

    #expect(ZipListing.parse(output)?.declaredTotalBytes == 5_000_000_000)
  }

  @Test("크기 합이 Int64 를 넘으면 Int64.max 에서 멈춘다")
  func totalOverflow() {
    let output = """
    Archive:  x.zip
    Zip file size: 100 bytes, number of entries: 2
    -rw-r--r--  2.0 unx 9223372036854775807 b- defN 20240101.000000 Sample.app/a
    -rw-r--r--  2.0 unx        1 b- defN 20240101.000000 Sample.app/b

    """

    #expect(ZipListing.parse(output)?.declaredTotalBytes == .max)
  }

  @Test("링크(l)·FIFO(p)·이름이 / 로 끝나는 항목의 종류")
  func kinds() {
    let link = ZipinfoOutput.single("lrwxr-xr-x  2.0 unx        4 b- stor 20240101.000000 Sample.app/l")
    let fifo = ZipinfoOutput.single("prw-r--r--  2.0 unx        0 b- stor 20240101.000000 Sample.app/p")
    let slash = ZipinfoOutput.single("-rw-r--r--  2.0 unx        0 b- stor 20240101.000000 Sample.app/")

    #expect(ZipListing.parse(link)?.entries.first?.kind == .symlink)
    #expect(ZipListing.parse(fifo)?.entries.first?.kind == .other)
    #expect(ZipListing.parse(slash)?.entries.first?.kind == .directory)
  }

  @Test("읽지 못하는 출력은 nil: 줄이 헤더보다 적음, 크기가 숫자 아님, 헤더 형식 아님, 경고 줄, 이름 없음")
  func malformed() {
    let fewerLines = """
    Archive:  x.zip
    Zip file size: 100 bytes, number of entries: 3
    -rw-r--r--  2.0 unx        1 b- defN 20240101.000000 Sample.app/a
    """
    let badSize = ZipinfoOutput.single("-rw-r--r--  2.0 unx      1x2 b- defN 20240101.000000 Sample.app/a")
    let negativeSize = ZipinfoOutput.single("-rw-r--r--  2.0 unx       -1 b- defN 20240101.000000 Sample.app/a")
    let noName = ZipinfoOutput.single("-rw-r--r--  2.0 unx        1 b- defN 20240101.000000")
    let notHeader = """
    zipinfo:  cannot find or open x.zip, x.zip.zip or x.zip.ZIP.

    """
    let badCount = """
    Archive:  x.zip
    Zip file size: 100 bytes, number of entries: many

    """

    for output in [fewerLines, badSize, negativeSize, noName, notHeader, badCount, ZipinfoOutput.prefixed, ""] {
      #expect(ZipListing.parse(output) == nil)
    }
  }
}
