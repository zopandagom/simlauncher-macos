import Core
import Testing
@testable import LayoutInspectorFeature

struct LayoutValueFormatTests {
  @Test("숫자는 소수 첫째 자리에서 반올림하고 .0 은 뺀다")
  func numbers() {
    #expect(LayoutValueFormat.number(48) == "48")
    #expect(LayoutValueFormat.number(411.428) == "411.4")
    #expect(LayoutValueFormat.number(142.46) == "142.5")
    #expect(LayoutValueFormat.number(23.96) == "24")
    #expect(LayoutValueFormat.number(-0.01) == "0")
    #expect(LayoutValueFormat.number(-12.5) == "-12.5")
  }

  @Test("배율 2.625(밀도 420)의 값은 dp 먼저, px 를 괄호에")
  func densityValue() {
    #expect(LayoutValueFormat.value(63, unit: .dp, pixelsPerUnit: 2.625) == "24 dp (63 px)")
    #expect(LayoutValueFormat.value(374, unit: .dp, pixelsPerUnit: 2.625) == "142.5 dp (374 px)")
    #expect(LayoutValueFormat.value(1080, unit: .dp, pixelsPerUnit: 2.625) == "411.4 dp (1080 px)")
  }

  @Test("iOS 는 pt 로 보인다")
  func pointValue() {
    #expect(LayoutValueFormat.value(132, unit: .pt, pixelsPerUnit: 3) == "44 pt (132 px)")
  }

  @Test("배율을 모르면(nil·0 이하) px 만 보인다")
  func pixelsOnly() {
    #expect(LayoutValueFormat.value(374, unit: .dp, pixelsPerUnit: nil) == "374 px")
    #expect(LayoutValueFormat.value(374, unit: .dp, pixelsPerUnit: 0) == "374 px")
    #expect(LayoutValueFormat.value(10.25, unit: .dp, pixelsPerUnit: nil) == "10.3 px")
  }
}
