/// 새 AVD 의 화면 모양. SDK 에는 기기 정의가 없어(Studio 안에만 있다, 실측) 앱이 목록을 갖고 있다.
/// 폴더블의 접기 설정은 시스템 이미지 안에 있다 (`Fold.requiredImageFiles`).
public struct AndroidDeviceProfile: Identifiable, Hashable, Sendable {
  public enum ID: String, Hashable, Sendable, CaseIterable {
    case phone, smallPhone, tablet, foldable
  }

  /// 접히는 기기의 설정 값 (config 의 `hw.device.name`·`hw.sensor.hinge*`·`hw.displayRegion.0.1.*`).
  public struct Fold: Hashable, Sendable {
    /// `hw.device.name`. 화면에 보이지 않는 설정 값으로, emulator 가 이미지 안 기기별 접기 설정(`data/misc/<이름>/`)을
    /// 찾는 이름이라 바꿀 수 없다 (다른 이름이면 접히지 않는다, 실측). 화면 문구에는 기기 상표명을 쓰지 않는다.
    public let emulatorDeviceName: String
    /// 접힌 바깥 화면 (`hw.displayRegion.0.1.width`·`height`, 픽셀).
    public let outerWidth: Int
    public let outerHeight: Int
    /// `hw.sensor.hinge.areas`.
    public let hingeArea: String

    public init(emulatorDeviceName: String, outerWidth: Int, outerHeight: Int, hingeArea: String) {
      self.emulatorDeviceName = emulatorDeviceName
      self.outerWidth = outerWidth
      self.outerHeight = outerHeight
      self.hingeArea = hingeArea
    }

    /// 이미지 폴더 아래 상대 경로. 둘 중 하나라도 없으면 접히지 않는다 (이미지 복제본에서 지워 보고 확인, emulator 37.2.12).
    public var requiredImageFiles: [String] {
      [
        "data/misc/\(self.emulatorDeviceName)/devicestate/device_state_configuration.xml",
        "data/misc/\(self.emulatorDeviceName)/displayconfig/display_layout_configuration.xml",
      ]
    }
  }

  public let id: ID
  /// `hw.lcd.width` (픽셀).
  public let width: Int
  /// `hw.lcd.height` (픽셀).
  public let height: Int
  /// `hw.lcd.density` (dpi).
  public let density: Int
  /// 접히는 기기면 값이 있다. 펼친 안쪽 화면이 `width`·`height` 다.
  public let fold: Fold?

  public init(id: ID, width: Int, height: Int, density: Int, fold: Fold? = nil) {
    self.id = id
    self.width = width
    self.height = height
    self.density = density
    self.fold = fold
  }

  /// 고정 순서: 휴대전화 1080x2400@420, 작은 휴대전화 720x1280@320, 태블릿 2560x1600@320 (모두 켜서 `wm size`·`wm density` 확인),
  /// 폴더블 펼침 2076x2152@390·접힘 1080x2424 (켜서 `emu fold`·`emu unfold` 뒤 `wm size` 확인).
  public static let all: [AndroidDeviceProfile] = [
    AndroidDeviceProfile(id: .phone, width: 1080, height: 2400, density: 420),
    AndroidDeviceProfile(id: .smallPhone, width: 720, height: 1280, density: 320),
    AndroidDeviceProfile(id: .tablet, width: 2560, height: 1600, density: 320),
    AndroidDeviceProfile(
      id: .foldable,
      width: 2076,
      height: 2152,
      density: 390,
      fold: Fold(
        emulatorDeviceName: "pixel_9_pro_fold",
        outerWidth: 1080,
        outerHeight: 2424,
        hingeArea: "1038-0-0-2152"
      )
    ),
  ]

  public static func profile(_ id: ID) -> AndroidDeviceProfile? {
    self.all.first { $0.id == id }
  }

  /// 접히는 기기면 foldable, 아니면 화면 크기로 정한 기기 모양.
  public var formFactor: AndroidVirtualDevice.FormFactor {
    if self.fold != nil {
      return .foldable
    }
    return AndroidVirtualDevice.FormFactor(width: self.width, height: self.height, density: self.density)
  }
}
