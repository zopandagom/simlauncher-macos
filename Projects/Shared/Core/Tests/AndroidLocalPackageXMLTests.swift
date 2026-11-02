import Foundation
import Testing
@testable import Core

/// 저장소 XML → package.xml 내용. 기대값 `Fixtures/android-local-package-*.xml` 은 설계 원형 생성기의 출력이다 (끝 줄바꿈 없음).
struct AndroidLocalPackageXMLTests {
  /// 고정 기대값. 편집기가 끝에 줄바꿈 하나를 더했어도 견디게 뗀다 (생성 결과는 줄바꿈으로 끝나지 않는다).
  static func expected(_ name: String) throws -> Data {
    let data = try AndroidFixture.xml(name)
    return data.last == UInt8(ascii: "\n") ? data.dropLast() : data
  }

  /// 저장소에서 path 가 같고 revision 이 가장 높은 stable 패키지와 그 라이선스로 만든 내용.
  static func render(_ repositoryName: String, path: String) throws -> Data? {
    let repository = try AndroidFixture.repository(repositoryName)
    let package = try #require(repository.packages
      .filter { $0.path.raw == path && $0.channel == .stable && !$0.obsolete }
      .max { $0.revision < $1.revision })
    let license = try #require(package.licenseID.flatMap { repository.licenses[$0] })
    return AndroidLocalPackageXML.render(package, license: license)
  }

  @Test("고정 저장소 XML 의 platform-tools·emulator·시스템 이미지 → 고정 package.xml 과 바이트까지 같다")
  func fixtures() throws {
    #expect(try Self.render("android-repository", path: "platform-tools")
      == Self.expected("android-local-package-platform-tools"))
    #expect(try Self.render("android-repository", path: "emulator")
      == Self.expected("android-local-package-emulator"))
    #expect(try Self.render("android-sys-img", path: "system-images;android-37.0;google_apis;arm64-v8a")
      == Self.expected("android-local-package-sys-img"))
  }

  @Test("이스케이프(&·<·>·\"·\\r·\\n)·비 ASCII·다듬은 표시 이름·다른 xsi 접두·remotePackage 에 선언한 접두·빈 요소·속성 정렬")
  func escaping() throws {
    let repository = try AndroidFixture.repository("android-local-package-escape-input")
    let package = try #require(repository.packages.first)
    let license = try #require(repository.licenses["lic"])

    #expect(try AndroidLocalPackageXML.render(package, license: license)
      == Self.expected("android-local-package-escape"))
  }

  @Test("라이선스 id 가 패키지의 uses-license 와 다르거나 원문 조각이 없으면 nil")
  func nilCases() throws {
    let repository = try AndroidFixture.repository("android-repository")
    let package = try #require(repository.packages.first { $0.path.raw == "platform-tools" })
    #expect(package.localPackageSource != nil)

    #expect(AndroidLocalPackageXML.render(package, license: AndroidLicense(id: "other", text: "x")) == nil)
    let tool = AndroidFixture.tool("platform-tools", .v("37.0.1"), archives: [])
    #expect(AndroidLocalPackageXML.render(tool, license: AndroidFixture.sdkLicense) == nil)
  }
}
