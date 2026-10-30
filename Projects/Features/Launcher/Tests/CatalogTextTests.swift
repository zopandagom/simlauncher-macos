import AppBundleInterface
import Core
import DownloadInterface
import Foundation
import Testing
@testable import LauncherFeature

/// 카탈로그에서 설치 문구: 케이스마다 어느 문구를 고르는지와 여러 줄 본문의 조합. 키가 컴파일된 표에 있는지는
/// `LauncherResourcesTests`, Settings 조각과 같은지는 `CatalogFragmentSyncTests` 가 본다.
struct CatalogTextTests {
  static let downloadErrors: [DownloadError] = [
    .insecureRedirect, .httpStatus(401), .httpStatus(403), .httpStatus(407), .httpStatus(404), .httpStatus(410),
    .httpStatus(503), .httpStatus(400), .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost,
    .secureConnectionFailed, .tooLarge, .insufficientDiskSpace, .storageUnavailable, .failed, .cancelled,
  ]

  static func isKorean(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }
  }

  @Test("카탈로그 받기 실패: 케이스마다 시트 문맥의 문구이고, 407·5xx·오프라인은 URL 설치와 같으며, 나오지 않는 케이스는 일반 문구다")
  func catalogDownloadMessages() {
    for error in Self.downloadErrors {
      let text = LauncherText.catalogLoadMessage(for: .download(error), isLocked: false)
      #expect(Self.isKorean(text), "\(error)")
    }
    #expect(
      LauncherText.catalogLoadMessage(for: .download(.httpStatus(404)), isLocked: false)
        == "서버에 카탈로그 파일이 없습니다 (HTTP 404). 설정(⌘,)에서 주소가 맞는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요."
    )
    #expect(
      LauncherText.catalogLoadMessage(for: .download(.httpStatus(410)), isLocked: false)
        == LauncherText.catalogLoadMessage(for: .download(.httpStatus(404)), isLocked: false).replacingOccurrences(
          of: "404",
          with: "410"
        )
    )
    #expect(
      LauncherText.catalogLoadMessage(for: .download(.httpStatus(403)), isLocked: false)
        == LauncherText.catalogLoadMessage(for: .download(.httpStatus(401)), isLocked: false).replacingOccurrences(
          of: "401",
          with: "403"
        )
    )
    #expect(LauncherText.catalogLoadMessage(for: .download(.httpStatus(403)), isLocked: false)
      .contains("설정(⌘,)에서 주소가 맞는지"))
    for code in [407, 503] {
      #expect(LauncherText.catalogLoadMessage(for: .download(.httpStatus(code)), isLocked: false) == LauncherText
        .httpStatusMessage(code))
    }
    #expect(LauncherText.catalogLoadMessage(for: .download(.offline), isLocked: false) == LauncherText
      .message(for: DownloadError.offline))
    let general = "카탈로그를 받지 못했습니다. 다시 시도하고, 계속되면 설정(⌘,)에서 주소를 확인하세요."
    for error in [DownloadError.failed, .cancelled, .insufficientDiskSpace, .storageUnavailable] {
      #expect(LauncherText.catalogLoadMessage(for: .download(error), isLocked: false) == general, "\(error)")
    }
    // 등록한 주소라 고칠 곳은 설정이다. 받은 크기를 지웠다는 말은 메모리 받기라 쓰지 않는다.
    #expect(LauncherText.catalogLoadMessage(for: .download(.hostNotFound), isLocked: false).contains("설정(⌘,)에서 주소의 철자"))
    #expect(!LauncherText.catalogLoadMessage(for: .download(.connectionLost), isLocked: false).contains("지웠"))
  }

  @Test("형식 문제 본문: 머리 + 내용 + 다음 할 일이 케이스마다 정해진 조합이다")
  func catalogProblemMessages() {
    let header = "카탈로그 형식이 맞지 않아 읽지 않았습니다."
    let checkAddress = "설정(⌘,)에서 주소가 catalog.json 파일을 바로 가리키는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요."
    let report = "카탈로그를 만든 사람에게 알려 주세요."
    func lines(_ problem: BuildCatalogProblem) -> [String] {
      LauncherText.catalogLoadMessage(for: .catalog(problem), isLocked: false).components(separatedBy: "\n")
    }

    #expect(lines(.notJSONObject) == [
      header,
      "받은 파일을 카탈로그(JSON 객체)로 읽지 못했습니다. 로그인 페이지 같은 웹 페이지이거나 다른 파일일 수 있습니다.",
      checkAddress,
    ])
    #expect(lines(.unsupportedSchemaVersion(3)) == [
      header, "이 카탈로그는 이 앱보다 새 규격(schemaVersion 3)입니다. SimLauncher 를 업데이트하세요.",
    ])
    #expect(lines(.unsupportedSchemaVersion(0)) == [header, "카탈로그의 schemaVersion 0 은 없는 규격입니다 (지원: 1~2).", report])
    #expect(lines(.unsupportedSchemaVersion(-1))[1] == "카탈로그의 schemaVersion -1 은 없는 규격입니다 (지원: 1~2).")
    #expect(lines(.missingField(.apps, position: .root)) == [
      header, "카탈로그 최상위에 필수 필드 apps 가 없거나 null 입니다.", checkAddress,
    ])
    #expect(lines(.wrongType(.schemaVersion, position: .root)).last == checkAddress)
    let app = BuildCatalogProblem.Position(appIndex: 1, appID: "app-b", versionIndex: nil, versionID: nil)
    #expect(lines(.missingField(.name, position: app)) == [
      header, "2번째 앱(id: app-b)에 필수 필드 name 가 없거나 null 입니다.", report,
    ])
    let item = BuildCatalogProblem.Position(appIndex: 0, appID: nil, versionIndex: 2, versionID: nil)
    #expect(lines(.wrongType(.versions, position: item))[1] == "1번째 앱의 3번째 버전이 객체가 아닙니다 (versions 배열의 항목은 객체여야 합니다).")
    let version = BuildCatalogProblem.Position(appIndex: 0, appID: "a", versionIndex: 2, versionID: "v")
    #expect(lines(.invalidBuildURL(.hasCredentials, position: version)) == [
      header, "1번째 앱(id: a)의 3번째 버전(id: v)의 buildURL 을 쓸 수 없습니다: 사용자 이름이나 비밀번호가 들어 있습니다.", report,
    ])
    #expect(lines(.unsupportedPlatform(position: app)) == [
      header, "2번째 앱(id: app-b)의 platform 이 ios 나 android 가 아닙니다 (소문자로 씁니다).", report,
    ])
    #expect(lines(.missingField(.platform, position: app))[1] == "2번째 앱(id: app-b)에 필수 필드 platform 가 없거나 null 입니다.")
    #expect(LauncherText.catalogLocation(.root) == "카탈로그 최상위")
  }

  @Test("카탈로그 읽기 실패: 잠김이면 주소를 고치라는 안내만 담당자 안내로 바뀌고, 나머지 문구는 잠김과 관계없이 같다")
  func lockedCatalogLoadMessages() {
    let admin = Self.admin
    let rows = Self.lockedDownloadRows() + Self.lockedProblemRows()
    for (failure, expectedLocked) in rows {
      let unlocked = LauncherText.catalogLoadMessage(for: failure, isLocked: false)
      let locked = LauncherText.catalogLoadMessage(for: failure, isLocked: true)
      #expect(!locked.contains("설정(⌘,)"), "\(failure)")
      if let expectedLocked {
        #expect(unlocked.contains("설정(⌘,)"), "\(failure)")
        #expect(locked.contains(admin), "\(failure)")
        #expect(locked == expectedLocked, "\(failure)")
      } else {
        #expect(locked == unlocked, "\(failure)")
      }
      for isLocked in [false, true] {
        #expect(
          LauncherText.catalogSourceNote(.failed(failure, isLocked: isLocked))
            == LauncherText.catalogLoadMessage(for: failure, isLocked: isLocked),
          "\(failure)"
        )
      }
    }
    for problem in CatalogTextCatalog.urlProblems {
      for isLocked in [false, true] {
        #expect(
          LauncherText.catalogSourceNote(.invalid(problem, isLocked: isLocked))
            == LauncherText.invalidCatalogURL(problem, isLocked: isLocked)
        )
      }
    }
  }

  @Test("카탈로그 버전 설치 실패: 빌드 주소·파일 쪽 원인은 카탈로그 문맥 문구이고, 빌드 주소와 관계없는 원인과 그 밖의 받은 zip 풀기 실패는 URL 설치와 같다")
  func catalogInstallMessages() {
    let missing = LauncherText.message(for: AppInstallFailure.catalogDownload(.httpStatus(404)))
    #expect(missing == "서버에 이 버전의 빌드 파일이 없습니다 (HTTP 404). 지워진 빌드일 수 있습니다. 다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.")
    #expect(missing != LauncherText.message(for: AppInstallFailure.download(.httpStatus(404))))
    #expect(
      LauncherText.message(for: AppInstallFailure.catalogDownloadedNotZip(isWebPage: true))
        != LauncherText.message(for: AppInstallFailure.downloadedNotZip(isWebPage: true))
    )
    #expect(
      LauncherText.message(for: AppInstallFailure.catalogDownloadedZip(.zipWithoutApp))
        != LauncherText.message(for: AppInstallFailure.downloadedZip(.zipWithoutApp))
    )
    let shared: [DownloadError] = [
      .httpStatus(407), .httpStatus(503), .offline, .timedOut, .connectionLost, .insufficientDiskSpace,
      .storageUnavailable,
    ]
    for error in shared {
      #expect(
        LauncherText.message(for: AppInstallFailure.catalogDownload(error))
          == LauncherText.message(for: AppInstallFailure.download(error)),
        "\(error)"
      )
    }
    let general = "빌드 파일을 받지 못했습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요."
    for error in [DownloadError.failed, .tooLarge, .cancelled] {
      #expect(LauncherText.message(for: AppInstallFailure.catalogDownload(error)) == general, "\(error)")
    }
    for error in Self.downloadErrors {
      let text = LauncherText.message(for: AppInstallFailure.catalogDownload(error))
      #expect(Self.isKorean(text), "\(error)")
      // 입력한 주소가 없으므로 주소를 입력·확인하라고 하지 않는다.
      #expect(!text.contains("주소를 입력"), "\(error)")
    }
    let zipShared: [AppBundleError] = [
      .insufficientDiskSpace, .zipUnsafeEntry, .extractionUnavailable, .ipaFile, .notAppBundle, .macOSApp,
      .invalidBundle, .notLocalFile, .fileNotFound,
    ]
    for error in zipShared {
      #expect(
        LauncherText.message(for: AppInstallFailure.catalogDownloadedZip(error))
          == LauncherText.downloadedZipMessage(for: error),
        "\(error)"
      )
    }
    #expect(
      LauncherText.message(for: AppInstallFailure.catalogDownloadedZip(.zipUnreadable))
        == LauncherText.message(for: AppInstallFailure.catalogDownloadedNotZip(isWebPage: false))
    )
    // 카탈로그 출처가 아닌 케이스가 넘어와도 기존 문구를 돌려준다.
    #expect(LauncherText.catalogInstallMessage(for: .multipleItems) == LauncherText.message(for: .multipleItems))
  }

  @Test("시트 문구: 빈 목록·쓸 수 없는 주소는 잠금에 따라 다음 할 일이 다르고, 버전 캡션은 태그·브랜치·빌드·날짜 순서다")
  func sheetTexts() throws {
    #expect(LauncherText.emptyCatalogMessage(isLocked: false).contains("설정(⌘,)"))
    #expect(LauncherText.emptyCatalogMessage(isLocked: true).contains("담당자에게 문의"))
    for problem in CatalogTextCatalog.urlProblems {
      let reason = LauncherText.catalogURLProblemReason(problem)
      #expect(
        LauncherText.invalidCatalogURL(problem, isLocked: false)
          == "쓸 수 없는 주소라 읽지 않았습니다: \(reason). 설정(⌘,)에서 지우고 https 주소로 다시 등록하세요."
      )
      #expect(
        LauncherText.invalidCatalogURL(problem, isLocked: true)
          == "쓸 수 없는 주소라 읽지 않았습니다: \(reason). Mac 을 관리하는 담당자에게 알려 주세요."
      )
    }
    #expect(Set(CatalogTextCatalog.urlProblems.map { LauncherText.catalogURLProblemReason($0) }).count == 5)
    #expect(
      LauncherText.catalogSheetTitle(for: CatalogTextCatalog.device) == "“iPhone 17” (iOS 26.0) 기기에 카탈로그에서 앱 설치"
    )

    let catalog = try CatalogData.catalog(CatalogData.twoApps)
    let versions = try #require(catalog.apps.first?.versions)
    let locale = Locale(identifier: "ko_KR")
    let timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
    // v2: 태그·브랜치·빌드 번호가 모두 있다. 2026-10-21T04:08:49Z 는 서울 오후 1:08.
    let full = LauncherText.versionDetail(versions[0], locale: locale, timeZone: timeZone)
    let date = versions[0].createdAt.formatted(style)
    #expect(full == "태그 v1.1 · 브랜치 main · 빌드 42 · \(date)")
    #expect(date.contains("2026"))
    #expect(date.contains("오후 1:08"))
    // v1: 선택 필드가 없으면 날짜만.
    let bare = LauncherText.versionDetail(versions[1], locale: locale, timeZone: timeZone)
    #expect(bare == versions[1].createdAt.formatted(style))
  }
}

// MARK: - 잠김 표

extension CatalogTextTests {
  static let admin = "Mac 을 관리하는 담당자에게"

  /// 둘째 값: 주소를 고치라는 안내가 있는 분기(잠김 판이 있는 분기)의 잠김 문구. nil 이면 잠김과 관계없이 같은 문구다.
  static func lockedDownloadRows() -> [(CatalogLoadFailure, String?)] {
    let admin = Self.admin
    func download(_ error: DownloadError, _ locked: String?) -> (CatalogLoadFailure, String?) {
      (.download(error), locked)
    }
    var rows: [(CatalogLoadFailure, String?)] = [
      download(.insecureRedirect, nil), download(.offline, nil), download(.timedOut, nil),
      download(.connectionLost, nil), download(.httpStatus(407), nil), download(.httpStatus(503), nil),
    ]
    for code in [401, 403] {
      rows.append(download(.httpStatus(code), [
        "서버가 접근을 거부해 받지 못했습니다 (HTTP \(code)). \(admin) 주소가 맞는지 확인해 달라고 하고, ",
        "맞다면 로그인 없이 받을 수 있는 주소인지 카탈로그를 만든 사람에게 확인하세요.",
      ].joined()))
    }
    for code in [404, 410] {
      rows.append(download(.httpStatus(code), [
        "서버에 카탈로그 파일이 없습니다 (HTTP \(code)). \(admin) 주소가 맞는지 확인해 달라고 하고, ",
        "맞다면 카탈로그를 만든 사람에게 알려 주세요.",
      ].joined()))
    }
    rows.append(download(.httpStatus(400), [
      "서버가 카탈로그를 주지 않았습니다 (HTTP 400). 다시 시도하고, 계속되면 ",
      "\(admin) 주소를 확인해 달라고 하세요.",
    ].joined()))
    rows.append(download(.hostNotFound, [
      "서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, ",
      "아니면 \(admin) 주소의 철자를 확인해 달라고 하세요.",
    ].joined()))
    rows.append(download(.cannotConnect, [
      "서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, ",
      "아니면 \(admin) 주소를 확인해 달라고 하세요.",
    ].joined()))
    rows.append(download(.secureConnectionFailed, [
      "서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). ",
      "\(admin) 주소가 맞는지 확인해 달라고 하고, 계속되면 서버 관리자에게 알려 주세요.",
    ].joined()))
    rows.append(download(.tooLarge, [
      "파일이 5 MiB 를 넘어 받지 않았습니다. \(admin) 주소가 catalog.json 파일을 바로 가리키는지 확인해 달라고 하고, ",
      "맞다면 오래된 버전 항목을 지워 달라고 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()))
    let general = "카탈로그를 받지 못했습니다. 다시 시도하고, 계속되면 \(admin) 주소를 확인해 달라고 하세요."
    for error in [DownloadError.insufficientDiskSpace, .storageUnavailable, .failed, .cancelled] {
      rows.append(download(error, general))
    }
    return rows
  }

  /// 형식 문제: JSON 객체가 아님·최상위 필드 문제만 주소 확인 안내(잠김 판)가 있다.
  static func lockedProblemRows() -> [(CatalogLoadFailure, String?)] {
    let header = "카탈로그 형식이 맞지 않아 읽지 않았습니다."
    let checkWithAdmin = [
      "Mac 을 관리하는 담당자에게 주소가 catalog.json 파일을 바로 가리키는지 확인해 달라고 하고, ",
      "맞다면 카탈로그를 만든 사람에게 알려 주세요.",
    ].joined()
    let addressProblems: [BuildCatalogProblem] = [
      .notJSONObject, .missingField(.apps, position: .root), .wrongType(.schemaVersion, position: .root),
    ]
    var rows = addressProblems.map { (problem: BuildCatalogProblem) -> (CatalogLoadFailure, String?) in
      (.catalog(problem), [header, CatalogTextCatalog.detail(problem), checkWithAdmin].joined(separator: "\n"))
    }
    let version = BuildCatalogProblem.Position(appIndex: 0, appID: "a", versionIndex: 1, versionID: "v")
    let otherProblems: [BuildCatalogProblem] = [
      .unsupportedSchemaVersion(3), .unsupportedSchemaVersion(0),
      .invalidID(position: CatalogTextCatalog.position(app: 1)),
      .unsupportedPlatform(position: CatalogTextCatalog.position(app: 1, appID: "a")),
      .invalidCreatedAt(position: version),
      .invalidBuildURL(.notHTTPS, position: version),
    ]
    rows += otherProblems.map { (problem: BuildCatalogProblem) -> (CatalogLoadFailure, String?) in
      (.catalog(problem), nil)
    }
    return rows
  }
}
