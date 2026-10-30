import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import Core
import DownloadInterface
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// URL·카탈로그에서 설치 문구의 분기 (키·값은 `AndroidDevicesResourcesTests`·`LauncherTextSyncTests` 가 본다).
struct AndroidDevicesDownloadTextTests {
  static let label = AndroidDeviceLabel(.phoneSample)

  static let downloadErrors: [DownloadError] = [
    .insecureRedirect, .httpStatus(401), .httpStatus(403), .httpStatus(404), .httpStatus(407), .httpStatus(410),
    .httpStatus(418), .httpStatus(503), .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost,
    .secureConnectionFailed, .insufficientDiskSpace, .storageUnavailable, .tooLarge, .failed, .cancelled,
  ]

  @Test("시트 제목은 기기 라벨을 넣는다")
  func sheetTitles() {
    #expect(AndroidDevicesText.installURLSheetTitle(for: Self.label) == "“테스트 폰” (API 37.0) 기기에 URL 에서 앱 설치")
    #expect(AndroidDevicesText.catalogSheetTitle(for: Self.label) == "“테스트 폰” (API 37.0) 기기에 카탈로그에서 앱 설치")
  }

  @Test("받는 중 글자: 진행이 없으면 글자만, 전체 크기를 모르거나 0 이면 받은 크기만, 알면 받은 크기 / 전체 크기")
  func downloadingLabel() {
    let received = Int64(2048).formatted(.byteCount(style: .file))
    let total = Int64(4096).formatted(.byteCount(style: .file))
    #expect(AndroidDevicesText.downloadingLabel(nil) == "받는 중…")
    #expect(AndroidDevicesText.downloadingLabel(DownloadProgress(receivedBytes: 2048, expectedBytes: nil))
      == "받는 중… \(received)")
    #expect(AndroidDevicesText.downloadingLabel(DownloadProgress(receivedBytes: 2048, expectedBytes: 0))
      == "받는 중… \(received)")
    #expect(AndroidDevicesText.downloadingLabel(DownloadProgress(receivedBytes: 2048, expectedBytes: 4096))
      == "받는 중… \(received) / \(total)")
  }

  @Test("빈 주소는 안내 없이 버튼만 비활성이고, 나머지 입력 문제는 서로 다른 안내다")
  func urlProblems() {
    #expect(AndroidDevicesText.downloadURLProblem(.empty) == nil)
    let texts = [DownloadURLProblem.malformed, .notHTTPS, .missingHost, .hasCredentials]
      .compactMap { AndroidDevicesText.downloadURLProblem($0) }
    #expect(texts.count == 4)
    #expect(Set(texts).count == 4)
  }

  @Test("받기 실패 알림: 출처가 문구를 고른다 (입력한 주소 = URL 문구, 카탈로그 = 카탈로그 버전 문구)")
  func downloadFailureByOrigin() {
    for error in Self.downloadErrors {
      #expect(
        AndroidDevicesText.message(for: AndroidAppInstallFailure.download(error, origin: .enteredURL))
          == AndroidDevicesText.urlDownloadMessage(for: error),
        "\(error)"
      )
      #expect(
        AndroidDevicesText.message(for: AndroidAppInstallFailure.download(error, origin: .catalog))
          == AndroidDevicesText.catalogInstallDownloadMessage(for: error),
        "\(error)"
      )
    }
    // 주소 쪽 원인은 카탈로그를 만든 사람에게 알리게 한다.
    let addressSide: [DownloadError] = [
      .insecureRedirect, .httpStatus(401), .httpStatus(404), .httpStatus(418), .hostNotFound, .cannotConnect,
      .secureConnectionFailed, .failed,
    ]
    for error in addressSide {
      let catalog = AndroidDevicesText.catalogInstallDownloadMessage(for: error)
      #expect(catalog != AndroidDevicesText.urlDownloadMessage(for: error), "\(error)")
      #expect(catalog.contains("카탈로그를 만든 사람"), "\(error)")
    }
    // 빌드 주소와 관계없는 원인(네트워크·저장)은 같은 문구다.
    let networkSide: [DownloadError] = [
      .offline, .httpStatus(407), .httpStatus(503), .timedOut, .connectionLost, .insufficientDiskSpace,
      .storageUnavailable,
    ]
    for error in networkSide {
      #expect(
        AndroidDevicesText.catalogInstallDownloadMessage(for: error)
          == AndroidDevicesText.urlDownloadMessage(for: error),
        "\(error)"
      )
    }
    // 없는 빌드·접근 거부는 다른 버전 고르기를 안내한다.
    for code in [401, 403, 404, 410] {
      #expect(AndroidDevicesText.catalogInstallDownloadMessage(for: .httpStatus(code)).contains("다른 버전을 고르거나"))
    }
  }

  @Test("받은 apk 실패: 웹 페이지는 읽기 실패일 때만 따로, 받은 파일 문맥이 없는 실패는 고른 파일과 같은 문구다")
  func downloadedPackageMessages() {
    for origin in [AndroidDownloadOrigin.enteredURL, .catalog] {
      let web = AndroidDevicesText.downloadedPackageMessage(for: .unreadable, isWebPage: true, origin: origin)
      let unreadable = AndroidDevicesText.downloadedPackageMessage(for: .unreadable, isWebPage: false, origin: origin)
      #expect(web != unreadable)
      #expect(web.hasPrefix("apk 파일 대신 웹 페이지를 받았습니다."))
      // 고른 파일의 읽기 실패 문구가 아니다 (받은 파일 문맥).
      #expect(unreadable != AndroidDevicesText.message(for: AndroidPackageError.unreadable))
      // 웹 페이지 여부는 읽기 실패에서만 본다.
      #expect(AndroidDevicesText.downloadedPackageMessage(for: .appBundle, isWebPage: true, origin: origin)
        == AndroidDevicesText.downloadedPackageMessage(for: .appBundle, isWebPage: false, origin: origin))
      #expect(AndroidDevicesText.downloadedPackageMessage(for: .appBundle, isWebPage: false, origin: origin)
        != AndroidDevicesText.message(for: AndroidPackageError.appBundle))
      for error in [AndroidPackageError.unsafeEntry, .inspectionUnavailable] {
        #expect(
          AndroidDevicesText.downloadedPackageMessage(for: error, isWebPage: false, origin: origin)
            == AndroidDevicesText.message(for: error),
          "\(error)"
        )
      }
      // 받은 파일은 늘 로컬 download.apk 라 나오지 않는 실패는 한 문구다.
      for error in [AndroidPackageError.notLocalFile, .fileNotFound, .notAPK, .splitPackage] {
        #expect(
          AndroidDevicesText.downloadedPackageMessage(for: error, isWebPage: false, origin: origin)
            == "받은 파일을 읽지 못했습니다. 다시 시도하세요.",
          "\(error)"
        )
      }
    }
    // 서명 없음: 입력한 주소는 고른 파일과 같은 문구, 카탈로그는 만든 사람에게 알린다.
    #expect(AndroidDevicesText.downloadedPackageMessage(for: .unsigned, isWebPage: false, origin: .enteredURL)
      == AndroidDevicesText.message(for: AndroidPackageError.unsigned))
    let catalogUnsigned = AndroidDevicesText.downloadedPackageMessage(
      for: .unsigned,
      isWebPage: false,
      origin: .catalog
    )
    #expect(catalogUnsigned != AndroidDevicesText.message(for: AndroidPackageError.unsigned))
    #expect(catalogUnsigned.contains("카탈로그를 만든 사람"))
    // 알림 본문은 같은 함수를 거친다.
    #expect(AndroidDevicesText.message(for: AndroidAppInstallFailure.downloadedPackage(
      .appBundle,
      isWebPage: false,
      origin: .catalog
    )) == AndroidDevicesText.downloadedPackageMessage(for: .appBundle, isWebPage: false, origin: .catalog))
  }

  @Test("받기·받은 파일 실패 알림의 제목은 다른 설치 실패와 같다")
  func downloadNoticeTitle() {
    let title = AndroidDevicesText.title(for: .installFailed(Self.label, .multipleItems))
    #expect(AndroidDevicesText.title(for: .installFailed(Self.label, .download(.offline, origin: .catalog))) == title)
    #expect(AndroidDevicesText.title(for: .installFailed(
      Self.label,
      .downloadedPackage(.unreadable, isWebPage: true, origin: .enteredURL)
    )) == title)
    #expect(title == "“테스트 폰” (API 37.0) 기기에 앱을 설치하지 못했습니다")
  }

  @Test("Android 앱이 없는 구역의 이유는 셋이 서로 다르고, 앱이 전혀 없는 문구는 iOS 시트와 같다")
  func emptyReasons() {
    let reasons = [AndroidCatalogEmptyReason.noApps, .noAndroidApps, .schemaVersion1]
      .map { AndroidDevicesText.catalogEmptyReason($0) }
    #expect(Set(reasons).count == 3)
    #expect(AndroidDevicesText.catalogEmptyReason(.noApps) == "이 카탈로그에는 앱이 없습니다.")
    #expect(AndroidDevicesText.catalogEmptyReason(.schemaVersion1).contains("schemaVersion 2"))
  }

  @Test("구역 상태 줄: 실패는 카탈로그 읽기 실패 문구, 쓸 수 없는 주소는 주소 이유 문구 (잠김을 그대로 넘긴다)")
  func sourceNotes() {
    for isLocked in [false, true] {
      let failure = AndroidCatalogLoadFailure.download(.httpStatus(404))
      #expect(AndroidDevicesText.catalogSourceNote(.failed(failure, isLocked: isLocked))
        == AndroidDevicesText.catalogLoadMessage(for: failure, isLocked: isLocked))
      #expect(AndroidDevicesText.catalogSourceNote(.invalid(.notHTTPS, isLocked: isLocked))
        == AndroidDevicesText.invalidCatalogURL(.notHTTPS, isLocked: isLocked))
    }
    #expect(AndroidDevicesText.catalogSourceNote(.failed(.download(.httpStatus(404)), isLocked: true))
      != AndroidDevicesText.catalogSourceNote(.failed(.download(.httpStatus(404)), isLocked: false)))
  }

  @Test("카탈로그 형식 문제: platform 문제는 위치와 함께 만든 사람에게, 2보다 큰 schemaVersion 은 업데이트 안내만, 없는 규격은 지원 범위")
  func catalogProblems() {
    let position = BuildCatalogProblem.Position(
      appIndex: 1,
      appID: "com.example.app",
      versionIndex: nil,
      versionID: nil
    )
    let platform = AndroidDevicesText.catalogLoadMessage(
      for: .catalog(.unsupportedPlatform(position: position)),
      isLocked: false
    )
    #expect(platform == """
    카탈로그 형식이 맞지 않아 읽지 않았습니다.
    2번째 앱(id: com.example.app)의 platform 이 ios 나 android 가 아닙니다 (소문자로 씁니다).
    카탈로그를 만든 사람에게 알려 주세요.
    """)
    // 잠긴 목록도 같은 문구다 (주소 확인을 안내하지 않는 문제).
    #expect(AndroidDevicesText.catalogLoadMessage(
      for: .catalog(.unsupportedPlatform(position: position)),
      isLocked: true
    )
      == platform)
    let missing = AndroidDevicesText.catalogLoadMessage(
      for: .catalog(.missingField(.platform, position: position)),
      isLocked: false
    )
    #expect(missing.contains("필수 필드 platform"))

    let newer = AndroidDevicesText.catalogLoadMessage(for: .catalog(.unsupportedSchemaVersion(3)), isLocked: false)
    #expect(newer == """
    카탈로그 형식이 맞지 않아 읽지 않았습니다.
    이 카탈로그는 이 앱보다 새 규격(schemaVersion 3)입니다. SimLauncher 를 업데이트하세요.
    """)
    #expect(AndroidDevicesText.catalogLoadMessage(for: .catalog(.unsupportedSchemaVersion(0)), isLocked: false)
      .contains("schemaVersion 0 은 없는 규격입니다 (지원: 1~2)"))
  }
}
