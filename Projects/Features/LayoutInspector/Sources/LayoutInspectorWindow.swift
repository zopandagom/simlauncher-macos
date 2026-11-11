import Core
import ScreenLayoutInterface

/// 레이아웃 창이 보일 실패 분류. `ScreenLayoutError` 를 화면 문구 단위로 묶는다 (취소는 화면에 보이지 않아 없다).
public enum LayoutInspectorFailure: Hashable, Sendable, CaseIterable {
  /// 기기를 찾을 수 없거나 쓸 수 없다.
  case deviceGone
  case deviceNotBooted
  case toolsUnavailable
  case screenNotIdle
  case displayOff
  case automationBusy
  case timedOut
  case unreadable
  /// 이 빌드가 읽지 못하는 플랫폼 (지금은 나오지 않는다. 남겨 둔 case).
  case unsupported
  // iOS (XCUITest 러너 경로가 만든다)
  case xcodeUnavailable
  case setupFailed
  /// 읽는 동안 앞 앱이 사라졌다 (앞 앱이 없으면 시스템 화면을 읽으므로 실패가 아니다).
  case appNotInForeground

  /// 실패 분류. `.cancelled` 는 화면에 보일 실패가 아니라 nil.
  init?(_ error: ScreenLayoutError) {
    switch error {
    case .deviceNotFound, .deviceUnavailable: self = .deviceGone
    case .deviceNotBooted: self = .deviceNotBooted
    case .toolsUnavailable: self = .toolsUnavailable
    case .screenNotIdle: self = .screenNotIdle
    case .displayOff: self = .displayOff
    case .automationBusy: self = .automationBusy
    case .timedOut: self = .timedOut
    case .cancelled: return nil
    default: self = Self.platformFailure(error)
    }
  }

  /// 읽기 자체가 아니라 플랫폼·iOS 준비에서 나오는 실패와 그 밖의 실패(`.unreadable`).
  private static func platformFailure(_ error: ScreenLayoutError) -> Self {
    switch error {
    case .unsupportedPlatform: .unsupported
    case .xcodeUnavailable: .xcodeUnavailable
    case .inspectorSetupFailed: .setupFailed
    case .appNotInForeground: .appNotInForeground
    default: .unreadable
    }
  }
}

/// 레이아웃 창 하나(대상 하나)의 상태: 마지막으로 읽은 스냅샷, 읽는 단계, 마지막 실패, 고른 뷰.
/// 규칙만 담은 값이고 Client 호출은 `LayoutInspectorModel` 이 한다. 창을 닫으면 Model 이 값을 통째로 버린다.
/// 스냅샷은 새로 고침·실패 중에도 남는다(마지막 성공). 실패는 새 읽기를 시작하거나 성공하면 지운다.
public struct LayoutInspectorWindow: Hashable, Sendable {
  public private(set) var snapshot: LayoutSnapshot?
  /// 읽는 단계. nil 이면 읽지 않는 중이다.
  public private(set) var loading: LayoutReadPhase?
  public private(set) var failure: LayoutInspectorFailure?
  /// 클릭한 점과 고른 노드. 새 스냅샷을 읽으면 같은 점으로 다시 고른다.
  public private(set) var pick: LayoutPick?
  /// 첫 스냅샷 전 제목에 쓸 기기 이름 (Client 의 `deviceName(of:)`). 모르면 nil.
  public private(set) var deviceName: String?

  public init() {}

  public var isLoading: Bool {
    self.loading != nil
  }

  /// 읽기를 시작한다: 단계는 `.reading`, 앞 실패를 지운다. 스냅샷·고름은 그대로다.
  mutating func beginReading() {
    self.loading = .reading
    self.failure = nil
  }

  /// 기기 이름을 알았다.
  mutating func deviceNameResolved(_ name: String) {
    self.deviceName = name
  }

  /// 읽는 중일 때만 단계를 바꾼다.
  mutating func phaseChanged(_ phase: LayoutReadPhase) {
    guard self.loading != nil else { return }
    self.loading = phase
  }

  /// 새 스냅샷. 앞에 고른 점이 있으면 새 스냅샷에서 같은 점으로 다시 고른다 (점이 화면 밖이거나 노드가 없으면 고름 해제).
  /// 노드 번호는 덤프마다 다시 매기므로 앞 번호는 쓰지 않는다.
  mutating func readSucceeded(_ snapshot: LayoutSnapshot) {
    self.snapshot = snapshot
    self.loading = nil
    self.failure = nil
    self.pick = self.pick.flatMap { LayoutPick(point: $0.point, in: snapshot) }
  }

  /// 실패. 스냅샷과 고름은 남긴다.
  mutating func readFailed(_ failure: LayoutInspectorFailure) {
    self.failure = failure
    self.loading = nil
  }

  /// 실패로 보이지 않고 읽기만 끝낸다 (취소).
  mutating func readEnded() {
    self.loading = nil
  }

  /// 캔버스 클릭: 점의 가장 안쪽 노드를 고른다. 빈 곳(노드 없음)이면 고름을 푼다. 스냅샷이 없으면 아무것도 하지 않는다.
  mutating func canvasClicked(at point: LayoutPoint) {
    guard let snapshot = self.snapshot else { return }
    self.pick = LayoutPick(point: point, in: snapshot)
  }

  /// 목록에서 고르기: 지금 스택에 든 번호일 때만 바꾼다.
  mutating func stackNodeSelected(_ id: LayoutNode.ID) {
    self.pick?.select(id)
  }
}
