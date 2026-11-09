import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import AndroidPackageTesting
import AppLogTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 켜진 기기 행의 URL·카탈로그에서 설치의 실패 뒤 정리: 판정 거절·기기 값·설치 명령 실패·실행 실패.
@MainActor
extension AndroidDevicesDownloadTests {
  @Test("판정 거절은 받은 파일을 지운 뒤 알리고 다시 읽지 않는다")
  func rejectedRemovesFile() async {
    let setup = await Self.loadedFixture()
    setup.package.setResult(.success(.sample(minSDK: .level(99))))
    await setup.model.downloadInstallRequested(Self.request())
    #expect(Self.notices(setup.model).count == 1)
    guard case .installFailed(_, .rejected) = Self.notices(setup.model).first else {
      Issue.record("판정 거절 알림이 아니다: \(Self.notices(setup.model))")
      return
    }
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.appCalls(setup.fake) == [.deviceTraits(Self.tablet.id)])
    // 대체 예고는 판정을 통과한 뒤에만 하므로 되돌릴 것도 없다.
    #expect(setup.appLog.calls.isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("기기 값 읽기·설치 명령 실패는 받은 파일을 한 번 지우고 알린 뒤 다시 읽는다")
  func emulatorFailureRemovesFileAndReloads() async {
    let traits = await Self.loadedFixture { $0.setDeviceTraits(.failure(.deviceNotBooted)) }
    await traits.model.downloadInstallRequested(Self.request())
    #expect(Self.notices(traits.model) == [.installFailed(Self.label, .emulator(.deviceNotBooted))])
    #expect(Self.removals(traits.download) == [Self.file])
    #expect(Self.fetchCount(traits.fake) == 2)

    let install = await Self.loadedFixture { $0.setInstallError(.installFailed(.updateIncompatible)) }
    await install.model.downloadInstallRequested(Self.request())
    #expect(Self.notices(install.model) == [
      .installFailed(Self.label, .emulator(.installFailed(.updateIncompatible))),
    ])
    #expect(Self.removals(install.download) == [Self.file])
    #expect(Self.appCalls(install.fake).count == 2)
    #expect(install.appLog.calls == [
      .androidReplacementWillStart(Self.info.packageName, Self.tablet.id),
      .androidReplacementCancelled(Self.info.packageName, Self.tablet.id),
    ])
    #expect(Self.fetchCount(install.fake) == 2)
  }

  @Test("실행 실패는 설치 후 실행 실패로 알리고, 받은 파일은 이미 지웠다")
  func launchFailure() async {
    let setup = await Self.loadedFixture()
    setup.launchErrors.set(.noLauncherActivity)
    await setup.model.downloadInstallRequested(Self.request(origin: .catalog))
    #expect(Self.notices(setup.model) == [
      .installedButNotLaunched(Self.label, .launchFailed(.noLauncherActivity)),
    ])
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.fetchCount(setup.fake) == 2)
  }
}
