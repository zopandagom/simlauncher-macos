import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import DownloadInterface
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 툴바 "선택한 기기에 앱 설치" 의 "URL 에서…"·"카탈로그에서…": 여러 대상으로 시트를 열고, 제목·대상 줄을 보이고, 대상 모두를
/// 담아 요청한다.
@MainActor
struct AndroidDownloadInstallModelBatchTests {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
  /// 꺼진 폰과 켜진 태블릿 (목록 순서).
  static let devices: [AndroidVirtualDevice] = [.phoneSample, tablet]
  static let targets = devices.map(AndroidTargetDevice.init)

  @Test("대상 중 켜진·쓸 수 있는 기기가 없으면 두 시트 모두 열지 않는다")
  func noInstallableTarget() async {
    let model = AndroidDownloadInstallModelTests.model()
    model.urlMenuTapped([.phoneSample, .unsupportedNameSample])
    await model.catalogMenuTapped([.phoneSample, .unsupportedNameSample])
    model.urlMenuTapped([])
    #expect(model.urlDraft == nil)
    #expect(model.catalogDraft == nil)
  }

  @Test("하나라도 설치할 수 있으면 꺼진 기기를 포함한 대상 모두로 URL 시트를 열고, 요청에 대상 모두를 담는다")
  func urlSheetForTargets() async throws {
    let (model, requests) = AndroidDownloadInstallModelTests.requestsSetup()
    model.urlMenuTapped(Self.devices)
    #expect(model.urlDraft?.targets == Self.targets)
    model.urlTextChanged("https://builds.example.com/app.apk")
    await model.urlInstallTapped()
    #expect(try requests.items == [AndroidDownloadInstallRequest(
      targets: Self.targets,
      url: #require(DownloadURL("https://builds.example.com/app.apk")),
      origin: .enteredURL
    )])
  }

  @Test("카탈로그 시트도 대상 모두로 열고, 고른 버전의 요청에 대상 모두를 담는다")
  func catalogSheetForTargets() async throws {
    let (model, requests) = AndroidDownloadInstallModelTests.requestsSetup(
      urls: [AndroidCatalogData.v2Raw],
      download: AndroidCatalogData.fake()
    )
    await model.catalogMenuTapped(Self.devices)
    #expect(model.catalogDraft?.targets == Self.targets)
    let sourceID = try #require(model.catalogDraft?.sources.first?.id)
    model.catalogAppSelected(AndroidCatalogAppKey(sourceID: sourceID, appID: AndroidCatalogData.sampleID))
    await model.catalogInstallTapped()
    #expect(requests.items == [AndroidDownloadInstallRequest(
      targets: Self.targets,
      url: AndroidCatalogData.newestURL,
      origin: .catalog
    )])
  }

  @Test("제목은 1대면 행 메뉴와 같고 여러 대면 대수, 대상 줄은 여러 대일 때만 라벨을 이어 보인다")
  func titlesAndTargetsLine() {
    let one = [AndroidTargetDevice(Self.tablet)]
    let two = [AndroidTargetDevice(Self.tablet), AndroidTargetDevice(Self.second)]
    let label = AndroidDeviceLabel(Self.tablet)
    #expect(AndroidDevicesText.installURLSheetTitle(for: one) == AndroidDevicesText.installURLSheetTitle(for: label))
    #expect(AndroidDevicesText.catalogSheetTitle(for: one) == AndroidDevicesText.catalogSheetTitle(for: label))
    #expect(AndroidDevicesText.batchTargetsLine(one) == nil)
    #expect(AndroidDevicesText.installURLSheetTitle(for: two) == "기기 2대에 URL 에서 앱 설치")
    #expect(AndroidDevicesText.catalogSheetTitle(for: two) == "기기 2대에 카탈로그에서 앱 설치")
    #expect(AndroidDevicesText.batchTargetsLine(two) == "대상: “Pixel Tablet” (API 37.0), “두 번째 폰” (API 37.0)")
  }
}
