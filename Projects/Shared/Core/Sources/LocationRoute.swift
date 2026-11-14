/// 위치 경로 (iOS `simctl location start`): 경유지를 차례로 정한 속도로 움직인다. 경로는 simctl 이 끝난 뒤에도 기기 안에서 이어지고,
/// 끝나면 마지막 점에 머문다 (실측). 경유지 수는 `parseWaypoints` 가 2…`waypointLimit` 로 막는다.
public struct LocationRoute: Hashable, Sendable {
  public static let waypointLimit = 100

  public let waypoints: [GeoCoordinate]
  public let speed: LocationRouteSpeed

  public init(waypoints: [GeoCoordinate], speed: LocationRouteSpeed) {
    self.waypoints = waypoints
    self.speed = speed
  }

  /// 한 줄에 한 지점("위도, 경도", `GeoCoordinate.parse`). `\n`·`\r\n` 으로 나누고 공백뿐인 줄은 건너뛴다.
  /// 처음 문제 하나만: 줄 문제는 원문 줄 번호(1부터)와 함께, 지점이 2개 미만(빈 입력 포함)이면 `.tooFewWaypoints`,
  /// `waypointLimit` 를 넘으면 `.tooManyWaypoints` (넘는 순간 멈춘다).
  public static func parseWaypoints(_ text: String) -> Result<[GeoCoordinate], LocationRouteProblem> {
    var waypoints: [GeoCoordinate] = []
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (index, line) in lines.enumerated() {
      switch GeoCoordinate.parse(String(line)) {
      case .failure(.empty):
        continue
      case let .failure(problem):
        return .failure(.line(number: index + 1, problem))
      case let .success(coordinate):
        waypoints.append(coordinate)
        if waypoints.count > Self.waypointLimit {
          return .failure(.tooManyWaypoints)
        }
      }
    }
    return waypoints.count < 2 ? .failure(.tooFewWaypoints) : .success(waypoints)
  }
}

/// `LocationRoute.parseWaypoints` 가 거절한 이유 (처음 하나).
public enum LocationRouteProblem: Error, Hashable, Sendable {
  /// 원문 줄 번호(1부터)와 그 줄의 문제 (`.empty` 는 오지 않는다: 빈 줄은 건너뛴다).
  case line(number: Int, GeoCoordinateProblem)
  case tooFewWaypoints
  case tooManyWaypoints
}

/// 경로 속도 단계. 모두 0 보다 크다: simctl 은 `--speed=0` 을 거절하고, 음수는 받아 곧바로 끝점으로 간다 (실측).
public enum LocationRouteSpeed: String, CaseIterable, Hashable, Sendable {
  case walking
  case running
  case cycling
  case driving
  case highway

  public static let `default` = LocationRouteSpeed.walking

  /// 초당 미터 (simctl `--speed=` 값).
  public var metersPerSecond: Double {
    switch self {
    case .walking: 1.4
    case .running: 3.0
    case .cycling: 6.0
    case .driving: 14.0
    case .highway: 28.0
    }
  }
}
