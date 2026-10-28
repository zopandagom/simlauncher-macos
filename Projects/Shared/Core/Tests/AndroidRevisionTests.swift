import Testing
@testable import Core

struct AndroidRevisionTests {
  @Test("Pkg.Revision 문자열: 숫자 1~3 개 점 구분, 빠진 minor·micro 는 0", arguments: [
    ("37.0.1", AndroidRevision(major: 37, minor: 0, micro: 1)),
    ("7", AndroidRevision(major: 7)),
    ("37.2.12", AndroidRevision(major: 37, minor: 2, micro: 12)),
    ("36.1", AndroidRevision(major: 36, minor: 1)),
    (" 37.0.1 ", AndroidRevision(major: 37, minor: 0, micro: 1)),
  ])
  func parses(raw: String, expected: AndroidRevision) {
    #expect(AndroidRevision(raw) == expected)
  }

  @Test("형식이 틀리면 nil", arguments: ["", "37.", ".1", "37..1", "1.2.3.4", "37.0.0 rc1", "a", "-1", "３７", "37.0.x"])
  func rejects(raw: String) {
    #expect(AndroidRevision(raw) == nil)
  }

  @Test("비교: major → minor → micro, 같은 숫자면 preview 없는 쪽이 높다, 빠진 값은 0")
  func comparison() {
    #expect(AndroidRevision.v("37.2.12") > .v("37.2.11"))
    #expect(AndroidRevision.v("37.3") > .v("37.2.99"))
    #expect(AndroidRevision.v("38") > .v("37.9.9"))
    #expect(AndroidRevision.v("37") == AndroidRevision(major: 37, minor: 0, micro: 0))
    #expect(AndroidRevision(major: 37, preview: 1) < .v("37"))
    #expect(AndroidRevision(major: 37, preview: 1) < AndroidRevision(major: 37, preview: 2))
    #expect(AndroidRevision(major: 37, preview: 9) > .v("36.9.9"))
    #expect(!(AndroidRevision.v("37") < .v("37")))
  }

  @Test("description: 37.0.1, 미리보기면 rc 를 붙인다")
  func description() {
    #expect(AndroidRevision.v("37.0.1").description == "37.0.1")
    #expect(AndroidRevision.v("7").description == "7.0.0")
    #expect(AndroidRevision(major: 37, preview: 2).description == "37.0.0 rc2")
  }
}
