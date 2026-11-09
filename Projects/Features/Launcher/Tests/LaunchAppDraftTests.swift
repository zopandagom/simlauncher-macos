import Core
import SimulatorTesting
import Testing
@testable import LauncherFeature

struct LaunchAppDraftTests {
  static let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 27.0")

  static func draft(request: Int = 1, booting: Bool = false) -> LaunchAppDraft {
    LaunchAppDraft(deviceID: SampleID.iPhoneOn, device: self.device, request: request, booting: booting)
  }

  @Test("꺼진 기기면 켜는 중, 켜진 기기면 불러오는 중으로 시작하고 실행할 수 없다")
  func startsBootingOrLoading() {
    #expect(Self.draft(booting: true).apps == .booting)
    #expect(Self.draft(booting: false).apps == .loading)
    #expect(!Self.draft().canSubmit)
    #expect(Self.draft().selectedApp == nil)
  }

  @Test("목록에 하나뿐이면 그것을 고르고 실행할 수 있다")
  func singleAppIsSelected() {
    var draft = Self.draft()
    draft.appsLoaded(.success([InstalledAppSamples.alpha]), request: 1)

    #expect(draft.apps == .loaded([InstalledAppSamples.alpha]))
    #expect(draft.selection == InstalledAppSamples.alpha.bundleID)
    #expect(draft.selectedApp == InstalledAppSamples.alpha)
    #expect(draft.canSubmit)
  }

  @Test("둘 이상이면 고르지 않고, 고르면 실행할 수 있으며, 목록에 없는 앱을 고르면 실행할 수 없다")
  func selectionRules() {
    var draft = Self.draft()
    draft.appsLoaded(.success(InstalledAppSamples.two), request: 1)
    #expect(draft.selection == nil)
    #expect(!draft.canSubmit)

    draft.selectionChanged(InstalledAppSamples.beta.bundleID)
    #expect(draft.selectedApp == InstalledAppSamples.beta)
    #expect(draft.canSubmit)

    draft.selectionChanged(AppBundleID("com.example.missing"))
    #expect(draft.selectedApp == nil)
    #expect(!draft.canSubmit)
  }

  @Test("빈 목록이면 실행할 수 없다")
  func emptyListCannotSubmit() {
    var draft = Self.draft()
    draft.appsLoaded(.success([]), request: 1)
    #expect(draft.apps == .loaded([]))
    #expect(!draft.canSubmit)
  }

  @Test("번호가 다른 결과는 무시한다")
  func staleResultIsIgnored() {
    var draft = Self.draft(request: 2)
    draft.appsLoaded(.success([InstalledAppSamples.alpha]), request: 1)
    #expect(draft.apps == .loading)

    let failure = LaunchAppPreparationFailure(.simulator(.commandFailed), stage: .list)
    draft.appsLoaded(.failure(failure), request: 1)
    #expect(draft.apps == .loading)
  }

  @Test("실패는 원인과 단계를 함께 담는다")
  func failureKeepsStage() {
    var draft = Self.draft(booting: true)
    draft.appsLoaded(.failure(LaunchAppPreparationFailure(.simulator(.commandFailed), stage: .boot)), request: 1)
    #expect(draft.apps == .failed(.simulator(.commandFailed), stage: .boot))
    #expect(!draft.canSubmit)
  }

  @Test("다시 불러오면 새 번호로 켜는 중이나 불러오는 중이 되고 고른 앱은 유지하며, 다시 읽은 목록에 없으면 지운다")
  func reloadKeepsSelectionUntilMissing() {
    var draft = Self.draft()
    draft.appsLoaded(.success(InstalledAppSamples.two), request: 1)
    draft.selectionChanged(InstalledAppSamples.beta.bundleID)

    draft.reloadStarted(request: 2, booting: true)
    #expect(draft.request == 2)
    #expect(draft.apps == .booting)
    #expect(draft.selection == InstalledAppSamples.beta.bundleID)

    draft.reloadStarted(request: 3, booting: false)
    #expect(draft.apps == .loading)
    draft.appsLoaded(.success(InstalledAppSamples.two), request: 3)
    #expect(draft.selection == InstalledAppSamples.beta.bundleID)

    draft.reloadStarted(request: 4, booting: false)
    draft.appsLoaded(.success([InstalledAppSamples.alpha, InstalledAppSamples.gamma]), request: 4)
    #expect(draft.selection == nil)
  }

  @Test("켜기가 끝나면 번호가 같고 켜는 중일 때만 불러오는 중으로 바뀐다")
  func loadingStartedOnlyFromBootingWithSameRequest() {
    var draft = Self.draft(request: 1, booting: true)
    draft.loadingStarted(request: 2)
    #expect(draft.apps == .booting)

    draft.loadingStarted(request: 1)
    #expect(draft.apps == .loading)

    draft.appsLoaded(.success([]), request: 1)
    draft.loadingStarted(request: 1)
    #expect(draft.apps == .loaded([]))
  }
}

/// 앱 실행 테스트가 함께 쓰는 설치된 앱. 이름은 ASCII 라 정렬이 로캘과 상관없다.
enum InstalledAppSamples {
  static let alpha = InstalledApp(
    bundleID: AppBundleID("com.example.alpha")!,
    displayName: "Alpha",
    version: "1.0",
    build: "7"
  )
  static let beta = InstalledApp(
    bundleID: AppBundleID("com.example.beta")!,
    displayName: "Beta",
    version: nil,
    build: nil
  )
  static let gamma = InstalledApp(
    bundleID: AppBundleID("com.example.gamma")!,
    displayName: "Gamma",
    version: "2.0",
    build: nil
  )
  static let two = [alpha, beta]
}
