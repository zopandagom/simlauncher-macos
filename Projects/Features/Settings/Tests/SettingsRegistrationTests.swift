import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesInterface
import PreferencesTesting
import Testing
@testable import SettingsFeature

@MainActor
struct SettingsRegistrationTests: SettingsModelTesting {
  static let first = "https://builds.example.com/ios/catalog.json"
  static let typed = "  https://cdn.example.org/팀/catalog.json "
  static let stored = "https://cdn.example.org/%ED%8C%80/catalog.json"

  @Test("성공하면 상한을 두고 한 번 받아 확인하고, 저장 문자열을 끝에 붙이고, 글자를 비우고, 앱 수를 알린다")
  func success() async {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let download = Self.catalogFake()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)

    await model.addButtonTapped()

    #expect(download.calls == [.fetchData(Self.url(Self.typed).url, maxBytes: BuildCatalog.maxByteCount)])
    #expect(preferences.calls.last == .addCatalogURL(Self.stored))
    #expect(model.setting == CatalogURLSetting(urls: [Self.first, Self.stored], isLocked: false))
    #expect(model.draftText.isEmpty)
    #expect(model.result == .added(raw: Self.stored, appCount: 2))
    #expect(model.checkingURL == nil)
  }

  @Test(
    "받기 실패는 그 이유를 결과 줄에 두고, 글자를 남기고, 저장하지 않는다",
    arguments: [
      DownloadError.insecureRedirect, .httpStatus(401), .httpStatus(404), .httpStatus(500), .offline, .hostNotFound,
      .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed, .insufficientDiskSpace, .tooLarge,
      .storageUnavailable, .failed,
    ]
  )
  func downloadFailure(error: DownloadError) async {
    let preferences = PreferencesClientFake()
    let download = DownloadClientFake()
    download.setFetchResult(.failure(error))
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)

    await model.addButtonTapped()

    #expect(model.result == .failed(.download(error)))
    #expect(model.draftText == Self.typed)
    #expect(model.checkingURL == nil)
    #expect(Self.addCount(preferences) == 0)
    #expect(model.setting == .empty)
  }

  @Test(
    "형식 문제는 그 문제를 결과 줄에 두고, 글자를 남기고, 저장하지 않는다",
    arguments: [
      (CatalogData.loginHTML, BuildCatalogProblem.notJSONObject),
      (CatalogData.newerSchema, .unsupportedSchemaVersion(2)),
      (
        CatalogData.missingCreatedAt,
        .missingField(
          .createdAt,
          position: BuildCatalogProblem.Position(appIndex: 1, appID: "app-b", versionIndex: 0, versionID: "v1")
        )
      ),
    ]
  )
  func catalogProblem(data: Data, problem: BuildCatalogProblem) async {
    let preferences = PreferencesClientFake()
    let download = DownloadClientFake()
    download.setFetchResult(.success(data))
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)

    await model.addButtonTapped()

    #expect(model.result == .failed(.catalog(problem)))
    #expect(model.draftText == Self.typed)
    #expect(model.checkingURL == nil)
    #expect(Self.addCount(preferences) == 0)
  }

  @Test("취소를 누르지 않았는데 받기가 cancelled 로 끝나도 확인 중에 갇히지 않고, 결과 줄 없이 글자를 남긴다")
  func cancelledWithoutCancel() async {
    let preferences = PreferencesClientFake()
    let download = DownloadClientFake()
    download.setFetchResult(.failure(.cancelled))
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)

    await model.addButtonTapped()

    #expect(model.checkingURL == nil)
    #expect(model.result == nil)
    #expect(model.draftText == Self.typed)
    #expect(model.canAdd)
    #expect(Self.addCount(preferences) == 0)
  }

  @Test("확인 중 바깥에서 잠기면 결과 줄 없이 다시 읽어 잠금 표시로 바뀐다")
  func outsideLockDuringCheck() async {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let download = Self.catalogFake()
    download.suspendFetches()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)
    let add = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.suspendedFetchCount == 1 }

    preferences.setStored(urls: [Self.first], isLocked: true)
    download.resumeFetches()
    await Self.waitUntil { add.isFinished }

    #expect(model.result == nil)
    #expect(model.setting == CatalogURLSetting(urls: [Self.first], isLocked: true))
    #expect(model.checkingURL == nil)
    #expect(!model.canEdit)
    #expect(preferences.stored.urls == [Self.first])
  }

  @Test("확인 중 바깥에서 같은 카탈로그가 들어오면 결과 줄 없이 다시 읽고, 남긴 글자에 중복 안내가 보인다")
  func outsideDuplicateDuringCheck() async {
    let preferences = PreferencesClientFake(urls: [Self.first])
    let download = Self.catalogFake()
    download.suspendFetches()
    let model = Self.openedModel(preferences: preferences, download: download)
    model.catalogURLTextChanged(Self.typed)
    let add = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.suspendedFetchCount == 1 }

    preferences.setStored(urls: [Self.first, "HTTPS://CDN.EXAMPLE.ORG/%ed%8c%80/catalog.json"], isLocked: false)
    download.resumeFetches()
    await Self.waitUntil { add.isFinished }

    #expect(model.result == nil)
    #expect(model.setting.urls == [Self.first, "HTTPS://CDN.EXAMPLE.ORG/%ed%8c%80/catalog.json"])
    #expect(model.draftText == Self.typed)
    #expect(model.draftProblem == .duplicate)
    #expect(model.checkingURL == nil)
  }

  @Test("확인 중에는 확인 중인 주소를 보이고 결과 줄을 지운다")
  func checkingState() async {
    let download = Self.catalogFake()
    let model = Self.openedModel(download: download)
    model.catalogURLTextChanged("http://bad.example/c.json")
    model.catalogURLTextChanged(Self.typed)
    download.setFetchResult(.failure(.offline))
    await model.addButtonTapped()
    #expect(model.result != nil)
    download.setFetchResult(.success(CatalogData.twoApps))
    download.suspendFetches()

    let add = Self.start { await model.addButtonTapped() }
    await Self.waitUntil { download.suspendedFetchCount == 1 }

    #expect(model.checkingURL == Self.url(Self.typed))
    #expect(model.result == nil)
    #expect(!model.canAdd)
    download.resumeFetches()
    await Self.waitUntil { add.isFinished }
    #expect(model.checkingURL == nil)
  }
}
