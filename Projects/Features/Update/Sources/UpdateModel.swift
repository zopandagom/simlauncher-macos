import Core
import Foundation
import Observation
import PreferencesInterface
import UpdateCheckInterface

/// 업데이트 알림. App 이 하나를 만들어 메인 창 배너(`UpdateBanner`)·메뉴(`UpdateCommands`)·업데이트 확인 창(`UpdateCheckView`)이
/// 함께 쓰고, 자동 확인은 App 의 `AppDelegate` 가 실행(`appLaunched()`)·활성화(`appBecameActive()`) 때 부른다.
/// 자동 확인은 설정이 켜져 있고, 마지막 확인 기록(서버가 답한 확인)에서 24시간이 지났고(없거나 미래 포함), 이 실행에서 마지막
/// 요청 시작에서 1시간이 지났을 때(없거나 미래 포함)만 요청한다 (Core `UpdateCheckSchedule`). 수동 확인(메뉴·창 열기·"다시 시도")은
/// 이 조건을 보지 않는다. 요청은 동시에 하나이고, 진행 중이면 새로 보내지 않고 그 결과를 함께 쓴다. 판정과 시작 사이에 await 가
/// 없어 실행 직후 실행·활성화가 겹쳐도 요청은 하나다. Model 은 요청을 취소하지 않는다 (창을 닫아도 끝까지 가고 결과는 배너·기록에).
/// 서버가 답한 결과(성공·거절·404·그 밖 HTTP·응답 이상)만 시각을 기록한다. 서버에 닿지 못한 실패는 기록하지 않아 1시간 뒤 다시 한다.
/// 배너는 이 실행의 마지막 성공 결과의 새 버전(`knownLatest`)에서 건너뛴 버전과 숨김(× 로 그 버전을 24시간) 중인 버전을 뺀다.
/// 건너뛰기·숨김을 저장하지 못하면(관리자 강제) 이 실행 동안만 메모리로 지킨다. 배포 저장소가 없는 빌드(`isAvailable` 거짓)면
/// 요청·기록·배너가 모두 없다.
@MainActor
@Observable
public final class UpdateModel {
  /// 배너에 보일 새 버전. 건너뛴 버전·숨김 중인 버전은 넣지 않는다. 메모리에만 (다시 켜면 다음 확인 결과 전까지 없다).
  public private(set) var availableUpdate: AppVersion?
  /// 업데이트 확인 창의 상태. nil 이면 창이 보이지 않거나 곧 확인을 시작한다.
  public private(set) var manualCheck: UpdateCheckPhase?
  /// 이 앱의 버전 (Info.plist). 읽지 못하면 nil 이고, 확인 결과는 비교 불가다.
  public let currentVersion: AppVersion?

  /// 이 빌드에 배포 저장소가 있어 업데이트 기능을 쓴다.
  public var isAvailable: Bool {
    self.releasePageURL != nil
  }

  /// 다운로드 페이지. 빌드 설정의 배포 저장소로 앱이 만든 고정 주소다 (응답 안의 주소가 아니다).
  public var releasePageURL: URL? {
    self.updateCheck.releasePageURL
  }

  @ObservationIgnored private let updateCheck: any UpdateCheckClient
  @ObservationIgnored private let preferences: any PreferencesClient
  @ObservationIgnored private let now: @Sendable () -> Date
  /// 진행 중인 요청 (동시에 최대 1개). 끝나면 nil.
  @ObservationIgnored private var inFlight: Task<Void, Never>?
  /// 이 실행에서 마지막으로 새 요청을 시작한 시각 (자동·수동 모두. 자동 확인의 재시도 간격).
  @ObservationIgnored private var lastRequestStartedAt: Date?
  /// 이 실행에서 마지막으로 받은 성공 결과의 새 버전 (건너뛰기·숨김과 무관). 성공 결과가 새 버전이 아니면 nil, 실패면 그대로.
  @ObservationIgnored private var knownLatest: AppVersion?
  /// 저장하지 못했을 때(키 잠김) 이 실행 동안 쓰는 건너뛰기.
  @ObservationIgnored private var sessionSkipped: AppVersion?
  /// 저장하지 못했을 때(키 잠김) 이 실행 동안 쓰는 숨김.
  @ObservationIgnored private var sessionDismissal: UpdateBannerDismissal?

  public init(
    updateCheck: any UpdateCheckClient,
    preferences: any PreferencesClient,
    currentVersion: AppVersion?,
    now: @escaping @Sendable () -> Date
  ) {
    self.updateCheck = updateCheck
    self.preferences = preferences
    self.currentVersion = currentVersion
    self.now = now
  }

  // MARK: - 이벤트

  /// 앱을 켰다 (`applicationDidFinishLaunching`). 자동 확인 조건이면 확인이 끝날 때까지 기다린다.
  public func appLaunched() async {
    await self.runAutomaticCheck()
  }

  /// 다른 앱에서 돌아왔다 (`applicationDidBecomeActive`). 요청 없이 배너를 다시 판정하고(숨김이 끝났으면 다시 보인다),
  /// 자동 확인 조건이면 확인이 끝날 때까지 기다린다.
  public func appBecameActive() async {
    await self.runAutomaticCheck()
  }

  /// 메뉴 "업데이트 확인…"·창 열기·"다시 시도". 자동 확인 조건을 보지 않는다. 창이 확인 중이면 새로 시작하지 않고 그 확인을
  /// 기다리고, 자동 확인이 진행 중이면 새 요청 없이 그 결과를 창에 보인다.
  public func checkForUpdatesRequested() async {
    guard self.isAvailable else { return }
    if self.manualCheck == .checking {
      await self.inFlight?.value
      return
    }
    self.manualCheck = .checking
    await self.startOrJoin().value
  }

  /// 업데이트 확인 창이 닫혔다. 창 상태만 지우고 요청은 취소하지 않는다 (끝나면 배너·기록만 반영한다).
  public func checkWindowClosed() {
    self.manualCheck = nil
  }

  /// "이 버전 건너뛰기" (배너·창). 저장하지 못하면 이 실행 동안만 건너뛴다. 창이 그 버전의 결과를 보이고 있으면 건너뛴 버전으로 바꾼다.
  public func skipVersionTapped(_ version: AppVersion) {
    guard self.isAvailable else { return }
    self.sessionSkipped = version
    try? self.preferences.setSkippedUpdateVersion(version.description)
    if case let .finished(.newer(shown, current, skipped: false)) = self.manualCheck, shown == version {
      self.manualCheck = .finished(.newer(shown, current: current, skipped: true))
    }
    self.refreshBanner()
  }

  /// 배너의 닫기(×): 지금 배너의 버전을 24시간 숨긴다. 저장하지 못하면 이 실행 동안만 숨긴다.
  public func bannerDismissed() {
    guard let version = self.availableUpdate else { return }
    let dismissal = UpdateBannerDismissal(version: version, dismissedAt: self.now())
    self.sessionDismissal = dismissal
    try? self.preferences.setUpdateBannerDismissal(dismissal)
    self.refreshBanner()
  }

  // MARK: - 흐름

  /// 요청 없이 배너를 다시 판정한 뒤, 자동 확인 조건이면 요청(또는 진행 중 요청에 합류)하고 끝나기를 기다린다.
  private func runAutomaticCheck() async {
    self.refreshBanner()
    guard self.shouldStartAutomaticCheck() else { return }
    await self.startOrJoin().value
  }

  /// 자동 확인 조건. 앞 조건이 거짓이면 뒤(설정·기록 읽기)를 보지 않는다.
  private func shouldStartAutomaticCheck() -> Bool {
    guard self.isAvailable,
          self.preferences.automaticUpdateCheck().isEnabled,
          self.inFlight == nil
    else { return false }
    let now = self.now()
    return UpdateCheckSchedule.isDue(lastCheck: self.preferences.lastUpdateCheck(), now: now)
      && UpdateCheckSchedule.isRetryDue(lastAttempt: self.lastRequestStartedAt, now: now)
  }

  /// 진행 중인 요청이 있으면 그것을, 없으면 새 요청을 시작해 돌려준다. await 가 없어 판정한 그 자리에서 시작한다.
  private func startOrJoin() -> Task<Void, Never> {
    if let inFlight = self.inFlight {
      return inFlight
    }
    self.lastRequestStartedAt = self.now()
    let task = Task {
      await self.performCheck()
    }
    self.inFlight = task
    return task
  }

  /// 요청 하나를 보내고 결과를 반영한다. await 는 Client 호출 하나이고, 반영은 그 뒤 한 번에(await 없이) 한다.
  private func performCheck() async {
    let outcome: Result<AppVersion?, UpdateCheckError>
    do throws(UpdateCheckError) {
      outcome = try await .success(self.updateCheck.latestReleaseVersion())
    } catch {
      outcome = .failure(error)
    }
    // 반영 맨 앞에서 비워, 반영 뒤 들어온 요청은 새 요청을 만든다.
    self.inFlight = nil
    if Self.shouldRecord(outcome) {
      self.preferences.setLastUpdateCheck(self.now())
    }
    let report = self.report(for: outcome)
    switch self.manualCheck {
    case .checking:
      self.manualCheck = .finished(report)
    case .finished:
      // 창이 지난 결과를 보이는 동안 자동 확인이 새 결과를 내면 배너와 어긋나지 않게 창도 바꾼다.
      // 자동 확인의 실패는 조용하다: 보이고 있는 결과를 덮지 않는다.
      if case .failed = report {
        break
      }
      self.manualCheck = .finished(report)
    case nil:
      break
    }
    self.refreshBanner()
  }

  /// 시각을 기록하는 결과: 성공과 서버가 HTTP 로 답한 실패.
  private static func shouldRecord(_ outcome: Result<AppVersion?, UpdateCheckError>) -> Bool {
    switch outcome {
    case .success:
      true
    case let .failure(error):
      error.serverAnswered
    }
  }

  /// 결과를 창에 보일 값으로 바꾸고, 성공이면 `knownLatest` 를 바꾼다 (실패면 그대로 둔다).
  private func report(for outcome: Result<AppVersion?, UpdateCheckError>) -> UpdateCheckReport {
    let latest: AppVersion?
    switch outcome {
    case let .failure(error):
      return .failed(error)
    case let .success(version):
      latest = version
    }
    let skipped: Set<AppVersion> = if let latest, self.isSkipped(latest) {
      [latest]
    } else {
      []
    }
    switch UpdateAvailability.judge(current: self.currentVersion, latest: latest, skipped: skipped) {
    case let .newer(version, skipped):
      // judge 는 current 가 있을 때만 .newer 를 낸다.
      guard let current = self.currentVersion else {
        self.knownLatest = nil
        return .currentUnknown
      }
      self.knownLatest = version
      return .newer(version, current: current, skipped: skipped)
    case .upToDate:
      self.knownLatest = nil
      guard let current = self.currentVersion else { return .currentUnknown }
      return .upToDate(current: current)
    case .currentUnknown:
      self.knownLatest = nil
      return .currentUnknown
    case .latestUnrecognized:
      self.knownLatest = nil
      return .latestUnrecognized
    }
  }

  /// 이 실행의 마지막 성공 결과로 배너를 정한다 (요청하지 않는다). 건너뛰기가 숨김보다 먼저다.
  private func refreshBanner() {
    guard let version = self.knownLatest else {
      self.availableUpdate = nil
      return
    }
    self.availableUpdate = self.isSkipped(version) || self.isDismissed(version) ? nil : version
  }

  private func isSkipped(_ version: AppVersion) -> Bool {
    if version == self.sessionSkipped {
      return true
    }
    return self.preferences.skippedUpdateVersion().flatMap(AppVersion.init) == version
  }

  private func isDismissed(_ version: AppVersion) -> Bool {
    let now = self.now()
    if self.sessionDismissal?.hides(version, now: now) == true {
      return true
    }
    return self.preferences.updateBannerDismissal()?.hides(version, now: now) == true
  }
}
