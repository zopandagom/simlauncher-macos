import AppLogInterface
import Core
import Foundation

/// 상태를 바꾸지 않는 읽기. View 가 쓴다.
public extension DeviceLogModel {
  /// 창의 상태. 아직 열린 적이 없으면 기본값.
  func window(for target: AppLogTarget) -> DeviceLogWindow {
    self.windows[target] ?? DeviceLogWindow()
  }

  /// 대상의 세션 (시작 시각 순).
  func sessions(for target: AppLogTarget) -> [AppLogSessionSummary] {
    DeviceLogSessionChoice.sessions(of: target, in: self.sessions)
  }

  /// 창이 보이는 세션.
  func selectedSession(for target: AppLogTarget) -> AppLogSessionSummary? {
    guard let id = self.windows[target]?.selectedSessionID else { return nil }
    return self.sessions.first { $0.id == id }
  }

  /// 창 제목: "<기기 이름> 로그". 세션이 없으면 "앱 로그".
  func title(for target: AppLogTarget) -> String {
    guard let deviceName = self.sessions.last(where: { $0.target == target })?.deviceName else {
      return DeviceLogText.defaultWindowTitle
    }
    return DeviceLogText.windowTitle(deviceName: deviceName)
  }
}
