import Core
import DownloadInterface
import Foundation
import Testing
@testable import SettingsFeature

struct SettingsResourcesTests {
  @Test("리소스 번들의 원문 언어는 한국어다")
  func resourceBundleIsKorean() {
    #expect(Bundle.module.developmentLocalization == "ko")
  }

  @Test("화면의 모든 문구가 String Catalog 에서 한국어 값으로 컴파일되고, 그 밖의 키는 없다")
  func everyTextIsInCompiledKoreanTable() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko")
    )
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
    let texts = SettingsTextCatalog.plainTexts
    for text in texts {
      #expect(table[text] == text, "\(text)")
    }
    // 보간이 든 키도 .strings 표에 들어간다. 코드의 키가 카탈로그 키와 어긋나면 코드 문자열로 서식을 만들어 겉보기에
    // 멀쩡하므로, 표의 값으로 만든 문구와 함수 결과를 비교한다.
    let formats = SettingsTextCatalog.formatSamples
    for sample in formats {
      #expect(table[sample.key] == sample.key, "\(sample.key)")
      #expect(String(format: table[sample.key] ?? "", arguments: sample.arguments) == sample.text, "\(sample.key)")
    }
    var keys = Set(texts)
    keys.formUnion(formats.map(\.key))
    #expect(keys == Set(table.keys))
  }
}

/// 문구 함수가 돌려주는 값.
struct SettingsTextTests {
  @Test("모든 문구 함수가 모든 케이스에 비어 있지 않은 한국어를 돌려준다")
  func textsAreNonEmptyKorean() throws {
    var texts = SettingsTextCatalog.plainTexts + SettingsTextCatalog.formatSamples.map(\.text)
    texts += SettingsTextCatalog.downloadErrors
      .map { SettingsText.message(for: CatalogRegistrationFailure.download($0)) }
    texts += SettingsTextCatalog.catalogProblems
      .map { SettingsText.message(for: CatalogRegistrationFailure.catalog($0)) }
    texts += SettingsTextCatalog.urlProblems.map(SettingsText.urlProblemReason)
    let usable = try #require(DownloadURL("https://example.com/catalog.json"))
    #expect(SettingsText.entryNote(.usable(usable)) == nil)
    for problem in SettingsTextCatalog.urlProblems {
      try texts.append(#require(SettingsText.entryNote(.invalid(problem))))
    }
    for text in texts {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
  }

  @Test("SDK 폴더 판정 결과 줄: 쓸 수 있는지가 저장·설치 여부를 바꾸는 빈 폴더·SDK 폴더만 문구가 갈리고, 저장하지 않은 줄은 그렇게 말한다")
  func sdkFolderResultTexts() {
    let byCandidate = Dictionary(grouping: SettingsTextCatalog.sdkFolderResults, by: \.candidate)
    for (candidate, results) in byCandidate {
      let texts = Set(results.map(SettingsText.sdkFolderResult))
      #expect(texts.count == (candidate == .empty || candidate == .sdk ? 2 : 1), "\(candidate)")
    }
    for result in SettingsTextCatalog.sdkFolderResults {
      #expect(SettingsText.sdkFolderResult(result).contains("저장하지 않았습니다") == !result.isSaved, "\(result)")
    }
    let readOnlySDK = SettingsSDKFolderResult(path: "/x", candidate: .sdk, writable: false)
    #expect(SettingsText.sdkFolderResult(readOnlySDK).contains("설치할 수 없습니다"))
    #expect(
      SettingsText.androidSDKInvalidSetting(isLocked: true) != SettingsText.androidSDKInvalidSetting(isLocked: false)
    )
    #expect(SettingsText.androidSDKInvalidSetting(isLocked: true).contains("담당자"))
  }

  @Test("빈 입력은 안내 없이 버튼만 비활성이고, 그 밖의 입력 문제와 중복은 안내가 있다")
  func draftProblemTexts() {
    #expect(SettingsText.draftProblem(.url(.empty)) == nil)
    for problem in SettingsTextCatalog.urlProblems where problem != .empty {
      #expect(SettingsText.draftProblem(.url(problem)) != nil, "\(problem)")
    }
    #expect(SettingsText.draftProblem(.duplicate) == "이미 등록된 카탈로그입니다.")
  }

  @Test("받기 실패는 등록 실패 문구로 그대로 쓰이고, HTTP 상태 범위마다 다른 문구다")
  func downloadFailureTexts() {
    for error in SettingsTextCatalog.downloadErrors {
      #expect(SettingsText.message(for: CatalogRegistrationFailure.download(error)) == SettingsText.message(for: error))
    }
    let byRange = [401, 404, 500, 302].map { SettingsText.message(for: DownloadError.httpStatus($0)) }
    #expect(Set(byRange).count == byRange.count)
    #expect(SettingsText.message(for: DownloadError.httpStatus(403)).contains("HTTP 403"))
    #expect(SettingsText.message(for: DownloadError.tooLarge).contains("5 MiB"))
  }

  @Test("형식 문제는 등록하지 않았다는 첫 줄로 시작하고, 카탈로그를 고칠 문제만 만든 사람에게 알리라고 한다")
  func catalogProblemTexts() {
    let header = "카탈로그 형식이 맞지 않아 등록하지 않았습니다."
    let report = "카탈로그를 만든 사람에게 알려 주세요."
    let checkAddress = "주소가 catalog.json 파일을 바로 가리키는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알려 주세요."
    for problem in SettingsTextCatalog.catalogProblems {
      let lines = SettingsText.message(for: problem).components(separatedBy: "\n")
      #expect(lines.first == header, "\(problem)")
      switch problem {
      case .notJSONObject:
        // 주소 확인과 만든 사람에게 알리는 안내가 본문 한 줄에 함께 있다.
        #expect(lines.count == 2)
        #expect(lines.last?.contains("catalog.json") == true)
      case let .unsupportedSchemaVersion(version) where version > BuildCatalog.supportedSchemaVersion:
        #expect(lines.count == 2)
        #expect(lines.last?.contains("업데이트") == true)
      case let .missingField(_, position) where position == .root, let .wrongType(_, position) where position == .root:
        // 다른 JSON 객체를 가리키는 주소도 여기서 걸리므로 주소 확인을 먼저 안내한다.
        #expect(lines.count == 3, "\(problem)")
        #expect(lines.last == checkAddress, "\(problem)")
      default:
        #expect(lines.count == 3, "\(problem)")
        #expect(lines.last == report, "\(problem)")
      }
    }
    #expect(
      SettingsText.message(for: BuildCatalogProblem.unsupportedSchemaVersion(2))
        != SettingsText.message(for: BuildCatalogProblem.unsupportedSchemaVersion(0))
    )
    let field = SettingsText.message(for: BuildCatalogProblem.missingField(
      .buildURL,
      position: SettingsTextCatalog.versionPosition
    ))
    #expect(field.contains("buildURL"))
  }

  @Test("위치는 최상위·앱·앱의 버전 세 형태이고, 인덱스는 1부터, id 는 있을 때만 괄호로 붙는다")
  func locationTexts() {
    #expect(SettingsText.location(.root) == "카탈로그 최상위")
    let app = BuildCatalogProblem.Position(appIndex: 0, appID: "my-app", versionIndex: nil, versionID: nil)
    #expect(SettingsText.location(app) == "1번째 앱(id: my-app)")
    let appWithoutID = BuildCatalogProblem.Position(appIndex: 2, appID: nil, versionIndex: nil, versionID: nil)
    #expect(SettingsText.location(appWithoutID) == "3번째 앱")
    #expect(SettingsText.location(SettingsTextCatalog.versionPosition) == "2번째 앱(id: my-app)의 3번째 버전(id: v1.2)")
    let versionWithoutID = BuildCatalogProblem.Position(appIndex: 0, appID: nil, versionIndex: 0, versionID: nil)
    #expect(SettingsText.location(versionWithoutID) == "1번째 앱의 1번째 버전")
  }

  @Test("저장된 주소의 안내: 주소 문제는 이유, 중복은 앞 항목의 순서(1부터)")
  func entryNoteTexts() {
    #expect(SettingsText.entryNote(.invalid(.empty)) == "쓸 수 없는 주소라 읽지 않습니다: 빈 주소입니다.")
    #expect(SettingsText.entryNote(.duplicate(firstIndex: 0)) == "위의 1번째 주소와 같은 카탈로그라 한 번만 읽습니다.")
  }

  @Test("시간 초과는 응답이 없다고 단정하지 않는다 (받는 중이어도 전체 60초를 넘기면 멈춘다)")
  func timedOutText() {
    let text = SettingsText.message(for: DownloadError.timedOut)
    #expect(text.contains("60초 안에 받지 못해"))
    #expect(!text.contains("응답하지 않아"))
  }

  @Test("JSON 객체로 읽지 못한 카탈로그는 주소가 맞으면 만든 사람에게 알리라고 끝맺는다")
  func notJSONObjectEndsWithReport() {
    let lines = SettingsText.message(for: BuildCatalogProblem.notJSONObject).components(separatedBy: "\n")
    #expect(lines.count == 2)
    #expect(lines.last?.hasSuffix("만든 사람에게 알려 주세요.") == true)
  }

  @Test("apps·versions 배열의 항목이 객체가 아니면 항목 문구이고, 그 밖의 타입 오류는 필드 문구다")
  func notObjectItemTexts() {
    let items: [BuildCatalogProblem] = [
      .wrongType(.apps, position: SettingsTextCatalog.appItemPosition),
      .wrongType(.versions, position: SettingsTextCatalog.versionItemPosition),
    ]
    for problem in items {
      #expect(SettingsText.message(for: problem).contains("객체가 아닙니다"), "\(problem)")
    }
    let appPosition = BuildCatalogProblem.Position(appIndex: 0, appID: "my-app", versionIndex: nil, versionID: nil)
    let fields: [BuildCatalogProblem] = [
      .wrongType(.name, position: SettingsTextCatalog.versionPosition),
      .wrongType(.apps, position: .root),
      .wrongType(.versions, position: appPosition),
    ]
    for problem in fields {
      #expect(!SettingsText.message(for: problem).contains("객체가 아닙니다"), "\(problem)")
    }
  }

  @Test("5 MiB 초과는 받은 것을 카탈로그로 단정하지 않고 주소 확인부터 안내한다")
  func tooLargeText() {
    let text = SettingsText.message(for: DownloadError.tooLarge)
    #expect(text.contains("catalog.json"))
    #expect(text.contains("카탈로그를 만든 사람"))
    #expect(!text.hasPrefix("카탈로그 파일이"))
  }

  @Test("https 가 아닌 주소로 넘겨 보내면 주소 확인부터 안내한다")
  func insecureRedirectText() {
    #expect(SettingsText.message(for: DownloadError.insecureRedirect).contains("주소가 맞는지"))
  }

  @Test("403 은 로그인 요구로 단정하지 않고 주소 확인을 안내한다")
  func forbiddenText() {
    #expect(SettingsText.message(for: DownloadError.httpStatus(403)).contains("주소가 맞는지"))
  }
}

/// 문구 함수가 돌려주는 값과 그 카탈로그 키.
enum SettingsTextCatalog {
  static let urlProblems: [DownloadURLProblem] = [.empty, .malformed, .notHTTPS, .missingHost, .hasCredentials]

  /// HTTP 상태 하나만 대표로 넣는다 (상태별 문구는 `formatSamples`).
  static let downloadErrors: [DownloadError] = [
    .insecureRedirect, .httpStatus(404), .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost,
    .secureConnectionFailed, .insufficientDiskSpace, .tooLarge, .cancelled, .storageUnavailable, .failed,
  ]

  /// 2번째 앱(id: my-app)의 3번째 버전(id: v1.2).
  static let versionPosition = BuildCatalogProblem.Position(
    appIndex: 1, appID: "my-app", versionIndex: 2, versionID: "v1.2"
  )

  /// `apps` 배열의 2번째 항목 (객체가 아니면 id 가 없다).
  static let appItemPosition = BuildCatalogProblem.Position(appIndex: 1, appID: nil, versionIndex: nil, versionID: nil)

  /// 2번째 앱(id: my-app)의 `versions` 배열의 3번째 항목 (객체가 아니면 id 가 없다).
  static let versionItemPosition = BuildCatalogProblem.Position(
    appIndex: 1, appID: "my-app", versionIndex: 2, versionID: nil
  )

  /// 모든 케이스, 필드 문제는 모든 필드 (항목이 객체가 아닌 `apps`·`versions` 도).
  static var catalogProblems: [BuildCatalogProblem] {
    var problems: [BuildCatalogProblem] = [.notJSONObject, .unsupportedSchemaVersion(2), .unsupportedSchemaVersion(0)]
    for field in BuildCatalogProblem.Field.allCases {
      problems += [
        .missingField(field, position: .root), .wrongType(field, position: self.versionPosition),
        .emptyField(field, position: self.versionPosition),
      ]
    }
    problems += [
      .wrongType(.apps, position: self.appItemPosition), .wrongType(.versions, position: self.versionItemPosition),
      .wrongType(.apps, position: .root),
      .invalidID(position: self.versionPosition), .duplicateAppID(position: self.versionPosition),
      .duplicateVersionID(position: self.versionPosition), .invalidCreatedAt(position: self.versionPosition),
    ]
    problems += self.urlProblems.map { BuildCatalogProblem.invalidBuildURL($0, position: self.versionPosition) }
    return problems
  }

  /// 보간 없는 문구. 카탈로그 키와 값이 문구 그대로다.
  static var plainTexts: [String] {
    var texts = [
      SettingsText.catalogSectionTitle, SettingsText.lockedNote, SettingsText.emptyList, SettingsText.urlField,
      SettingsText.urlPrompt, SettingsText.urlGuide, SettingsText.addButton, SettingsText.checkingLabel,
      SettingsText.cancelButton, SettingsText.removeAccessibilityLabel, SettingsText.location(.root),
    ]
    texts += self.urlProblems.compactMap { SettingsText.draftProblem(.url($0)) }
    texts += [SettingsText.draftProblem(.duplicate)].compactMap(\.self)
    texts += self.urlProblems.map(SettingsText.urlProblemReason)
    texts += self.downloadErrors.filter(\.isPlain).map { SettingsText.message(for: $0) }
    // 형식 문제의 첫 줄·끝 줄과 보간 없는 본문 (JSON 이 아님).
    texts += SettingsText.message(for: BuildCatalogProblem.notJSONObject).components(separatedBy: "\n")
    texts += [self.line(.invalidID(position: .root), 2), self.line(.missingField(.schemaVersion, position: .root), 2)]
    texts += self.androidSDKTexts
    return texts
  }

  /// 판정 결과 줄의 모든 경우 (후보 × 쓸 수 있음).
  static var sdkFolderResults: [SettingsSDKFolderResult] {
    let candidates: [AndroidSDKFolderCandidate] = [
      .empty, .sdk, .otherContents, .notDirectory, .missing, .unreadable, .unsupportedVolume,
    ]
    return candidates.flatMap { candidate in
      [true, false].map { SettingsSDKFolderResult(path: "/Volumes/Tools/sdk", candidate: candidate, writable: $0) }
    }
  }

  /// "Android SDK 위치" 절의 문구 (모두 보간 없음).
  static var androidSDKTexts: [String] {
    [
      SettingsText.androidSDKSectionTitle, SettingsText.androidSDKDefaultBadge, SettingsText.androidSDKChooseButton,
      SettingsText.androidSDKResetButton, SettingsText.androidSDKInspecting, SettingsText.androidSDKLockedNote,
      SettingsText.androidSDKInvalidSetting(isLocked: true), SettingsText.androidSDKInvalidSetting(isLocked: false),
      SettingsText.androidSDKGuide, SettingsText.androidSDKInstallNote,
    ] + self.sdkFolderResults.map(SettingsText.sdkFolderResult)
  }

  struct FormatSample {
    let key: String
    let arguments: [any CVarArg]
    /// 같은 인자로 문구 함수가 돌려준 값.
    let text: String
  }

  /// 보간이 든 키와, 표의 값에 `arguments` 를 넣으면 나와야 하는 문구.
  static var formatSamples: [FormatSample] {
    self.screenSamples + self.httpSamples + self.schemaSamples + self.locationSamples + self.problemSamples
  }

  private static var screenSamples: [FormatSample] {
    [
      FormatSample(
        key: "쓸 수 없는 주소라 읽지 않습니다: %@.", arguments: [SettingsText.urlProblemReason(.notHTTPS)],
        text: SettingsText.entryNote(.invalid(.notHTTPS)) ?? ""
      ),
      FormatSample(
        key: "위의 %lld번째 주소와 같은 카탈로그라 한 번만 읽습니다.", arguments: [2],
        text: SettingsText.entryNote(.duplicate(firstIndex: 1)) ?? ""
      ),
      FormatSample(key: "등록했습니다. 앱 %lld개가 있습니다.", arguments: [3], text: SettingsText.added(appCount: 3)),
    ]
  }

  private static var httpSamples: [FormatSample] {
    let keys: [(key: String, code: Int)] = [
      ("서버가 접근을 거부해 받지 못했습니다 (HTTP %lld). 주소가 맞는지, 로그인 없이 받을 수 있는 주소인지 확인하세요.", 401),
      ("서버에 카탈로그 파일이 없습니다 (HTTP %lld). 주소가 맞는지 확인하세요.", 410),
      ("서버 오류로 받지 못했습니다 (HTTP %lld). 잠시 뒤 다시 시도하세요.", 503),
      ("서버가 파일을 주지 않았습니다 (HTTP %lld). 주소를 확인한 뒤 다시 시도하세요.", 302),
    ]
    return keys.map { (entry: (key: String, code: Int)) -> FormatSample in
      FormatSample(key: entry.key, arguments: [entry.code], text: SettingsText.message(for: .httpStatus(entry.code)))
    }
  }

  private static var schemaSamples: [FormatSample] {
    [
      FormatSample(
        key: "이 카탈로그는 이 앱보다 새 규격(schemaVersion %lld)입니다. SimLauncher 를 업데이트한 뒤 다시 등록하세요.",
        arguments: [2], text: self.line(.unsupportedSchemaVersion(2), 1)
      ),
      FormatSample(
        key: "카탈로그의 schemaVersion %lld 은 없는 규격입니다 (지원: %lld).",
        arguments: [0, BuildCatalog.supportedSchemaVersion], text: self.line(.unsupportedSchemaVersion(0), 1)
      ),
    ]
  }

  private static var locationSamples: [FormatSample] {
    let appWithID = SettingsText.location(.init(appIndex: 1, appID: "my-app", versionIndex: nil, versionID: nil))
    let appWithoutID = SettingsText.location(.init(appIndex: 1, appID: nil, versionIndex: nil, versionID: nil))
    let version = SettingsText.location(self.versionPosition)
    let versionWithoutID = SettingsText.location(.init(appIndex: 1, appID: nil, versionIndex: 2, versionID: nil))
    // 버전 위치는 "앱 위치의 버전 위치" 로 잇는다. 뒤 부분을 떼어 버전 키의 서식 결과와 비교한다.
    let versionPart = self.suffix(of: version, after: appWithID)
    return [
      FormatSample(key: "%lld번째 앱(id: %@)", arguments: [2, "my-app"], text: appWithID),
      FormatSample(key: "%lld번째 앱", arguments: [2], text: appWithoutID),
      FormatSample(key: "%@의 %@", arguments: [appWithID, versionPart], text: version),
      FormatSample(key: "%lld번째 버전(id: %@)", arguments: [3, "v1.2"], text: versionPart),
      FormatSample(key: "%lld번째 버전", arguments: [3], text: self.suffix(of: versionWithoutID, after: appWithoutID)),
    ]
  }

  /// `text` 가 `"\(prefix)의 "` 로 시작하면 그 뒤. 아니면 빈 문자열 (비교가 실패한다).
  private static func suffix(of text: String, after prefix: String) -> String {
    let head = prefix + "의 "
    guard text.hasPrefix(head) else { return "" }
    return String(text.dropFirst(head.count))
  }

  private static var problemSamples: [FormatSample] {
    let place = SettingsText.location(self.versionPosition)
    let reason = SettingsText.urlProblemReason(.notHTTPS)
    return [
      FormatSample(
        key: "%@에 필수 필드 %@ 가 없거나 null 입니다.", arguments: [place, "name"],
        text: self.line(.missingField(.name, position: self.versionPosition), 1)
      ),
      FormatSample(
        key: "%@의 %@ 값의 형식(타입)이 다릅니다.", arguments: [place, "buildNumber"],
        text: self.line(.wrongType(.buildNumber, position: self.versionPosition), 1)
      ),
      FormatSample(
        key: "%@이 객체가 아닙니다 (%@ 배열의 항목은 객체여야 합니다).",
        arguments: [SettingsText.location(self.appItemPosition), "apps"],
        text: self.line(.wrongType(.apps, position: self.appItemPosition), 1)
      ),
      FormatSample(
        key: "%@이 객체가 아닙니다 (%@ 배열의 항목은 객체여야 합니다).",
        arguments: [SettingsText.location(self.versionItemPosition), "versions"],
        text: self.line(.wrongType(.versions, position: self.versionItemPosition), 1)
      ),
      FormatSample(
        key: "%@의 %@ 가 비어 있습니다.", arguments: [place, "name"],
        text: self.line(.emptyField(.name, position: self.versionPosition), 1)
      ),
      FormatSample(
        key: "%@의 id 가 형식에 맞지 않습니다 (영문·숫자로 시작하고 영문·숫자·. _ - 만, 128자까지).", arguments: [place],
        text: self.line(.invalidID(position: self.versionPosition), 1)
      ),
      FormatSample(
        key: "%@의 id 가 앞의 앱과 같습니다 (대소문자 무시).", arguments: [place],
        text: self.line(.duplicateAppID(position: self.versionPosition), 1)
      ),
      FormatSample(
        key: "%@의 id 가 같은 앱의 앞 버전과 같습니다 (대소문자 무시).", arguments: [place],
        text: self.line(.duplicateVersionID(position: self.versionPosition), 1)
      ),
      FormatSample(
        key: "%@의 createdAt 이 날짜 형식(예: 2026-10-21T04:08:49Z)이 아니거나 없는 날짜·시각입니다.", arguments: [place],
        text: self.line(.invalidCreatedAt(position: self.versionPosition), 1)
      ),
      FormatSample(
        key: "%@의 buildURL 을 쓸 수 없습니다: %@.", arguments: [place, reason],
        text: self.line(.invalidBuildURL(.notHTTPS, position: self.versionPosition), 1)
      ),
    ]
  }

  /// 형식 문제 본문의 `index` 번째 줄 (0: 첫 줄, 1: 무엇이 어디서, 2: 알릴 사람).
  private static func line(_ problem: BuildCatalogProblem, _ index: Int) -> String {
    let lines = SettingsText.message(for: problem).components(separatedBy: "\n")
    return lines.indices.contains(index) ? lines[index] : ""
  }
}

private extension DownloadError {
  /// 보간 없는 문구를 돌려주는 케이스 (HTTP 상태만 숫자가 든다).
  var isPlain: Bool {
    if case .httpStatus = self {
      return false
    }
    return true
  }
}
