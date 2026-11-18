import AppLogInterface
import AppLogTesting
import Core
import Foundation
import Testing
@testable import DeviceLogFeature

/// 고른 세션의 줄 구독이 스스로 끝날 때 (`DeviceLogModel.linesEnded`). `DeviceLogModelTests.swift` 의 길이 상한 때문에 따로 둔다.
extension DeviceLogModelRelaunchTests {
  @Test("다시 실행 결과 세션이 어떤 알림에도 나오기 전에 정리되면 대상의 가장 늦은 세션으로 돌아온다")
  func relaunchedSessionPrunedBeforeNotice() async {
    let session = Support.summary(state: .ended(.appExited))
    let (model, fake) = Support.fixture([session])
    await Support.openAndWait(model, expecting: session.id, visible: 0)
    fake.setRelaunchSkipsPublish(true)
    await model.relaunchTapped(in: Support.target)
    // 결과 id 를 고른 직후에는 선택이 그 id 다. 줄 구독이 곧바로 끝나 가장 늦은 세션(다시 실행한 세션)으로 돌아와야 한다.
    await Support.waitUntil {
      model.window(for: Support.target).selectedSessionID == session.id && fake
        .activeLineSubscriptions(of: session.id) == 1
    }
    #expect(model.window(for: Support.target).relaunch == .idle)
    #expect(fake.calls == [.relaunch(session.id)])
    await Support.settle()
    #expect(model.window(for: Support.target).selectedSessionID == session.id)
    #expect(fake.activeLineSubscriptions(of: session.id) == 1)
  }

  @Test("창을 닫은 채 끝난 다시 실행은 구독을 만들지 않고, 다시 열면 가장 늦은 세션을 고른다")
  func relaunchedSessionPrunedAfterClose() async {
    let session = Support.summary(state: .ended(.appExited))
    let (model, fake) = Support.fixture([session])
    await Support.openAndWait(model, expecting: session.id, visible: 0)
    fake.setRelaunchSkipsPublish(true)
    fake.suspendRelaunches()
    let relaunch = Task { await model.relaunchTapped(in: Support.target) }
    await Support.waitUntil { model.window(for: Support.target).relaunch == .running && fake.calls.count == 1 }
    model.windowDisappeared(Support.target)
    fake.resumeRelaunches()
    await relaunch.value
    await Support.settle()
    #expect(model.window(for: Support.target).selectedSessionID == nil)
    #expect(fake.activeLineSubscriptions(of: session.id) == 0)
    await Support.openAndWait(model, expecting: session.id, visible: 0)
    await Support.waitUntil { fake.activeLineSubscriptions(of: session.id) == 1 }
  }

  @Test("목록에 있던 고른 세션이 정리되면 선택은 가장 늦은 세션으로 한 번만 옮겨지고 구독은 하나다")
  func selectedSessionRemovedMovesOnce() async {
    let latest = Support.summary(at: 10, state: .ended(.appExited))
    let earlier = Support.summary("com.example.other", at: 0, state: .ended(.appExited))
    let (model, fake) = Support.fixture([earlier, latest])
    await Support.openAndWait(model, expecting: latest.id, visible: 0)
    model.sessionSelected(earlier.id, in: Support.target)
    await Support.waitUntil { fake.activeLineSubscriptions(of: earlier.id) == 1 }
    // 정리 알림과 줄 구독 끝이 함께 온다. 어느 쪽이 먼저 돌아도 (구독 끝이 먼저면 아직 목록에 있어 알림에 맡긴다) 결과는 같다.
    fake.remove(earlier.id)
    await Support.waitUntil {
      model.window(for: Support.target).selectedSessionID == latest.id && fake
        .activeLineSubscriptions(of: latest.id) == 1
    }
    await Support.settle()
    #expect(model.window(for: Support.target).selectedSessionID == latest.id)
    #expect(fake.activeLineSubscriptions(of: latest.id) == 1)
    #expect(fake.activeLineSubscriptions(of: earlier.id) == 0)
  }
}
