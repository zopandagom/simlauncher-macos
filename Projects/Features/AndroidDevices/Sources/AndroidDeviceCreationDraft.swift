import Core

/// 만들기 시트 초안. 선택지는 시트를 연 시점 목록의 스냅샷이다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `creationDraft` 를 읽기만 한다).
public struct AndroidDeviceCreationDraft: Hashable, Sendable {
  public let options: AndroidDeviceCreationOptions
  /// 표시 이름 (한글 가능). AVD 이름은 Client 가 이것으로 만든다.
  public private(set) var name = ""
  public private(set) var image: AndroidSystemImageRef
  public private(set) var profile: AndroidDeviceProfile.ID = .phone
  /// 사용자가 이름을 고쳤는지. 고치기 전에는 빈 이름의 문제를 보이지 않는다 (열자마자 빨간 글자가 뜨지 않게).
  public private(set) var isNameEdited = false

  /// 만들 이미지가 없으면 nil. 기본: 가장 높은 API, 휴대전화, 빈 이름.
  init?(options: AndroidDeviceCreationOptions) {
    guard let image = options.defaultImage else { return nil }
    self.options = options
    self.image = image
  }

  public var nameProblem: DeviceNameProblem? {
    DeviceName.problem(in: self.name)
  }

  /// 만들기를 누를 수 있는지: 이름에 문제가 없고, 고른 조합을 만들 수 있다.
  public var canSubmit: Bool {
    self.nameProblem == nil && self.options.contains(image: self.image, profile: self.profile)
  }

  /// 고른 이미지에 고른 화면 모양(폴더블)의 접기 설정이 없는지. 규칙은 Core 선택지에 있고 여기서는 넘기기만 한다.
  /// 이 조합도 초안에 받아 두고(고른 것을 몰래 바꾸지 않는다) 시트가 이유를 보인다. `canSubmit` 은 false 다.
  public var isProfileUnsupportedByImage: Bool {
    self.options.lacksFoldSettings(image: self.image, profile: self.profile)
  }

  /// 폴더블을 만들 수 있는 이미지를 이미지 선택지 순서(API 내림차순)로. 시트 이유 문구가 고를 이미지로 알려 준다.
  public var foldableImageChoices: [AndroidSystemImageRef] {
    self.options.images.filter { self.options.foldableImages.contains($0) }
  }

  mutating func nameChanged(_ name: String) {
    self.name = name
    self.isNameEdited = true
  }

  /// 선택지에 없는 이미지면 무시한다.
  mutating func imageChanged(_ image: AndroidSystemImageRef) {
    guard self.options.images.contains(image) else { return }
    self.image = image
  }

  /// 선택지에 없는 화면 모양이면 무시한다.
  mutating func profileChanged(_ profile: AndroidDeviceProfile.ID) {
    guard self.options.profiles.contains(where: { $0.id == profile }) else { return }
    self.profile = profile
  }
}
