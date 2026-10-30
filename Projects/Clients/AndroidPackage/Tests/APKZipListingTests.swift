import AndroidPackageInterface
import Foundation
import Testing
@testable import AndroidPackageImpl

struct APKZipListingTests {
  // MARK: - 해석

  @Test("헤더·항목 줄을 읽고 요약 줄은 보지 않는다")
  func parse() throws {
    let listing = try #require(APKZipListing.parse(ZipinfoOutput.signed))

    #expect(listing.declaredCount == 5)
    #expect(listing.entries.first == APKZipListing.Entry(name: "AndroidManifest.xml", size: 2048, kind: .file))
  }

  @Test(
    "권한 열: fat -rw----·unix -rw-r--r--·?rw------- 는 파일, d 는 폴더, l 은 링크",
    arguments: [
      ("-rw----", "a.txt", APKZipListing.Kind.file),
      ("-rw-r--r--", "a.txt", .file),
      ("?rw-------", "a.txt", .file),
      ("drwxr-xr-x", "res/", .directory),
      ("lrwxr-xr-x", "link", .symlink),
      ("lrwxr-xr-x", "link/", .symlink),
      ("?rw-------", "res/", .directory),
    ]
  )
  func kinds(permissions: String, name: String, kind: APKZipListing.Kind) throws {
    let listing = try #require(APKZipListing.parse(ZipinfoOutput.listing([ZipinfoOutput.line(
      name,
      permissions: permissions
    )])))
    #expect(listing.entries.map(\.kind) == [kind])
  }

  @Test("헤더가 다르거나 줄이 모자라거나 크기를 읽지 못하면 nil")
  func parseFailures() {
    #expect(APKZipListing.parse("") == nil)
    #expect(APKZipListing
      .parse("Archive:  a.apk\nZip file size: 1 bytes, number of entries: 2\n" + ZipinfoOutput.line("a")) == nil)
    #expect(APKZipListing.parse(ZipinfoOutput.listing(["-rw-r--r--  2.0 unx  big b- defN 20081231.190000 a"])) == nil)
  }

  // MARK: - 검사

  @Test("정상: 네이티브 ABI 없음, v1 서명 있음")
  func valid() throws {
    let entries = try Self.check(ZipinfoOutput.signed).get()
    #expect(entries == APKEntries(nativeABIs: [], hasV1Signature: true))
  }

  @Test("링크 항목(이름 끝 / 포함)은 unsafeEntry", arguments: ["lib/x.so", "assets/dir/"])
  func link(name: String) {
    let output = ZipinfoOutput.listing([
      ZipinfoOutput.line("AndroidManifest.xml"),
      ZipinfoOutput.line(name, permissions: "lrwxr-xr-x"),
    ])
    #expect(Self.check(output) == .failure(.unsafeEntry))
  }

  @Test("이름에 .. 구성 요소가 있거나 / 로 시작하면 unsafeEntry", arguments: ["../evil", "assets/../../x", "/etc/passwd", "a/.."])
  func unsafeName(name: String) {
    let output = ZipinfoOutput.listing([ZipinfoOutput.line("AndroidManifest.xml"), ZipinfoOutput.line(name)])
    #expect(Self.check(output) == .failure(.unsafeEntry))
  }

  @Test("..을 이름 안에 가진 구성 요소(a..b)는 통과한다")
  func dotsInsideName() {
    let output = ZipinfoOutput.listing([ZipinfoOutput.line("AndroidManifest.xml"), ZipinfoOutput.line("assets/a..b")])
    #expect((try? Self.check(output).get()) != nil)
  }

  @Test("manifest 가 없으면 unreadable, base/manifest 만 있으면 appBundle")
  func missingManifest() {
    #expect(Self.check(ZipinfoOutput.listing([ZipinfoOutput.line("classes.dex")])) == .failure(.unreadable))
    #expect(Self.check(ZipinfoOutput.listing([])) == .failure(.unreadable))
    let bundle = ZipinfoOutput.listing([
      ZipinfoOutput.line("BundleConfig.pb"),
      ZipinfoOutput.line("base/manifest/AndroidManifest.xml"),
      ZipinfoOutput.line("base/dex/classes.dex"),
    ])
    #expect(Self.check(bundle) == .failure(.appBundle))
  }

  @Test("하위 폴더의 AndroidManifest.xml 이나 폴더 항목은 manifest 로 세지 않는다")
  func manifestOnlyAtTop() {
    let output = ZipinfoOutput.listing([
      ZipinfoOutput.line("res/AndroidManifest.xml"),
      ZipinfoOutput.line("AndroidManifest.xml/", permissions: "drwxr-xr-x"),
    ])
    #expect(Self.check(output) == .failure(.unreadable))
  }

  @Test("manifest 가 둘이면 unreadable")
  func twoManifests() {
    let output = ZipinfoOutput.listing([
      ZipinfoOutput.line("AndroidManifest.xml"),
      ZipinfoOutput.line("AndroidManifest.xml"),
    ])
    #expect(Self.check(output) == .failure(.unreadable))
  }

  @Test("manifest 선언 크기가 4 MiB 를 넘으면 unreadable, 4 MiB 는 통과")
  func manifestSize() {
    let limit = Int64(AXMLManifestReader.sizeLimit)
    #expect(Self
      .check(ZipinfoOutput.listing([ZipinfoOutput.line("AndroidManifest.xml", size: limit + 1)])) ==
      .failure(.unreadable))
    #expect((try? Self.check(ZipinfoOutput.listing([ZipinfoOutput.line("AndroidManifest.xml", size: limit)])).get()) !=
      nil)
  }

  @Test("lib/<abi>/<파일> 만 네이티브 ABI 로 센다 (폴더만·lib 바로 아래 파일은 아님)")
  func nativeABIs() throws {
    let output = ZipinfoOutput.listing([
      ZipinfoOutput.line("AndroidManifest.xml"),
      ZipinfoOutput.line("lib/arm64-v8a/libx.so"),
      ZipinfoOutput.line("lib/arm64-v8a/liby.so"),
      ZipinfoOutput.line("lib/armeabi-v7a/sub/libz.so"),
      ZipinfoOutput.line("lib/x86/", permissions: "drwxr-xr-x"),
      ZipinfoOutput.line("lib/a.so"),
      ZipinfoOutput.line("assets/lib/mips/x.so"),
    ])
    #expect(try Self.check(output).get().nativeABIs == ["arm64-v8a", "armeabi-v7a"])
  }

  @Test(
    "v1 서명 파일: META-INF 바로 아래 .RSA·.DSA·.EC (대소문자 무시)",
    arguments: [
      ("META-INF/CERT.RSA", true),
      ("META-INF/x.ec", true),
      ("meta-inf/KEY.DSA", true),
      ("META-INF/sub/A.RSA", false),
      ("META-INF/CERT.SF", false),
      ("META-INF/.RSA", false),
      ("other/CERT.RSA", false),
    ]
  )
  func v1Signature(name: String, expected: Bool) throws {
    let output = ZipinfoOutput.listing([ZipinfoOutput.line("AndroidManifest.xml"), ZipinfoOutput.line(name)])
    #expect(try Self.check(output).get().hasV1Signature == expected)
  }

  private static func check(_ output: String) -> Result<APKEntries, AndroidPackageError> {
    guard let listing = APKZipListing.parse(output) else {
      Issue.record("목록을 읽지 못했다")
      return .failure(.inspectionUnavailable)
    }
    return listing.check()
  }
}
