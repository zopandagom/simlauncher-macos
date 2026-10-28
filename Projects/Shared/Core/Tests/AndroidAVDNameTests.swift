import Testing
@testable import Core

struct AndroidAVDNameTests {
  @Test("영문·숫자로 시작하고 영문·숫자·. _ - 만 쓴 100자 이하 이름을 허용한다", arguments: [
    "a", "Pixel_9", "x.y_z", "A-1", "9", String(repeating: "a", count: 100),
  ])
  func valid(name: String) {
    #expect(AndroidAVDName.isValid(name))
  }

  @Test("빈 이름·공백·한글·- . _ 로 시작·/·101자를 거절한다", arguments: [
    "", "a b", "한글", "-a", ".a", "_a", "a/b", String(repeating: "a", count: 101), "a\n",
  ])
  func invalid(name: String) {
    #expect(!AndroidAVDName.isValid(name))
  }

  @Test("표시 이름에서 AVD 이름을 만든다", arguments: [
    ("테스트 폰", "Android_Device"),
    ("My Phone 2", "My_Phone_2"),
    ("a//b", "a_b"),
    ("a_ b", "a_b"),
    ("._-Pixel", "Pixel"),
    (" 픽셀 9", "9"),
    ("Pixel 9 ", "Pixel_9_"),
    ("x.y-z", "x.y-z"),
  ])
  func make(displayName: String, expected: String) {
    #expect(AndroidAVDName.make(from: displayName, existing: []) == expected)
  }

  @Test("60자로 자르고, 만든 이름은 늘 유효하다")
  func truncates() throws {
    let name = try #require(AndroidAVDName.make(from: String(repeating: "a", count: 80), existing: []))

    #expect(name == String(repeating: "a", count: 60))
    #expect(AndroidAVDName.isValid(name))
  }

  @Test("기존 이름과 대소문자 무시로 겹치면 _2 부터 붙인다")
  func collision() {
    #expect(AndroidAVDName.make(from: "Pixel", existing: ["pixel"]) == "Pixel_2")
    #expect(AndroidAVDName.make(from: "Pixel", existing: ["PIXEL", "Pixel_2"]) == "Pixel_3")
    #expect(AndroidAVDName.make(from: "테스트", existing: ["android_device"]) == "Android_Device_2")
  }

  @Test("_99 까지 모두 겹치면 nil")
  func exhausted() {
    let existing = Set(["Pixel"] + (2 ... 99).map { "Pixel_\($0)" })

    #expect(AndroidAVDName.make(from: "Pixel", existing: existing) == nil)
    #expect(AndroidAVDName.make(from: "Pixel", existing: existing.subtracting(["Pixel_99"])) == "Pixel_99")
  }

  @Test("60자 이름에 _99 가 붙어도 유효하다")
  func longWithSuffix() throws {
    let base = String(repeating: "a", count: 60)
    let name = try #require(AndroidAVDName.make(from: base, existing: [base]))

    #expect(name == base + "_2")
    #expect(AndroidAVDName.isValid(name))
  }
}
