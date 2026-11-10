import Core
import Foundation

/// 속성 값 글자: 단위(dp·pt) 값을 먼저, px 를 괄호 안에 함께 (예 `142.5 dp (374 px)`). 배율을 모르면 px 만.
/// 숫자는 소수 첫째 자리에서 반올림하고 `.0` 은 뺀다. 단위 이름은 번역하지 않는 기호라 String Catalog 를 거치지 않는다.
enum LayoutValueFormat {
  static func value(_ pixels: Double, unit: LayoutUnit, pixelsPerUnit: Double?) -> String {
    let pixelText = "\(self.number(pixels)) px"
    guard let pixelsPerUnit, pixelsPerUnit > 0 else { return pixelText }
    return "\(self.number(pixels / pixelsPerUnit)) \(unit.rawValue) (\(pixelText))"
  }

  /// 소수 첫째 자리 반올림, `.0` 은 뺀다. 소수점은 늘 `.` 이다.
  static func number(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    let posix = Locale(identifier: "en_US_POSIX")
    if rounded == rounded.rounded() {
      // 정수 자리는 소수 없이 (-0 은 0). 덤프 좌표는 9자리 안이라 Int 로 바꿔도 넘치지 않지만, 아주 큰 값은 서식으로 둔다.
      guard abs(rounded) < 1e15 else { return String(format: "%.0f", locale: posix, rounded) }
      return String(Int(rounded))
    }
    return String(format: "%.1f", locale: posix, rounded)
  }
}
