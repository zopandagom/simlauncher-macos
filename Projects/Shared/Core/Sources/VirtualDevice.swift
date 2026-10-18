/// 시뮬레이터 기기 하나.
public struct VirtualDevice: Identifiable, Hashable, Sendable {
  /// 기기 UDID.
  public struct ID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// 기기 종류. 섹션 안 정렬은 phone → tablet → 그 밖 순서.
  public enum Family: Hashable, Sendable {
    case phone, tablet, watch, tv, vision, other
  }

  /// 기기 상태. simctl 이 모르는 값을 주면 `.unknown`.
  public enum State: Hashable, Sendable {
    case shutdown, booting, booted, shuttingDown, unknown
  }

  /// 쓸 수 없는 이유. simctl 의 오류 문구가 아니라 런타임·기기 종류 목록과 대조해 정한다.
  public enum UnavailableReason: Hashable, Sendable {
    case runtimeNotInstalled, runtimeUnavailable, deviceTypeNotSupported, unknown
  }

  public enum Availability: Hashable, Sendable {
    case available
    case unavailable(UnavailableReason)
  }

  public let id: ID
  /// 사용자가 붙인 기기 이름. 번역하지 않고 그대로 보인다.
  public let name: String
  public let family: Family
  public let state: State
  public let availability: Availability
  public let runtime: DeviceRuntime

  public init(id: ID, name: String, family: Family, state: State, availability: Availability, runtime: DeviceRuntime) {
    self.id = id
    self.name = name
    self.family = family
    self.state = state
    self.availability = availability
    self.runtime = runtime
  }
}
