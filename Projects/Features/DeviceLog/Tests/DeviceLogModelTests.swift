import AppLogInterface
import AppLogTesting
import Core
import Foundation
import Testing
@testable import DeviceLogFeature

@MainActor
struct DeviceLogModelOpenTests {
  typealias Support = DeviceLogTestSupport

  @Test("창을 열면 대상의 가장 늦게 시작한 세션을 골라 그때까지의 줄을 보인다")
  func opensLatestSession() async {
    let older = Support.summary("com.example.other", at: 0, state: .ended(.appExited))
    let latest = Support.summary(at: 10)
    let elsewhere = Support.summary(at: 20, target: Support.otherTarget)
    let (model, fake) = Support.fixture([older, latest, elsewhere])
    fake.append(["probe start", "tick 1"], to: latest.id)
    await Support.openAndWait(model, expecting: latest.id, visible: 2)
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["probe start", "tick 1"])
    #expect(model.sessions(for: Support.target).map(\.id) == [older.id, latest.id])
    #expect(model.title(for: Support.target) == DeviceLogText.windowTitle(deviceName: "iPhone 17 Pro"))
  }

  @Test("세션 목록 첫 알림이 창을 연 뒤에 와도 가장 늦은 세션을 고른다")
  func selectsWhenFirstSessionNoticeArrivesLate() async {
    let latest = Support.summary(at: 10)
    let (model, fake) = Support.fixture([Support.summary(at: 0), latest])
    fake.append(["a"], to: latest.id)
    model.windowAppeared(Support.target)
    // 구독 작업이 아직 돌지 않아 고를 세션이 없다.
    #expect(model.window(for: Support.target).selectedSessionID == nil)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    #expect(model.window(for: Support.target).selectedSessionID == latest.id)
  }

  @Test("세션이 없던 대상에 세션이 생기면 고른다")
  func selectsWhenSessionAppears() async {
    let (model, fake) = Support.fixture([])
    model.windowAppeared(Support.target)
    await Support.settle()
    #expect(model.window(for: Support.target).selectedSessionID == nil)
    #expect(model.title(for: Support.target) == DeviceLogText.defaultWindowTitle)
    let session = Support.summary()
    fake.publish(session)
    await Support.waitUntil { model.window(for: Support.target).selectedSessionID == session.id }
  }

  @Test("새 묶음이 끝에 붙고, 같은 번호는 두 번 붙지 않는다")
  func batchesAppend() async {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["a"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 1)
    let generation = model.window(for: Support.target).displayGeneration
    fake.append(["b", "c"], to: session.id)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 3 }
    let window = model.window(for: Support.target)
    #expect(Support.texts(window.visibleLines) == ["a", "b", "c"])
    #expect(window.totalCount == 3)
    // 끝에 붙인 것이라 표는 전부 다시 읽지 않는다.
    #expect(window.displayGeneration == generation)
  }

  @Test("사용자가 고른 세션을 보이고, 같은 세션을 다시 고르면 아무것도 하지 않는다")
  func selectsSession() async {
    let first = Support.summary("com.example.other", at: 0)
    let second = Support.summary(at: 10)
    let (model, fake) = Support.fixture([first, second])
    fake.append(["other 1"], to: first.id)
    fake.append(["probe 1", "probe 2"], to: second.id)
    await Support.openAndWait(model, expecting: second.id, visible: 2)
    model.sessionSelected(first.id, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["other 1"])
    let generation = model.window(for: Support.target).displayGeneration
    model.sessionSelected(first.id, in: Support.target)
    #expect(model.window(for: Support.target).displayGeneration == generation)
  }

  @Test("같은 기기·같은 앱의 더 늦은 세션이 생기면 옮기고, 다른 앱의 새 세션으로는 옮기지 않는다")
  func followsSameAppOnly() async {
    let session = Support.summary(at: 0)
    let (model, fake) = Support.fixture([session])
    fake.append(["old"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 1)
    let otherApp = Support.summary("com.example.other", at: 5)
    fake.publish(otherApp)
    await Support.waitUntil { model.sessions.count == 2 }
    await Support.settle()
    #expect(model.window(for: Support.target).selectedSessionID == session.id)
    fake.publish(session.with(state: .ended(.replaced)))
    let replacement = Support.summary(at: 10)
    fake.append(["new"], to: replacement.id)
    fake.publish(replacement)
    await Support.waitUntil {
      model.window(for: Support.target).selectedSessionID == replacement.id
        && model.window(for: Support.target).visibleCount == 1
    }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["new"])
  }

  @Test("고른 세션이 정리되면 대상의 가장 늦은 세션으로 옮기고, 남은 세션이 없으면 빈 화면이다")
  func movesWhenSelectedSessionRemoved() async {
    let first = Support.summary("com.example.other", at: 0, state: .ended(.appExited))
    let second = Support.summary(at: 10)
    let (model, fake) = Support.fixture([first, second])
    await Support.openAndWait(model, expecting: second.id, visible: 0)
    model.sessionSelected(first.id, in: Support.target)
    fake.remove(first.id)
    await Support.waitUntil { model.window(for: Support.target).selectedSessionID == second.id }
    fake.remove(second.id)
    await Support.waitUntil { model.window(for: Support.target).selectedSessionID == nil }
    #expect(model.sessions(for: Support.target).isEmpty)
  }

  @Test("창을 닫으면 줄 구독이 풀리고 줄을 버리며, 필터·따라가기는 남는다")
  func closeKeepsFilter() async throws {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["tick 1", "other"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 2)
    #expect(fake.activeLineSubscriptions(of: session.id) == 1)
    let condition = try #require(model.window(for: Support.target).filter.conditions.first).id
    model.conditionTextChanged(condition, "tick", in: Support.target)
    model.followChanged(false, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    model.windowDisappeared(Support.target)
    let closed = model.window(for: Support.target)
    #expect(!closed.isOpen)
    #expect(closed.lines.isEmpty)
    #expect(closed.visibleLines.isEmpty)
    await Support.waitUntil { fake.activeLineSubscriptions(of: session.id) == 0 }
    // 닫힌 동안 쌓인 줄도 다시 열면 보이고, 필터가 그대로 걸린다.
    fake.append(["tick 2", "more"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 2)
    let reopened = model.window(for: Support.target)
    #expect(Support.texts(reopened.visibleLines) == ["tick 1", "tick 2"])
    #expect(reopened.totalCount == 4)
    #expect(reopened.filter.conditions.first?.text == "tick")
    #expect(!reopened.isFollowing)
  }
}

@MainActor
struct DeviceLogModelFilterTests {
  typealias Support = DeviceLogTestSupport

  private func opened(_ texts: [String]) async -> Support.Opened {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(texts, to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: texts.count)
    return Support.Opened(model: model, fake: fake, session: session)
  }

  private func firstCondition(_ model: DeviceLogModel) -> Int {
    model.window(for: Support.target).filter.conditions.first?.id ?? -1
  }

  @Test("필터를 바꾸면 전체를 다시 거르고 표를 다시 읽는다. 그 뒤 새 줄도 같은 필터로 걸러 붙는다")
  func refilters() async {
    let opened = await self.opened(["tick 1", "probe start", "tick 2"])
    let model = opened.model
    let fake = opened.fake
    let session = opened.session
    let generation = model.window(for: Support.target).displayGeneration
    model.conditionTextChanged(self.firstCondition(model), "tick", in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    #expect(model.window(for: Support.target).displayGeneration > generation)
    #expect(model.window(for: Support.target).totalCount == 3)
    fake.append(["other", "tick 3"], to: session.id)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 3 }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["tick 1", "tick 2", "tick 3"])
  }

  @Test("잘못된 정규식이면 문제만 보이고 줄은 바로 앞 결과 그대로다. 고치면 다시 거른다")
  func invalidRegexKeepsPreviousResult() async {
    let opened = await self.opened(["tick 1", "tick 15", "other"])
    let model = opened.model
    let id = self.firstCondition(model)
    model.conditionTextChanged(id, "tick", in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    model.conditionKindChanged(id, .regex, in: Support.target)
    model.conditionTextChanged(id, "(", in: Support.target)
    await Support.settle()
    let window = model.window(for: Support.target)
    #expect(window.filterProblem == .invalidRegex(conditionID: id))
    #expect(window.visibleCount == 2)
    model.conditionTextChanged(id, #"tick \d*5$"#, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    #expect(model.window(for: Support.target).filterProblem == nil)
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["tick 15"])
  }

  @Test("조건 더하기·제외·대소문자·지우기가 거르기에 반영된다")
  func conditionEvents() async throws {
    let opened = await self.opened(["tick 1", "TICK 2", "probe", "tick 5"])
    let model = opened.model
    let first = self.firstCondition(model)
    model.conditionTextChanged(first, "tick", in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 3 }
    model.caseSensitivityChanged(true, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    model.conditionAdded(in: Support.target)
    let second = try #require(model.window(for: Support.target).filter.conditions.last).id
    model.conditionTextChanged(second, "5", in: Support.target)
    model.conditionExclusionChanged(second, true, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["tick 1"])
    model.conditionRemoved(second, in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    let visible = model.window(for: Support.target).visibleLines
    #expect(Support.texts(visible) == ["tick 1", "tick 5"])
    #expect(visible.map(\.highlights) == [
      [LogHighlight(location: 0, length: 4)],
      [LogHighlight(location: 0, length: 4)],
    ])
  }

  @Test("필터를 바꿔 결과가 오면 보이는 모든 줄의 강조가 새 필터의 것이다")
  func highlightsFollowNewFilter() async {
    let opened = await self.opened(["tick 1", "probe tick", "other"])
    let model = opened.model
    let id = self.firstCondition(model)
    model.conditionTextChanged(id, "tick", in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    #expect(model.window(for: Support.target).visibleLines.map(\.highlights) == [
      [LogHighlight(location: 0, length: 4)], [LogHighlight(location: 6, length: 4)],
    ])
    model.conditionTextChanged(id, "probe", in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    let visible = model.window(for: Support.target).visibleLines
    #expect(Support.texts(visible) == ["probe tick"])
    #expect(visible.map(\.highlights) == [[LogHighlight(location: 0, length: 5)]])
  }

  @Test("잘못된 정규식으로 바꾸면 강조도 바로 앞 결과 그대로다")
  func invalidRegexKeepsHighlights() async {
    let opened = await self.opened(["tick 1", "other"])
    let model = opened.model
    let id = self.firstCondition(model)
    model.conditionTextChanged(id, "tick", in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    let before = model.window(for: Support.target).visibleLines
    model.conditionKindChanged(id, .regex, in: Support.target)
    model.conditionTextChanged(id, "(", in: Support.target)
    await Support.settle()
    #expect(model.window(for: Support.target).visibleLines == before)
    #expect(before.first?.highlights == [LogHighlight(location: 0, length: 4)])
  }
}

@MainActor
struct DeviceLogModelPauseTests {
  typealias Support = DeviceLogTestSupport

  @Test("일시정지 중에는 목록이 멈추고 새 줄 수만 늘며, 계속하면 따라잡는다")
  func pauseAndResume() async {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["a"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 1)
    model.pauseTapped(in: Support.target)
    #expect(model.window(for: Support.target).isPaused)
    fake.append(["b", "c"], to: session.id)
    await Support.waitUntil { model.window(for: Support.target).newWhilePaused == 2 }
    #expect(model.window(for: Support.target).visibleCount == 1)
    #expect(model.window(for: Support.target).totalCount == 3)
    model.pauseTapped(in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 3 }
    #expect(!model.window(for: Support.target).isPaused)
    #expect(model.window(for: Support.target).newWhilePaused == 0)
  }

  @Test("일시정지 중 필터를 바꾸면 멈춘 범위만 다시 거르고, 계속하면 그 뒤를 새 필터로 따라잡는다")
  func filterWhilePaused() async throws {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["tick 1", "other 1"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 2)
    model.pauseTapped(in: Support.target)
    fake.append(["tick 2", "other 2"], to: session.id)
    await Support.waitUntil { model.window(for: Support.target).newWhilePaused == 2 }
    let id = try #require(model.window(for: Support.target).filter.conditions.first).id
    model.conditionTextChanged(id, "tick", in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    await Support.settle()
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["tick 1"])
    #expect(model.window(for: Support.target).visibleLines.first?.highlights == [LogHighlight(location: 0, length: 4)])
    #expect(model.window(for: Support.target).newWhilePaused == 2)
    model.pauseTapped(in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["tick 1", "tick 2"])
  }

  @Test("따라가기는 토글과 사용자 스크롤(맨 아래를 떠남·닿음)로 바뀐다")
  func follow() async {
    let session = Support.summary()
    let (model, _) = Support.fixture([session])
    await Support.openAndWait(model, expecting: session.id, visible: 0)
    #expect(model.window(for: Support.target).isFollowing)
    model.scrolledAwayFromBottom(in: Support.target)
    #expect(!model.window(for: Support.target).isFollowing)
    model.scrolledToBottom(in: Support.target)
    #expect(model.window(for: Support.target).isFollowing)
    model.followChanged(false, in: Support.target)
    #expect(!model.window(for: Support.target).isFollowing)
  }

  @Test("지우면 목록이 비고 새 줄만 쌓이며, 닫았다 열어도 지운 줄은 다시 나오지 않는다")
  func clear() async {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["a", "b"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 2)
    model.clearTapped(in: Support.target)
    #expect(model.window(for: Support.target).visibleCount == 0)
    #expect(model.window(for: Support.target).totalCount == 0)
    fake.append(["c"], to: session.id)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 1 }
    model.windowDisappeared(Support.target)
    await Support.openAndWait(model, expecting: session.id, visible: 1)
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["c"])
  }

  @Test("버퍼가 차서 버린 앞 줄은 목록에서 빠지고 버린 수를 알린다. 지운 줄은 버린 수에 넣지 않는다")
  func droppedLines() async {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["0", "1", "2", "3"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 4)
    #expect(model.window(for: Support.target).discardedNotice == nil)
    fake.setDropped(2, for: session.id)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    let window = model.window(for: Support.target)
    #expect(Support.texts(window.visibleLines) == ["2", "3"])
    #expect(window.discardedNotice == 2)
    // 3번까지 지운 뒤 앞 5줄을 버리면, 지우지 않은 줄 중 버린 것은 4번 하나다.
    model.clearTapped(in: Support.target)
    fake.append(["4", "5"], to: session.id)
    fake.setDropped(5, for: session.id)
    await Support.waitUntil {
      model.window(for: Support.target).discardedNotice == 1 && model.window(for: Support.target).visibleCount == 1
    }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["5"])
  }

  @Test("일시정지 중 버린 줄은 보이는 줄에 남았다가 계속할 때 빠진다")
  func droppedWhilePaused() async {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["0", "1", "2"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 3)
    model.pauseTapped(in: Support.target)
    fake.append(["3"], to: session.id)
    fake.setDropped(2, for: session.id)
    await Support.waitUntil { model.window(for: Support.target).droppedCount == 2 }
    #expect(model.window(for: Support.target).visibleCount == 3)
    model.pauseTapped(in: Support.target)
    await Support.waitUntil { model.window(for: Support.target).visibleCount == 2 }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["2", "3"])
  }
}

@MainActor
struct DeviceLogModelRelaunchTests {
  typealias Support = DeviceLogTestSupport

  private func openedEnded() async -> Support.Opened {
    let session = Support.summary(state: .ended(.appExited))
    let (model, fake) = Support.fixture([session])
    await Support.openAndWait(model, expecting: session.id, visible: 0)
    return Support.Opened(model: model, fake: fake, session: session)
  }

  @Test("다시 실행에 성공하면 같은 기기·앱의 새 세션으로 옮긴다")
  func relaunchSucceeds() async {
    let opened = await self.openedEnded()
    let model = opened.model
    let fake = opened.fake
    let session = opened.session
    await model.relaunchTapped(in: Support.target)
    #expect(fake.calls == [.relaunch(session.id)])
    #expect(model.window(for: Support.target).relaunch == .idle)
    await Support.waitUntil { model.selectedSession(for: Support.target) != nil }
    let selected = model.selectedSession(for: Support.target)
    #expect(selected?.id != session.id)
    #expect(selected?.appID == session.appID)
    #expect(selected?.state == .receiving)
  }

  @Test("받는 중인 세션은 다시 실행하지 않는다")
  func noRelaunchWhileReceiving() async {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    await Support.openAndWait(model, expecting: session.id, visible: 0)
    await model.relaunchTapped(in: Support.target)
    #expect(fake.calls.isEmpty)
  }

  @Test("다시 실행 실패는 케이스마다 다른 안내이고, 다른 세션을 고르면 사라진다")
  func relaunchFailures() async {
    let errors: [AppLogLaunchError] = [
      .developerToolsUnavailable, .deviceNotFound, .deviceNotBooted, .appNotInstalled, .appLaunchFailed, .commandFailed,
      .sessionNotFound,
    ]
    let opened = await self.openedEnded()
    let model = opened.model
    let fake = opened.fake
    let session = opened.session
    for error in errors {
      fake.setRelaunchResult(.failure(error))
      await model.relaunchTapped(in: Support.target)
      #expect(model.window(for: Support.target).relaunch == .failed(error))
      #expect(model.window(for: Support.target).selectedSessionID == session.id)
    }
    #expect(Set(errors.map(DeviceLogText.relaunchFailed)).count == errors.count)
    #expect(DeviceLogText.relaunchFailed(.deviceNotBooted).contains("기기가 꺼져 있어"))
    let other = Support.summary("com.example.other", at: -10, state: .ended(.appExited))
    fake.publish(other)
    await Support.waitUntil { model.sessions.count == 2 }
    model.sessionSelected(other.id, in: Support.target)
    #expect(model.window(for: Support.target).relaunch == .idle)
  }

  @Test("다시 실행 중에는 또 누르지 못하고, 창을 닫았다 열어도 막혀 있다. 닫힌 채 끝나면 줄을 받지 않는다")
  func relaunchWhileRunning() async {
    let opened = await self.openedEnded()
    let model = opened.model
    let fake = opened.fake
    let session = opened.session
    fake.suspendRelaunches()
    let first = Task { await model.relaunchTapped(in: Support.target) }
    // Fake 는 메인 밖에서 호출을 기록한다. 기록까지 기다린다.
    await Support.waitUntil { model.window(for: Support.target).relaunch == .running && fake.calls.count == 1 }
    await model.relaunchTapped(in: Support.target)
    #expect(fake.calls == [.relaunch(session.id)])
    model.windowDisappeared(Support.target)
    model.windowAppeared(Support.target)
    #expect(model.window(for: Support.target).relaunch == .running)
    model.windowDisappeared(Support.target)
    fake.resumeRelaunches()
    await first.value
    let window = model.window(for: Support.target)
    #expect(window.relaunch == .idle)
    #expect(window.selectedSessionID == nil)
    #expect(fake.calls == [.relaunch(session.id)])
  }
}

/// 결과를 기다리는 동안 "없음" 으로 보이지 않게 하는 Model 값 (창 값 규칙은 DeviceLogWindowTests).
@MainActor
struct DeviceLogModelPendingTests {
  typealias Support = DeviceLogTestSupport

  @Test("맞는 줄이 없는 필터로 창을 열어 거르기가 끝나면 안내가 보일 조건이 된다")
  func noMatchNoticeAfterFiltering() async throws {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["tick 1", "tick 2"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 2)
    model.windowDisappeared(Support.target)
    let condition = try #require(model.window(for: Support.target).filter.conditions.first).id
    model.conditionTextChanged(condition, "nothing-matches", in: Support.target)
    model.windowAppeared(Support.target)
    await Support.waitUntil {
      let window = model.window(for: Support.target)
      return window.selectedSessionID == session.id && !window.lines.isEmpty && !window.isAwaitingFullFilter
    }
    let window = model.window(for: Support.target)
    #expect(window.visibleLines.isEmpty)
    #expect(window.showsNoMatchingNotice)
    #expect(!window.hidesLineCounts)
  }

  @Test("세션 목록 첫 알림 전에는 받지 않은 것으로, 알림 뒤에는 세션이 없어도 받은 것으로 본다")
  func receivesSessions() async {
    let (model, _) = Support.fixture([])
    #expect(!model.hasReceivedSessions)
    model.windowAppeared(Support.target)
    #expect(!model.hasReceivedSessions)
    await Support.waitUntil { model.hasReceivedSessions }
    #expect(model.sessions.isEmpty)
  }

  @Test("필터를 연달아 두 번 바꾸면 마지막 필터 결과로만 기다림이 끝난다")
  func consecutiveFilterChanges() async {
    let session = Support.summary()
    let (model, fake) = Support.fixture([session])
    fake.append(["tick 1", "probe 2", "other 3"], to: session.id)
    await Support.openAndWait(model, expecting: session.id, visible: 3)
    let condition = model.window(for: Support.target).filter.conditions.first?.id ?? -1
    model.conditionTextChanged(condition, "tick", in: Support.target)
    model.conditionTextChanged(condition, "probe", in: Support.target)
    #expect(model.window(for: Support.target).isAwaitingFullFilter)
    await Support.waitUntil { !model.window(for: Support.target).isAwaitingFullFilter }
    #expect(Support.texts(model.window(for: Support.target).visibleLines) == ["probe 2"])
  }
}
