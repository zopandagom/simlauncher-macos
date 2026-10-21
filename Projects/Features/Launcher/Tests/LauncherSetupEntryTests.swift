import AppBundleTesting
import Core
import DownloadTesting
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// Setup 진입: 툴바 "개발 환경"·빈 화면과 안내 줄의 iOS 설치·목록 읽기 실패 화면의 "개발 환경 열기" 버튼이 모두 같은 이벤트
/// (`setupButtonTapped()`)로 App 이 주입한 클로저를 불러 Setup 화면을 다시 연다.
@MainActor
struct LauncherSetupEntryTests: LauncherModelTesting {
  @Test("setupButtonTapped 는 목록을 읽는 중에도 주입한 클로저를 한 번 부르고, 목록 상태를 바꾸지 않는다")
  func setupButtonCallsInjectedClosureWhileLoading() async {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.suspendFetches()
    var requestCount = 0
    let model = LauncherModel(
      simulator: fake,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      setupRequested: { requestCount += 1 }
    )
    let appear = Task { await model.onAppear() }
    await Self.waitUntil { fake.calls.count == 1 }
    #expect(model.listState == .loading)

    model.setupButtonTapped()
    #expect(requestCount == 1)
    #expect(model.listState == .loading)
    #expect(model.isRefreshing)

    fake.resumeFetches()
    await appear.value
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(requestCount == 1)
    #expect(fake.calls == [.fetchInventory])
  }

  @Test("목록을 읽은 뒤 누를 때마다 클로저를 한 번씩 부른다")
  func setupButtonCallsClosureEachTimeAfterLoading() async {
    var requestCount = 0
    let fake = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(
      simulator: fake,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      setupRequested: { requestCount += 1 }
    )
    await model.onAppear()

    model.setupButtonTapped()
    model.setupButtonTapped()
    #expect(requestCount == 2)
    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(fake.calls == [.fetchInventory])
  }

  @Test("클로저 없이 만든 Model 에서 setupButtonTapped 를 불러도 아무 일 없다")
  func setupButtonWithoutClosureDoesNothing() async {
    let (model, fake) = await Self.loadedModel()

    model.setupButtonTapped()

    #expect(model.listState == .loaded(DeviceList(inventory: .sample)))
    #expect(model.notices.isEmpty)
    #expect(fake.calls == [.fetchInventory])
  }
}
