import Foundation
import Testing
@testable import Core

/// 실측 구조를 줄여 직접 만든 픽스처(`Fixtures/android-repository.xml`·`android-sys-img.xml`) 해석.
struct AndroidRepositoryTests {
  @Test("라이선스 id·원문(앞뒤 줄바꿈 그대로), 같은 id 는 처음 것")
  func licenses() throws {
    let repository = try AndroidFixture.repository("android-repository")

    #expect(repository.licenses.keys.sorted() == ["android-sdk-license", "android-sdk-preview-license"])
    #expect(repository.licenses["android-sdk-license"]?.text
      == "Terms and Conditions\n\nThis is the Android Software Development Kit License Agreement (fixture).")
    #expect(repository.licenses["android-sdk-preview-license"]?.id == "android-sdk-preview-license")

    let duplicate = Data("""
    <sdk-repository><license id="a">first</license><license id="a">second</license></sdk-repository>
    """.utf8)
    #expect(try AndroidRepository(xmlData: duplicate).licenses["a"]?.text == "first")
  }

  @Test("platform-tools: path·revision·display-name·uses-license·channel·archive(host-os·size·checksum·url), 문서 순서")
  func platformTools() throws {
    let repository = try AndroidFixture.repository("android-repository")
    let tools = repository.packages.filter { $0.path.raw == "platform-tools" }

    #expect(tools.map(\.revision) == [.v("37.0.1"), .v("36")])
    let latest = try #require(tools.first)
    #expect(latest.displayName == "Android SDK Platform-Tools")
    #expect(latest.licenseID == "android-sdk-license")
    #expect(latest.channel == .stable)
    #expect(!latest.obsolete)
    #expect(latest.systemImage == nil)
    #expect(latest.dependencies.isEmpty)
    #expect(latest.archives.map(\.hostOS) == ["macosx", "linux", "windows"])
    #expect(latest.archives.allSatisfy { $0.hostArch == nil })
    let darwin = try #require(latest.archives.first)
    #expect(darwin.size == 16_110_554)
    #expect(darwin.checksum == ArchiveChecksum(algorithm: .sha1, hex: "a1b2c3d4e5f60718293a4b5c6d7e8f9001122334"))
    #expect(darwin.fileName == "platform-tools_r37.0.1-darwin.zip")
  }

  @Test("channel 은 channelRef 가 가리키는 <channel> 의 이름, host-arch 를 읽는다")
  func emulatorChannels() throws {
    let repository = try AndroidFixture.repository("android-repository")
    let emulators = repository.packages.filter { $0.path.raw == "emulator" }

    #expect(emulators.map(\.channel) == [.stable, .dev])
    #expect(emulators.first?.archives.map(\.hostArch) == ["x64", "aarch64", "x64"])
    #expect(emulators.last?.licenseID == "android-sdk-preview-license")
  }

  @Test("obsolete=\"true\", dependencies 의 min-revision(없으면 nil), api-level 만 있는 type-details 는 시스템 이미지가 아니다")
  func obsoleteAndDependencies() throws {
    let repository = try AndroidFixture.repository("android-repository")
    let tools = try #require(repository.packages.first { $0.path.raw == "tools" })
    let platform = try #require(repository.packages.first { $0.path.raw == "platforms;android-37" })

    #expect(tools.obsolete)
    #expect(tools.dependencies == [
      AndroidPackageDependency(path: AndroidFixture.path("emulator"), minRevision: nil),
      AndroidPackageDependency(path: AndroidFixture.path("platform-tools"), minRevision: .v("20")),
    ])
    #expect(platform.systemImage == nil)
    #expect(platform.archives.first?.checksum.algorithm == .sha256)
    #expect(platform.archives.first?.hostOS == nil)
  }

  @Test("path·revision 이 없는 패키지는 건너뛰고, 모르는 요소는 무시한다")
  func skipsIncompletePackages() throws {
    let repository = try AndroidFixture.repository("android-repository")

    #expect(repository.packages.map(\.path.raw) == [
      "platform-tools", "platform-tools", "emulator", "emulator", "tools", "platforms;android-37", "odd-archives",
    ])
  }

  @Test("archive: size·checksum·url 이 없거나 checksum type 이 sha1·sha256 이 아니면 그 archive 만 건너뛴다, hex 는 소문자로")
  func oddArchives() throws {
    let repository = try AndroidFixture.repository("android-repository")
    let odd = try #require(repository.packages.first { $0.path.raw == "odd-archives" })

    #expect(odd.archives.map(\.fileName) == ["upper.zip"])
    #expect(odd.archives.first?.checksum.hex == "61b2c3d4e5f60718293a4b5c6d7e8f9001122334")
    #expect(odd.revision == AndroidRevision(major: 2, minor: 1, micro: 0, preview: 3))
    #expect(odd.channel == .unknown)
    #expect(odd.licenseID == nil)
    #expect(odd.displayName == "odd-archives")
  }

  @Test("시스템 이미지 type-details: api-level(37.0·36.1·36x·36)·codename·tag 여러 개·abi·base-extension")
  func systemImages() throws {
    let repository = try AndroidFixture.repository("android-sys-img")
    let details = Dictionary(uniqueKeysWithValues: repository.packages.compactMap { package in
      package.systemImage.map { (package.path.raw, $0) }
    })

    #expect(repository.packages.count == 8)
    #expect(details["system-images;android-37.0;google_apis;arm64-v8a"] == AndroidSystemImageDetails(
      apiLevel: "37.0",
      codename: nil,
      tags: ["google_apis"],
      abi: "arm64-v8a",
      baseExtension: true
    ))
    #expect(details["system-images;android-36.1;google_apis;arm64-v8a"]?.apiLevel == "36.1")
    #expect(details["system-images;android-36;google_apis;arm64-v8a"]?.apiLevel == "36")
    #expect(details["system-images;android-36-ext19;google_apis;arm64-v8a"]?.apiLevel == "36x")
    #expect(details["system-images;android-36-ext19;google_apis;arm64-v8a"]?.baseExtension == false)
    #expect(details["system-images;android-CANARY;google_apis;arm64-v8a"]?.codename == "CANARY")
    #expect(details["system-images;android-37.2;google_apis_ps16k;arm64-v8a"]?.tags == [
      "google_apis",
      "page_size_16kb",
    ])
    #expect(details["system-images;android-37.0;google_apis;x86_64"]?.abi == "x86_64")

    let arm = try #require(repository.packages.first)
    #expect(arm.dependencies == [AndroidPackageDependency(
      path: AndroidFixture.path("emulator"),
      minRevision: .v("37.2.11")
    )])
    #expect(try arm.archives == [AndroidArchive(
      hostOS: nil,
      hostArch: nil,
      size: 2_104_098_168,
      checksum: #require(ArchiveChecksum(algorithm: .sha1, hex: "71b2c3d4e5f60718293a4b5c6d7e8f9001122334")),
      fileName: "arm64-v8a-37.0_r08.zip"
    )])
  }

  @Test("루트 요소가 sdk-repository·sdk-sys-img 가 아니면 unexpectedRoot (접두는 무시)")
  func unexpectedRoot() throws {
    #expect(throws: AndroidRepositoryProblem.unexpectedRoot) {
      try AndroidRepository(xmlData: Data("<sdk:addons-list xmlns:sdk=\"x\"><a/></sdk:addons-list>".utf8))
    }
    #expect(throws: AndroidRepositoryProblem.unexpectedRoot) {
      try AndroidRepository(xmlData: Data("<html><body/></html>".utf8))
    }
    #expect(try AndroidRepository(xmlData: Data("<x:sdk-sys-img xmlns:x=\"y\"/>".utf8)).packages.isEmpty)
  }

  @Test("깨진 XML·빈 데이터는 malformedXML")
  func malformed() {
    for text in ["<sdk-repository><license id=\"a\">x</sdk-repository>", "", "not xml"] {
      #expect(throws: AndroidRepositoryProblem.malformedXML) {
        try AndroidRepository(xmlData: Data(text.utf8))
      }
    }
  }

  @Test("maxByteCount 를 넘으면 해석하지 않고 tooLarge, 같으면 해석한다")
  func tooLarge() throws {
    let open = Data("<sdk-repository>".utf8)
    let close = Data("</sdk-repository>".utf8)
    let fill = AndroidRepository.maxByteCount - open.count - close.count
    let exact = open + Data(repeating: UInt8(ascii: " "), count: fill) + close

    #expect(exact.count == AndroidRepository.maxByteCount)
    #expect(try AndroidRepository(xmlData: exact).packages.isEmpty)
    #expect(throws: AndroidRepositoryProblem.tooLarge) {
      try AndroidRepository(xmlData: exact + Data(" ".utf8))
    }
  }

  @Test("decoded(from:) 는 init(xmlData:) 와 같은 결과")
  func decodedMatchesInit() async throws {
    let data = try AndroidFixture.xml("android-sys-img")
    #expect(try await AndroidRepository.decoded(from: data) == AndroidRepository(xmlData: data))
  }
}

// MARK: - package.xml 원문 조각

extension AndroidRepositoryTests {
  static let inlineTypeDetails = "<type-details xsi:type=\"generic:genericDetailsType\"/>"
  static let inlineRevision = "<revision><major>1</major></revision>"

  /// remotePackage 하나(path `emulator`)의 저장소. 루트에 `sdk`·`xsi`·`generic`·`x` 를 선언한다.
  static func inline(_ body: String, rootAttributes: String = "") throws -> AndroidRemotePackage {
    let xml = """
    <sdk:sdk-repository xmlns:sdk="urn:r" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" \
    xmlns:generic="urn:g" xmlns:x="urn:x"\(rootAttributes)><remotePackage path="emulator">\(body)\
    <display-name>E</display-name></remotePackage></sdk:sdk-repository>
    """
    let repository = try AndroidRepository(xmlData: Data(xml.utf8))
    let package = try #require(repository.packages.first)
    #expect(repository.packages.count == 1)
    #expect(package.revision == .v("1"))
    return package
  }

  @Test("platform-tools 원문 조각: xsi:type 을 푼 generic/02·genericDetailsType, 빈 type-details, revision 그대로, 의존 없음")
  func platformToolsSource() throws {
    let repository = try AndroidFixture.repository("android-repository")
    let latest = try #require(repository.packages.first { $0.path.raw == "platform-tools" })
    let source = try #require(latest.localPackageSource)

    #expect(source.typeNamespace == "http://schemas.android.com/repository/android/generic/02")
    #expect(source.typeName == "genericDetailsType")
    #expect(source.typeDetails.isEmpty)
    #expect(source.dependencies == nil)
    guard case let .element(name, attributes, children) = source.revision else {
      Issue.record("revision 이 요소가 아니다")
      return
    }
    #expect(name == "revision")
    #expect(attributes.isEmpty)
    #expect(children.compactMap(Self.elementName) == ["major", "minor", "micro"])
  }

  @Test("시스템 이미지 원문 조각: sys-img2/03·sysImgDetailsType, 자식 요소 순서, dependencies 요소")
  func systemImageSource() throws {
    let repository = try AndroidFixture.repository("android-sys-img")
    let arm = try #require(repository.packages.first)
    let source = try #require(arm.localPackageSource)

    #expect(source.typeNamespace == "http://schemas.android.com/sdk/android/repo/sys-img2/03")
    #expect(source.typeName == "sysImgDetailsType")
    #expect(source.typeDetails.compactMap(Self.elementName) == [
      "api-level", "extension-level", "base-extension", "tag", "vendor", "abi",
    ])
    let dependencies = try #require(source.dependencies)
    #expect(Self.elementName(dependencies) == "dependencies")
  }

  @Test("인라인 기본 모양은 원문 조각이 있다 (아래 nil 경우의 기준)")
  func inlineBaseline() throws {
    let source = try #require(Self.inline(Self.inlineTypeDetails + Self.inlineRevision).localPackageSource)
    #expect(source.typeNamespace == "urn:g")
    #expect(source.typeName == "genericDetailsType")
    #expect(source.revision == .element(
      name: "revision",
      attributes: [:],
      children: [.element(name: "major", attributes: [:], children: [.text("1")])]
    ))
  }

  /// `{T}`·`{R}` 은 기본 type-details·revision 으로 바꾼다.
  @Test(
    "옮길 수 없는 모양이면 원문 조각만 nil, 패키지는 그대로 읽는다",
    arguments: [
      // ① xsi:type 없음
      ("<type-details/>{R}", ""),
      // ② xsi:type 값의 접두가 선언되지 않음, XMLSchema-instance 가 아닌 접두의 type
      ("<type-details xsi:type=\"nope:genericDetailsType\"/>{R}", ""),
      ("<type-details x:type=\"generic:genericDetailsType\"/>{R}", ""),
      // ③ 값에 접두 없음
      ("<type-details xsi:type=\"genericDetailsType\"/>{R}", ""),
      // ④ 루트에 기본 네임스페이스
      ("{T}{R}", " xmlns=\"urn:d\""),
      // ⑤ type-details 하위에 접두 요소
      ("<type-details xsi:type=\"generic:t\"><x:abi>a</x:abi></type-details>{R}", ""),
      // ⑥ 하위 요소에 접두 속성
      ("<type-details xsi:type=\"generic:t\"><tag x:id=\"1\"/></type-details>{R}", ""),
      // ⑦ type-details 두 번
      ("{T}{T}{R}", ""),
      // ⑧ 하위 요소에 xmlns 선언
      ("<type-details xsi:type=\"generic:t\"><tag xmlns:y=\"urn:y\"/></type-details>{R}", ""),
      // ⑨ revision 요소에 접두
      ("{T}<x:revision><major>1</major></x:revision>", ""),
      // ⑩ dependencies 요소에 접두 속성
      ("{T}{R}<dependencies x:a=\"1\"><dependency path=\"emulator\"/></dependencies>", ""),
      // ⑪ revision 두 번
      ("{T}{R}{R}", ""),
    ]
  )
  func sourceUnavailable(body: String, rootAttributes: String) throws {
    let body = body
      .replacing("{T}", with: Self.inlineTypeDetails)
      .replacing("{R}", with: Self.inlineRevision)
    #expect(try Self.inline(body, rootAttributes: rootAttributes).localPackageSource == nil)
  }

  static func elementName(_ node: AndroidXMLNode) -> String? {
    guard case let .element(name, _, _) = node else {
      return nil
    }
    return name
  }
}
