/// 새 AVD 의 화면 모양. SDK 에는 기기 정의가 없어(Studio 안에만 있다, 실측) 앱이 목록을 갖고 있다.
public struct AndroidDeviceProfile: Identifiable, Hashable, Sendable {
  public enum ID: String, Hashable, Sendable, CaseIterable {
    case phone, smallPhone, tablet
  }

  public let id: ID
  /// `hw.lcd.width` (픽셀).
  public let width: Int
  /// `hw.lcd.height` (픽셀).
  public let height: Int
  /// `hw.lcd.density` (dpi).
  public let density: Int

  public init(id: ID, width: Int, height: Int, density: Int) {
    self.id = id
    self.width = width
    self.height = height
    self.density = density
  }

  /// 고정 순서: 휴대전화 1080x2400@420, 작은 휴대전화 720x1280@320, 태블릿 2560x1600@320 (모두 켜서 `wm size`·`wm density` 확인).
  public static let all: [AndroidDeviceProfile] = [
    AndroidDeviceProfile(id: .phone, width: 1080, height: 2400, density: 420),
    AndroidDeviceProfile(id: .smallPhone, width: 720, height: 1280, density: 320),
    AndroidDeviceProfile(id: .tablet, width: 2560, height: 1600, density: 320),
  ]

  public static func profile(_ id: ID) -> AndroidDeviceProfile? {
    self.all.first { $0.id == id }
  }

  /// 화면 크기로 정한 기기 모양.
  public var formFactor: AndroidVirtualDevice.FormFactor {
    AndroidVirtualDevice.FormFactor(width: self.width, height: self.height, density: self.density)
  }
}
