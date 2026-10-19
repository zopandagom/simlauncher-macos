import Core

/// 생성 시트 초안. 선택지는 시트를 연 시점 목록의 스냅샷이다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `createDraft` 를 읽기만 한다).
public struct DeviceCreationDraft: Hashable, Sendable {
  public let options: DeviceCreationOptions
  public private(set) var name: String
  public private(set) var runtimeID: DeviceRuntime.ID
  public private(set) var deviceTypeID: DeviceType.ID
  /// 사용자가 이름을 고쳤는지. 고치지 않았으면 기기 종류가 바뀔 때 이름도 그 종류 이름으로 바뀐다.
  public private(set) var isNameEdited = false

  /// options 가 비었으면 nil. 기본: 최신 런타임, 그 첫 기기 종류, 이름 = 종류 이름.
  init?(options: DeviceCreationOptions) {
    guard let runtime = options.defaultRuntime,
          let deviceType = options.defaultDeviceType(for: runtime.id)
    else { return nil }
    self.options = options
    self.runtimeID = runtime.id
    self.deviceTypeID = deviceType.id
    self.name = deviceType.name
  }

  /// 지금 런타임으로 만들 수 있는 기기 종류.
  public var deviceTypes: [DeviceType] {
    self.options.deviceTypes(for: self.runtimeID)
  }

  public var nameProblem: DeviceNameProblem? {
    DeviceName.problem(in: self.name)
  }

  /// 만들기를 누를 수 있는지: 이름에 문제가 없고, 고른 조합을 만들 수 있다.
  public var canSubmit: Bool {
    self.nameProblem == nil && self.options.contains(runtime: self.runtimeID, deviceType: self.deviceTypeID)
  }

  public var runtime: DeviceRuntime? {
    self.options.runtimes.first { $0.id == self.runtimeID }
  }

  mutating func nameChanged(_ name: String) {
    self.name = name
    self.isNameEdited = true
  }

  /// 목록에 없는 런타임이면 무시. 지금 종류를 지원하면 유지, 아니면 첫 종류. 이름 미편집이면 종류 이름으로.
  mutating func runtimeChanged(_ id: DeviceRuntime.ID) {
    guard self.options.runtimes.contains(where: { $0.id == id }) else { return }
    self.runtimeID = id
    if !self.options.contains(runtime: id, deviceType: self.deviceTypeID),
       let first = self.options.defaultDeviceType(for: id)
    {
      self.deviceTypeID = first.id
    }
    self.followDeviceTypeName()
  }

  /// 지금 런타임의 종류가 아니면 무시. 이름 미편집이면 종류 이름으로.
  mutating func deviceTypeChanged(_ id: DeviceType.ID) {
    guard self.options.contains(runtime: self.runtimeID, deviceType: id) else { return }
    self.deviceTypeID = id
    self.followDeviceTypeName()
  }

  private mutating func followDeviceTypeName() {
    guard !self.isNameEdited,
          let deviceType = self.deviceTypes.first(where: { $0.id == self.deviceTypeID })
    else { return }
    self.name = deviceType.name
  }
}
