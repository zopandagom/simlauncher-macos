import Core
import Foundation
import Testing
@testable import AndroidPackageImpl

struct AXMLManifestReaderTests {
  // MARK: - 정상

  @Test("package 와 minSdk(10진)를 읽는다")
  func basic() {
    let manifest = AXMLManifestReader.read(AXMLTestBuilder.manifest().build())
    #expect(manifest == AXMLManifest(package: "com.example.app", minSDK: .level(24)))
  }

  @Test("minSdk 16진 값도 읽는다")
  func hex() {
    let data = AXMLTestBuilder.manifest(minSDK: .hex(0x1C)).build()
    #expect(AXMLManifestReader.read(data)?.minSDK == .level(28))
  }

  @Test("UTF-8 문자열 풀도 읽는다")
  func utf8Pool() {
    let data = AXMLTestBuilder.manifest(package: "dev.slm.probe", minSDK: .int(21), encoding: .utf8).build()
    #expect(AXMLManifestReader.read(data) == AXMLManifest(package: "dev.slm.probe", minSDK: .level(21)))
  }

  @Test("리소스 맵이 없으면 android 네임스페이스·이름 minSdkVersion 으로 찾는다")
  func withoutResourceMap() {
    var builder = AXMLTestBuilder.manifest(minSDK: .int(26))
    builder.resourceMap = nil
    #expect(AXMLManifestReader.read(builder.build())?.minSDK == .level(26))
  }

  @Test("리소스 맵에 minSdkVersion ID 가 없어도 이름으로 찾는다")
  func resourceMapWithoutMinSDK() {
    var builder = AXMLTestBuilder.manifest(minSDK: .int(23))
    builder.resourceMap = [("versionCode", AXMLTestBuilder.versionCodeID)]
    #expect(AXMLManifestReader.read(builder.build())?.minSDK == .level(23))
  }

  @Test("리소스 맵의 ID 로 찾으면 이름이 달라도 그 속성을 쓴다")
  func byResourceID() {
    var builder = AXMLTestBuilder.manifest(minSDK: nil)
    builder.resourceMap = [("renamed", AXMLTestBuilder.minSdkVersionID)]
    builder.root.children[0].attributes.append(.android("renamed", .int(30)))
    #expect(AXMLManifestReader.read(builder.build())?.minSDK == .level(30))
  }

  @Test("uses-sdk 가 없거나 minSdkVersion 속성이 없으면 Android 기본값 1")
  func defaultLevel() {
    #expect(AXMLManifestReader.read(AXMLTestBuilder.manifest(usesSDK: false).build())?.minSDK == .level(1))
    #expect(AXMLManifestReader.read(AXMLTestBuilder.manifest(minSDK: nil).build())?.minSDK == .level(1))
  }

  @Test(
    "리소스 참조·속성 참조·코드명 문자열은 unresolved",
    arguments: [
      AXMLTestBuilder.Value.reference(0x7F0A_0001),
      .attributeReference(0x0101_0000),
      .string("VanillaIceCream"),
      .typedString("Baklava"),
    ]
  )
  func unresolved(value: AXMLTestBuilder.Value) {
    #expect(AXMLManifestReader.read(AXMLTestBuilder.manifest(minSDK: value).build())?.minSDK == .unresolved)
  }

  @Test("숫자 문자열은 level 로 읽는다")
  func numericString() {
    #expect(AXMLManifestReader.read(AXMLTestBuilder.manifest(minSDK: .string("29")).build())?.minSDK == .level(29))
    #expect(AXMLManifestReader.read(AXMLTestBuilder.manifest(minSDK: .typedString("31")).build())?.minSDK == .level(31))
  }

  @Test("1...10000 밖의 정수는 unresolved", arguments: [Int32(0), -1, 10001, Int32.max])
  func outOfRange(value: Int32) {
    #expect(AXMLManifestReader.read(AXMLTestBuilder.manifest(minSDK: .int(value)).build())?.minSDK == .unresolved)
  }

  @Test("manifest 바로 아래가 아닌 uses-sdk 는 무시한다")
  func nestedUsesSDK() {
    var builder = AXMLTestBuilder.manifest(usesSDK: false)
    builder.root.children[0].children.append(AXMLTestBuilder.Element(
      name: "uses-sdk",
      attributes: [.android("minSdkVersion", .int(30))]
    ))
    #expect(AXMLManifestReader.read(builder.build())?.minSDK == .level(1))
  }

  @Test("두 번째 uses-sdk 는 무시한다")
  func secondUsesSDK() {
    var builder = AXMLTestBuilder.manifest(minSDK: .int(21))
    builder.root.children.append(AXMLTestBuilder.Element(
      name: "uses-sdk",
      attributes: [.android("minSdkVersion", .int(33))]
    ))
    #expect(AXMLManifestReader.read(builder.build())?.minSDK == .level(21))
  }

  @Test("package 가 rawValue 없이 문자열 값(data 색인)만 있어도 읽는다")
  func typedPackage() {
    var builder = AXMLTestBuilder.manifest(package: nil)
    builder.root.attributes.append(.plain("package", .typedString("com.example.typed")))
    #expect(AXMLManifestReader.read(builder.build())?.package == "com.example.typed")
  }

  @Test("깊이 64 까지는 읽는다")
  func depth64() {
    #expect(AXMLManifestReader.read(Self.nested(depth: 64).build()) != nil)
  }

  @Test("입력이 정확히 4 MiB 면 (뒤 남는 바이트는 무시하고) 읽는다")
  func exactLimit() {
    var data = AXMLTestBuilder.manifest().build()
    data.append(Data(count: AXMLManifestReader.sizeLimit - data.count))
    #expect(AXMLManifestReader.read(data)?.package == "com.example.app")
  }

  // MARK: - 거절

  @Test("첫 요소가 manifest 가 아니면 nil")
  func notManifest() {
    var builder = AXMLTestBuilder.manifest()
    builder.root.name = "application"
    #expect(AXMLManifestReader.read(builder.build()) == nil)
  }

  @Test("package 가 없으면 nil")
  func missingPackage() {
    #expect(AXMLManifestReader.read(AXMLTestBuilder.manifest(package: nil).build()) == nil)
  }

  @Test("파일 type 이 틀리면 nil")
  func wrongFileType() {
    var data = AXMLTestBuilder.manifest().build()
    AXMLBytes.set16(&data, 0, 0x0002)
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("파일 size 가 데이터보다 크면 nil")
  func fileSizeTooLarge() {
    var data = AXMLTestBuilder.manifest().build()
    AXMLBytes.set32(&data, 4, UInt32(data.count + 1))
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("청크 size < 8 이면 nil")
  func chunkTooSmall() {
    var data = AXMLTestBuilder.manifest().build()
    AXMLBytes.set32(&data, 8 + 4, 4)
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("청크 headerSize 가 size 보다 크면 nil")
  func chunkHeaderLargerThanSize() {
    var data = AXMLTestBuilder.manifest().build()
    let pool = AXMLBytes.first(0x0001, in: data)
    AXMLBytes.set16(&data, pool + 2, UInt16(min(Int(AXMLBytes.u32(data, pool + 4)) + 1, 0xFFFF)))
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("청크가 파일 밖으로 나가면 nil")
  func chunkOutsideFile() {
    var data = AXMLTestBuilder.manifest().build()
    let element = AXMLBytes.first(0x0102, in: data)
    AXMLBytes.set32(&data, element + 4, UInt32(data.count))
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("stringCount 가 0xFFFFFFFF 면 nil")
  func stringCountHuge() {
    var data = AXMLTestBuilder.manifest().build()
    AXMLBytes.set32(&data, AXMLBytes.first(0x0001, in: data) + 8, 0xFFFF_FFFF)
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("문자열 오프셋이 청크 밖이면 그 문자열을 읽지 못해 nil")
  func stringOffsetOutside() {
    var data = AXMLTestBuilder.manifest().build()
    let pool = AXMLBytes.first(0x0001, in: data)
    for index in 0 ..< Int(AXMLBytes.u32(data, pool + 8)) {
      AXMLBytes.set32(&data, pool + 28 + index * 4, 0x00FF_FFFF)
    }
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("문자열 길이가 청크 밖까지 가면 nil", arguments: [AXMLTestBuilder.Encoding.utf16, .utf8])
  func stringLengthOutside(encoding: AXMLTestBuilder.Encoding) {
    var data = AXMLTestBuilder.manifest(encoding: encoding).build()
    let pool = AXMLBytes.first(0x0001, in: data)
    let stringsStart = pool + Int(AXMLBytes.u32(data, pool + 20))
    for index in 0 ..< Int(AXMLBytes.u32(data, pool + 8)) {
      let position = stringsStart + Int(AXMLBytes.u32(data, pool + 28 + index * 4))
      switch encoding {
      case .utf16: AXMLBytes.set16(&data, position, 0x7FFF)
      case .utf8: data[position + 1] = 0x7F
      }
    }
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("attributeSize < 20 이면 nil")
  func attributeSizeTooSmall() {
    var data = AXMLTestBuilder.manifest().build()
    AXMLBytes.set16(&data, AXMLBytes.first(0x0102, in: data) + 16 + 10, 19)
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("attributeCount 0xFFFF 로 속성이 청크 밖이면 nil")
  func attributeCountHuge() {
    var data = AXMLTestBuilder.manifest().build()
    AXMLBytes.set16(&data, AXMLBytes.first(0x0102, in: data) + 16 + 12, 0xFFFF)
    #expect(AXMLManifestReader.read(data) == nil)
  }

  @Test("깊이 65 면 nil")
  func depth65() {
    #expect(AXMLManifestReader.read(Self.nested(depth: 65).build()) == nil)
  }

  @Test("4 MiB 를 넘으면 nil")
  func overLimit() {
    var data = AXMLTestBuilder.manifest().build()
    data.append(Data(count: AXMLManifestReader.sizeLimit + 1 - data.count))
    #expect(AXMLManifestReader.read(data) == nil)
  }

  // MARK: - 견고성

  @Test("정상 manifest 를 모든 길이로 자른 접두사가 멈추지 않고 nil 또는 값을 돌려준다")
  func prefixes() {
    let data = AXMLTestBuilder.manifest().build()
    for length in 0 ... data.count {
      let result = AXMLManifestReader.read(data.prefix(length))
      if length < data.count {
        // 파일 size 가 데이터보다 커서 늘 nil.
        #expect(result == nil)
      } else {
        #expect(result != nil)
      }
    }
  }

  @Test("고정 시드로 무작위 바이트를 바꾼 2,000개 입력이 멈추지 않고 끝난다", .timeLimit(.minutes(1)))
  func randomMutations() {
    var generator = SeededGenerator(seed: 0x7C5EED)
    let base = AXMLTestBuilder.manifest().build()
    var parsed = 0
    for _ in 0 ..< 2000 {
      var data = base
      for _ in 0 ..< Int.random(in: 1 ... 8, using: &generator) {
        data[Int.random(in: 0 ..< data.count, using: &generator)] = UInt8.random(in: 0 ... 255, using: &generator)
      }
      if AXMLManifestReader.read(data) != nil {
        parsed += 1
      }
    }
    // 바뀐 바이트가 문자열 내용 등에만 닿으면 읽힌다. 모두 거절되거나 모두 읽히면 변조가 의미 없다.
    #expect(parsed > 0)
    #expect(parsed < 2000)
  }

  // MARK: - 도우미

  /// manifest 아래로 `depth - 1` 단계 중첩한 요소.
  private static func nested(depth: Int) -> AXMLTestBuilder {
    var builder = AXMLTestBuilder.manifest()
    var element = AXMLTestBuilder.Element(name: "leaf")
    for _ in 0 ..< depth - 2 {
      element = AXMLTestBuilder.Element(name: "node", children: [element])
    }
    builder.root.children.append(element)
    return builder
  }
}
