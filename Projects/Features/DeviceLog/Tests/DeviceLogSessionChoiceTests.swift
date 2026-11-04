import AppLogInterface
import Core
import Foundation
import Testing
@testable import DeviceLogFeature

/// 열린 창이 세션 목록 알림 뒤 보일 세션을 고르는 규칙 (`DeviceLogSessionChoice.selection`).
@MainActor
struct DeviceLogSessionChoiceTests {
  typealias Support = DeviceLogTestSupport

  private let earlier = Support.summary(at: 0, state: .ended(.replaced))
  private let later = Support.summary(at: 10)

  private var previous: Set<AppLogSessionID> {
    [self.earlier.id, self.later.id]
  }

  private func choose(
    _ current: AppLogSessionID?, previous: Set<AppLogSessionID>, in sessions: [AppLogSessionSummary]
  ) -> AppLogSessionID? {
    DeviceLogSessionChoice.selection(current: current, of: Support.target, previous: previous, in: sessions)
  }

  @Test("앞 실행을 고른 뒤 같은 앱 최신 세션의 상태만 바뀌면 앞 실행 그대로다")
  func keepsEarlierOnStateChange() {
    let sessions = [self.earlier, self.later.with(state: .ended(.appExited))]
    #expect(self.choose(self.earlier.id, previous: self.previous, in: sessions) == self.earlier.id)
  }

  @Test("다른 기기 세션·다른 앱의 새 세션이 생겨도 앞 실행 그대로다")
  func keepsEarlierOnOtherSessions() {
    let otherDevice = Support.summary(at: 20, target: Support.otherTarget)
    let otherApp = Support.summary("com.example.other", at: 30)
    let sessions = [self.earlier, self.later, otherDevice, otherApp]
    #expect(self.choose(self.earlier.id, previous: self.previous, in: sessions) == self.earlier.id)
  }

  @Test("같은 앱의 새 세션이 생기면 앞 실행을 골랐든 최신을 골랐든 그것으로 옮긴다")
  func movesToNewSameAppSession() {
    let newest = Support.summary(at: 40)
    let sessions = [self.earlier, self.later, newest]
    #expect(self.choose(self.earlier.id, previous: self.previous, in: sessions) == newest.id)
    #expect(self.choose(self.later.id, previous: self.previous, in: sessions) == newest.id)
  }

  @Test("고른 세션이 앞 목록에 있었고 빠지면 대상의 가장 늦은 세션, 대상 세션이 없으면 nil 이다")
  func movesWhenRemoved() {
    let otherDevice = Support.summary(at: 20, target: Support.otherTarget)
    #expect(self.choose(self.earlier.id, previous: self.previous, in: [self.later, otherDevice]) == self.later.id)
    #expect(self.choose(self.earlier.id, previous: self.previous, in: [otherDevice]) == nil)
  }

  @Test("같은 앱 최신 세션이 정리되고 앞 실행을 고른 상태면 앞 실행 그대로다")
  func keepsEarlierWhenLatestRemoved() {
    #expect(self.choose(self.earlier.id, previous: self.previous, in: [self.earlier]) == self.earlier.id)
  }

  @Test("고른 세션이 앞 목록에 없으면(다시 실행 결과가 알림보다 먼저 옴) 새 목록에 없든 있든 그대로다")
  func keepsUnseenSelection() {
    let relaunched = Support.summary(at: 40)
    #expect(self.choose(relaunched.id, previous: self.previous, in: [self.earlier, self.later]) == relaunched.id)
    let sessions = [self.earlier, self.later, relaunched]
    #expect(self.choose(relaunched.id, previous: self.previous, in: sessions) == relaunched.id)
  }

  @Test("고른 세션이 없으면 대상의 가장 늦은 세션, 대상 세션이 없으면 nil 이다")
  func selectsLatestWithoutCurrent() {
    #expect(self.choose(nil, previous: [], in: [self.earlier, self.later]) == self.later.id)
    let otherDevice = Support.summary(at: 20, target: Support.otherTarget)
    #expect(self.choose(nil, previous: [], in: [otherDevice]) == nil)
  }
}
