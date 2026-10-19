import Testing
@testable import Core

struct DeviceNameTests {
  @Test("앞뒤 공백·개행을 자른다")
  func normalizes() {
    #expect(DeviceName.normalized("  iPhone 17 \n") == "iPhone 17")
    #expect(DeviceName.normalized("\t테스트 기기\t") == "테스트 기기")
    #expect(DeviceName.normalized("가운데  공백") == "가운데  공백")
  }

  @Test("앞뒤 공백·개행을 빼면 비는 이름은 empty", arguments: ["", "   ", "\n", " \t\n "])
  func empty(raw: String) {
    #expect(DeviceName.problem(in: raw) == .empty)
  }

  @Test("가운데의 제어 문자는 containsControlCharacter", arguments: ["a\nb", "a\tb", "a\u{0}b", "a\u{7F}b"])
  func controlCharacters(raw: String) {
    #expect(DeviceName.problem(in: raw) == .containsControlCharacter)
  }

  @Test("이름 길이는 Character 단위로 100 자까지다")
  func length() {
    #expect(DeviceName.problem(in: String(repeating: "a", count: 100)) == nil)
    #expect(DeviceName.problem(in: String(repeating: "a", count: 101)) == .tooLong)
    #expect(DeviceName.problem(in: String(repeating: "가", count: 100)) == nil)
    #expect(DeviceName.problem(in: String(repeating: "👩‍💻", count: 100)) == nil)
    #expect(DeviceName.problem(in: String(repeating: "👩‍💻", count: 101)) == .tooLong)
    #expect(DeviceName.problem(in: "  " + String(repeating: "a", count: 100) + "  ") == nil)
  }

  @Test("제어 문자 검사가 길이 검사보다 먼저다")
  func controlBeforeLength() {
    #expect(DeviceName.problem(in: String(repeating: "a", count: 101) + "\nb") == .containsControlCharacter)
  }

  @Test(
    "옵션처럼 보이는 이름·ZWJ 이모지·결합 문자 이름은 허용한다",
    arguments: ["-h", "--help", "-x", "  iPhone 17  ", "👩‍💻 테스트", "e\u{301}cole", "iPhone 17"]
  )
  func allowed(raw: String) {
    #expect(DeviceName.problem(in: raw) == nil)
  }
}
