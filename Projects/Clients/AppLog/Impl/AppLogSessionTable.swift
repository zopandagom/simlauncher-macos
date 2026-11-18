import AppLogInterface
import Core
import Foundation

/// 버퍼·세션 수 상한.
struct AppLogLimits: Sendable {
  /// 세션당 최근 줄 수.
  var maxLines = 50000
  /// 세션당 줄 텍스트(UTF-8) 바이트. 긴 줄이 많을 때 줄 수 상한만으로는 세션당 수백 MB 가 될 수 있어 함께 둔다.
  var maxBytes = 32 * 1024 * 1024
  /// 기기당 남기는 세션 수 (끝난 세션부터 정리한다).
  var sessionsPerDevice = 5

  static let standard = AppLogLimits()
}

/// 같은 기기·같은 앱. 새 실행·다시 설치가 앞 세션을 대체하는 단위.
struct AppLogSessionKey: Hashable, Sendable {
  let target: AppLogTarget
  let appID: String
}

/// 대체 표시를 단 쪽. 둘 다 되돌려질 때만 표시가 내려간다.
enum AppLogReplacementMark: Hashable, Sendable {
  /// `replacementWillStart` (다시 설치).
  case install
  /// 같은 키의 새 실행.
  case launch(AppLogSessionID)
}

/// 다시 실행에 쓰는 실행 정보 (플랫폼별 앱·기기).
struct AppLogLaunchSpec: Hashable, Sendable {
  enum App: Hashable, Sendable {
    case iOS(AppBundleID, VirtualDevice.ID)
    case android(AndroidPackageName, AndroidVirtualDevice.ID)
  }

  let app: App
  let appName: String
  /// iOS 앱 버전 (Android 는 nil).
  let appVersion: AppLogAppVersion?
  let deviceName: String
  let deviceOS: AppLogDeviceOS?

  /// 앱 버전만 바꾼 실행 정보 (다시 실행).
  func with(appVersion: AppLogAppVersion?) -> AppLogLaunchSpec {
    AppLogLaunchSpec(
      app: self.app,
      appName: self.appName,
      appVersion: appVersion,
      deviceName: self.deviceName,
      deviceOS: self.deviceOS
    )
  }

  var target: AppLogTarget {
    switch self.app {
    case let .iOS(_, device): .iOS(device)
    case let .android(_, device): .android(device)
    }
  }

  /// iOS 는 번들 ID, Android 는 패키지 이름.
  var appID: String {
    switch self.app {
    case let .iOS(bundleID, _): bundleID.rawValue
    case let .android(package, _): package.rawValue
    }
  }

  var key: AppLogSessionKey {
    AppLogSessionKey(target: self.target, appID: self.appID)
  }
}

/// 세션 하나의 기록.
struct AppLogSessionRecord {
  var summary: AppLogSessionSummary
  let spec: AppLogLaunchSpec
  /// 실행 신호를 받아(또는 신호 대기 상한이 지나) 목록에 보인다. 공개 전 실패면 세션을 버린다.
  var isPublished = false
  var marks: Set<AppLogReplacementMark> = []
  /// 이 실행이 시작할 때 대체 표시를 단 세션 (신호 전에 실패하면 되돌린다).
  var markedOnStart: [AppLogSessionID] = []
  /// 이 실행이 시작할 때 다시 설치 표시(`.install`)를 이 실행 표시로 바꾼 세션. 신호 전에 실패·멈추면 그 표시를 되돌린다
  /// (설치는 이미 끝나 앞 앱을 끝냈거나 곧 끝낸다, 측정). 그 사이 설치가 되돌려지면(`unmarkInstall`) 비운다.
  var installMarksTaken: [AppLogSessionID] = []
  var buffer: AppLogBuffer

  var key: AppLogSessionKey {
    AppLogSessionKey(target: self.summary.target, appID: self.summary.appID)
  }

  var isReceiving: Bool {
    self.summary.state == .receiving
  }
}

/// 모든 세션의 상태와 규칙 (순수). 받기 작업·구독은 `AppLogClientImpl` 이 갖는다.
struct AppLogSessionTable {
  let limits: AppLogLimits
  private(set) var records: [AppLogSessionID: AppLogSessionRecord] = [:]
  /// 시작 순.
  private(set) var order: [AppLogSessionID] = []
  /// 같은 기기·앱으로 가장 늦게 실행을 요청한 앱 버전 (다시 실행이 쓴다). 실행 요청(`begin`) 때 바꾸고, 그 실행이 버려지거나
  /// 세션이 정리돼도 지우지 않는다 (신호 전에 실패한 실행도 그 버전은 이미 설치돼 있다).
  private(set) var latestVersions: [AppLogSessionKey: AppLogAppVersion] = [:]

  /// 공개된 세션 요약, 시작 순.
  var publishedSummaries: [AppLogSessionSummary] {
    self.order.compactMap { id in
      guard let record = self.records[id], record.isPublished else { return nil }
      return record.summary
    }
  }

  func record(_ id: AppLogSessionID) -> AppLogSessionRecord? {
    self.records[id]
  }

  /// 같은 기기·앱으로 가장 늦게 실행을 요청한 앱 버전. 그 실행이 버전을 몰랐으면(nil) nil.
  func latestVersion(for key: AppLogSessionKey) -> AppLogAppVersion? {
    self.latestVersions[key]
  }

  /// 새 실행을 시작 중(비공개)으로 넣는다. 같은 키의 받는 중·시작 중 세션에 이 실행의 대체 표시를 단다
  /// (다시 설치 표시는 이 실행 표시로 바꾸고 바꾼 세션을 남긴다: 이 실행이 신호 전에 실패·멈추면 `discard` 가 그 세션에 다시 설치
  /// 표시를 되돌린다. 설치는 이미 앞 앱을 끝냈거나 곧 끝낸다, 측정).
  mutating func begin(_ summary: AppLogSessionSummary, spec: AppLogLaunchSpec) {
    let key = AppLogSessionKey(target: summary.target, appID: summary.appID)
    self.latestVersions[key] = spec.appVersion
    var marked: [AppLogSessionID] = []
    var installTaken: [AppLogSessionID] = []
    for id in self.order {
      guard var record = self.records[id], record.key == key, record.isReceiving else { continue }
      if record.marks.remove(.install) != nil {
        installTaken.append(id)
      }
      record.marks.insert(.launch(summary.id))
      self.records[id] = record
      marked.append(id)
    }
    self.records[summary.id] = AppLogSessionRecord(
      summary: summary,
      spec: spec,
      markedOnStart: marked,
      installMarksTaken: installTaken,
      buffer: AppLogBuffer(maxLines: self.limits.maxLines, maxBytes: self.limits.maxBytes)
    )
    self.order.append(summary.id)
  }

  /// 신호 전에 실패·멈춘 실행을 버리고, 그 실행이 단 대체 표시를 되돌리고, 그 실행이 가져간 다시 설치 표시는 아직 받는 중인
  /// 세션에 되살린다 (이미 끝난 세션은 그대로).
  mutating func discard(_ id: AppLogSessionID) {
    guard let record = self.records.removeValue(forKey: id) else { return }
    self.order.removeAll { $0 == id }
    for markedID in record.markedOnStart {
      self.records[markedID]?.marks.remove(.launch(id))
    }
    for takenID in record.installMarksTaken where self.records[takenID]?.isReceiving == true {
      self.records[takenID]?.marks.insert(.install)
    }
  }

  /// 공개한다. 그 기기의 공개 세션이 상한을 넘으면 **끝난** 세션 중 오래된 것부터 지우고 지운 ID 를 돌려준다
  /// (받는 중 세션은 지우지 않는다: 지우려면 앱을 꺼야 한다). 이미 공개됐거나 없으면 nil.
  mutating func publish(_ id: AppLogSessionID) -> [AppLogSessionID]? {
    guard var record = self.records[id], !record.isPublished else { return nil }
    record.isPublished = true
    self.records[id] = record
    let target = record.summary.target
    let sameDevice = self.order
      .filter { self.records[$0].map { $0.isPublished && $0.summary.target == target } ?? false }
    var excess = sameDevice.count - self.limits.sessionsPerDevice
    var removed: [AppLogSessionID] = []
    for candidate in sameDevice where excess > 0 {
      guard let candidateRecord = self.records[candidate], !candidateRecord.isReceiving else { continue }
      self.records[candidate] = nil
      self.order.removeAll { $0 == candidate }
      removed.append(candidate)
      excess -= 1
    }
    return removed
  }

  /// 다시 설치 전: 같은 키의 받는 중 세션에 표시를 단다.
  mutating func markInstall(_ key: AppLogSessionKey) {
    for id in self.order {
      guard let record = self.records[id], record.key == key, record.isReceiving else { continue }
      self.records[id]?.marks.insert(.install)
    }
  }

  /// 다시 설치 실패: `markInstall` 을 되돌리고, 시작 중인 실행이 가져간 다시 설치 표시도 되살리지 않게 비운다.
  mutating func unmarkInstall(_ key: AppLogSessionKey) {
    for id in self.order where self.records[id]?.key == key {
      self.records[id]?.marks.remove(.install)
      self.records[id]?.installMarksTaken = []
    }
  }

  /// 대체 표시가 하나라도 있다.
  func isReplacing(_ id: AppLogSessionID) -> Bool {
    !(self.records[id]?.marks.isEmpty ?? true)
  }

  /// 받는 중이면 끝냄으로 바꾸고 true.
  mutating func end(_ id: AppLogSessionID, reason: AppLogEndReason) -> Bool {
    guard var record = self.records[id], record.isReceiving else { return false }
    record.summary = record.summary.with(state: .ended(reason))
    record.marks = []
    self.records[id] = record
    return true
  }

  /// 줄을 버퍼에 넣는다. 없는 세션이면 false.
  mutating func append(_ texts: [String], to id: AppLogSessionID) -> Bool {
    guard self.records[id] != nil else { return false }
    self.records[id]?.buffer.append(texts)
    return true
  }
}
