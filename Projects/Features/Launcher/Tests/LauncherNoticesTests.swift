import SimulatorInterface
import Testing
@testable import LauncherFeature

struct LauncherNoticesTests {
  private static let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 27.0")

  @Test("쌓을 때 id 가 0 부터 늘어나고, 기기 작업 실패는 같은 값이어도 두 번 쌓인다")
  func enqueueAssignsIncreasingIDs() {
    var notices = LauncherNotices()

    notices.enqueue(.bootFailed(Self.device, .commandFailed))
    notices.enqueue(.bootFailed(Self.device, .commandFailed))

    #expect(notices.items == [
      LauncherNoticeItem(id: 0, notice: .bootFailed(Self.device, .commandFailed)),
      LauncherNoticeItem(id: 1, notice: .bootFailed(Self.device, .commandFailed)),
    ])
  }

  @Test("새로 고침 실패는 같은 원인이 줄에 있으면 쌓이지 않고, 다른 원인은 쌓인다")
  func refreshFailedIsDeduplicated() {
    var notices = LauncherNotices()

    notices.enqueue(.refreshFailed(.developerToolsUnavailable))
    notices.enqueue(.refreshFailed(.developerToolsUnavailable))
    notices.enqueue(.refreshFailed(.deviceNotFound))

    #expect(notices.items == [
      LauncherNoticeItem(id: 0, notice: .refreshFailed(.developerToolsUnavailable)),
      LauncherNoticeItem(id: 1, notice: .refreshFailed(.deviceNotFound)),
    ])
  }

  @Test("같은 원인의 새로 고침 실패도 닫은 뒤에는 새 id 로 쌓인다")
  func refreshFailedAfterDismissGetsNewID() {
    var notices = LauncherNotices()
    notices.enqueue(.refreshFailed(.developerToolsUnavailable))

    notices.dismiss(0)
    notices.enqueue(.refreshFailed(.developerToolsUnavailable))

    #expect(notices.items == [LauncherNoticeItem(id: 1, notice: .refreshFailed(.developerToolsUnavailable))])
  }

  @Test("dismiss 는 같은 id 만 지우고, 없는 id·두 번째 dismiss 는 아무것도 바꾸지 않는다")
  func dismissRemovesOnlyMatchingID() {
    var notices = LauncherNotices()
    notices.enqueue(.bootFailed(Self.device, .commandFailed))
    notices.enqueue(.shutdownFailed(Self.device, .deviceNotFound))

    notices.dismiss(0)
    #expect(notices.items == [LauncherNoticeItem(id: 1, notice: .shutdownFailed(Self.device, .deviceNotFound))])

    notices.dismiss(0)
    notices.dismiss(7)
    #expect(notices.items == [LauncherNoticeItem(id: 1, notice: .shutdownFailed(Self.device, .deviceNotFound))])
  }

  @Test("모두 닫아도 다음 id 는 줄지 않는다")
  func nextIDDoesNotShrink() {
    var notices = LauncherNotices()
    notices.enqueue(.bootFailed(Self.device, .commandFailed))
    notices.enqueue(.bootFailed(Self.device, .commandFailed))
    notices.dismiss(0)
    notices.dismiss(1)

    notices.enqueue(.bootFailed(Self.device, .commandFailed))

    #expect(notices.items.map(\.id) == [2])
  }
}
