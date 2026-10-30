import AndroidSDKInterface
import AndroidSDKTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesInterface
import PreferencesTesting
import SettingsFeature
import SwiftUI

/// App 없이 설정 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 위의 고르기에서 상황을 바꾸면 Fake 를 새로 만든다: 저장된 목록은 `PreferencesClientFake`(메모리, 등록·삭제가 그대로
/// 반영된다), 등록 확인의 받기는 `DownloadClientFake`(1초 뒤 상황에 정한 결과, "확인 중" 은 취소할 때까지 끝나지 않음)다.
/// "Android SDK 위치" 절은 저장된 위치를 상황에 정하고, "다른 폴더 고르기…" 로 아무 폴더나 고르면 `AndroidSDKClientFake` 가
/// 0.5초 뒤 상황에 정한 판정(기본: 빈 폴더, 쓸 수 있음)을 돌려준다. 위치가 바뀐 알림은 받을 Android 화면이 없어 버린다.
/// 설정 씬은 App 이 조립한다. 여기서는 일반 창에 띄우고, 확인 중 창을 닫으면(onDisappear) 확인이 취소된다.
@main
struct SettingsFeatureExampleApp: App {
  @State private var scenario = ExampleScenario.empty
  @State private var model = ExampleScenario.empty.makeModel()

  var body: some Scene {
    WindowGroup {
      VStack(spacing: 0) {
        Picker(
          selection: Binding(
            get: { self.scenario },
            set: { scenario in
              self.scenario = scenario
              self.model = scenario.makeModel()
            }
          )
        ) {
          ForEach(ExampleScenario.allCases, id: \.self) { scenario in
            Text(verbatim: scenario.title).tag(scenario)
          }
        } label: {
          Text(verbatim: "상황")
        }
        .padding()
        // 상황을 바꾸면 화면을 새로 만들어 onAppear 가 새 Model 의 목록을 읽는다.
        SettingsView(model: self.model)
          .id(self.scenario)
      }
    }
  }
}

/// Example 의 상황. 저장된 목록과 "등록" 을 눌렀을 때 받기 결과를 정한다.
enum ExampleScenario: CaseIterable, Hashable {
  case empty
  case sample
  case withProblems
  case locked
  case checking
  case notCatalog
  case newerSchema
  case versionProblem
  case notFound
  case hostNotFound
  case tooLarge
  case sdkChosen
  case sdkLocked
  case sdkInvalid
  case sdkPickSDK
  case sdkPickReadOnlySDK
  case sdkPickOtherContents
  case sdkPickUnsupportedVolume

  var title: String {
    switch self {
    case .empty: "빈 목록 (등록하면 성공)"
    case .sample: "쓸 수 있는 주소 2개"
    case .withProblems: "문제 섞인 목록 (http·중복·빈 주소·사용자 이름)"
    case .locked: "관리자 잠금"
    case .checking: "확인 중 (취소할 때까지 끝나지 않음)"
    case .notCatalog: "등록 실패: 로그인 페이지(HTML)"
    case .newerSchema: "등록 실패: 새 규격 (schemaVersion 3)"
    case .versionProblem: "등록 실패: 버전 항목의 날짜 형식"
    case .notFound: "등록 실패: HTTP 404"
    case .hostNotFound: "등록 실패: 서버 주소를 찾지 못함"
    case .tooLarge: "등록 실패: 5 MiB 초과"
    case .sdkChosen: "SDK 위치: 고른 폴더"
    case .sdkLocked: "SDK 위치: 관리자 잠금"
    case .sdkInvalid: "SDK 위치: 잘못된 저장 값"
    case .sdkPickSDK: "SDK 위치 고르기: SDK 폴더"
    case .sdkPickReadOnlySDK: "SDK 위치 고르기: 쓸 수 없는 SDK 폴더"
    case .sdkPickOtherContents: "SDK 위치 고르기: 다른 파일이 든 폴더"
    case .sdkPickUnsupportedVolume: "SDK 위치 고르기: exFAT 디스크"
    }
  }

  @MainActor
  func makeModel() -> SettingsModel {
    let setting = self.setting
    let preferences = PreferencesClientFake(urls: setting.urls, isLocked: setting.isLocked)
    preferences.setStoredAndroidSDKPath(self.androidSDKPath)
    let download = DownloadClientFake()
    download.setDelay(.seconds(1))
    download.setFetchResult(self.fetchResult)
    if self == .checking {
      download.suspendFetches()
    }
    let androidSDK = AndroidSDKClientFake()
    androidSDK.setDelay(.milliseconds(500))
    androidSDK.setCandidateResult(self.candidateResult)
    return SettingsModel(
      preferences: preferences, download: download, androidSDK: androidSDK,
      home: URL(filePath: "/Users/example", directoryHint: .isDirectory), androidSDKLocationChanged: {}
    )
  }

  private var androidSDKPath: AndroidSDKPathSetting {
    switch self {
    case .sdkChosen: AndroidSDKPathSetting(value: .path("/Volumes/Tools/AndroidSDK"), isLocked: false)
    case .sdkLocked: AndroidSDKPathSetting(value: .path("/Volumes/Tools/AndroidSDK"), isLocked: true)
    case .sdkInvalid: AndroidSDKPathSetting(value: .path("tools/sdk"), isLocked: false)
    default: .absent
    }
  }

  private var candidateResult: AndroidSDKClientFake.CandidateResult {
    switch self {
    case .sdkPickSDK: (.sdk, true)
    case .sdkPickReadOnlySDK: (.sdk, false)
    case .sdkPickOtherContents: (.otherContents, true)
    case .sdkPickUnsupportedVolume: (.unsupportedVolume, true)
    default: (.empty, true)
    }
  }

  private var setting: CatalogURLSetting {
    switch self {
    case .sample: .sample
    case .withProblems: .withProblems
    case .locked: .locked
    default: .empty
    }
  }

  private var fetchResult: Result<Data, DownloadError> {
    switch self {
    case .empty, .sample, .withProblems, .locked, .checking, .sdkChosen, .sdkLocked, .sdkInvalid, .sdkPickSDK,
         .sdkPickReadOnlySDK, .sdkPickOtherContents, .sdkPickUnsupportedVolume:
      .success(ExampleCatalog.valid)
    case .notCatalog: .success(ExampleCatalog.loginPage)
    case .newerSchema: .success(ExampleCatalog.newerSchema)
    case .versionProblem: .success(ExampleCatalog.badCreatedAt)
    case .notFound: .failure(.httpStatus(404))
    case .hostNotFound: .failure(.hostNotFound)
    case .tooLarge: .failure(.tooLarge)
    }
  }
}

/// 받은 것으로 돌려줄 카탈로그 내용 (docs/CATALOG.md).
enum ExampleCatalog {
  /// 앱 2개.
  static let valid = Data("""
  {
    "schemaVersion": 1,
    "apps": [
      {
        "id": "sample-app",
        "name": "Sample",
        "versions": [
          {
            "id": "build-42",
            "name": "1.0 (42)",
            "createdAt": "2026-10-21T04:08:49Z",
            "buildURL": "https://builds.example.com/sample-42.zip"
          }
        ]
      },
      { "id": "other-app", "name": "Other", "versions": [] }
    ]
  }
  """.utf8)

  static let loginPage = Data("<!doctype html><html><body>Sign in</body></html>".utf8)

  static let newerSchema = Data(#"{ "schemaVersion": 3, "apps": [] }"#.utf8)

  /// 첫 앱의 첫 버전 날짜에 시간대가 없다.
  static let badCreatedAt = Data("""
  {
    "schemaVersion": 1,
    "apps": [
      {
        "id": "sample-app",
        "name": "Sample",
        "versions": [
          {
            "id": "build-42",
            "name": "1.0 (42)",
            "createdAt": "2026-10-21T04:08:49",
            "buildURL": "https://builds.example.com/sample-42.zip"
          }
        ]
      }
    ]
  }
  """.utf8)
}

#Preview("빈 목록") {
  SettingsView(model: ExampleScenario.empty.makeModel())
}

#Preview("문제 섞인 목록") {
  SettingsView(model: ExampleScenario.withProblems.makeModel())
}

#Preview("SDK 위치: 고른 폴더") {
  SettingsView(model: ExampleScenario.sdkChosen.makeModel())
}

#Preview("SDK 위치: 관리자 잠금") {
  SettingsView(model: ExampleScenario.sdkLocked.makeModel())
}

#Preview("관리자 잠금") {
  SettingsView(model: ExampleScenario.locked.makeModel())
}

#Preview("확인 중 (주소를 입력하고 등록)") {
  SettingsView(model: ExampleScenario.checking.makeModel())
}

#Preview("등록 실패: 버전 항목의 날짜 형식 (주소를 입력하고 등록)") {
  SettingsView(model: ExampleScenario.versionProblem.makeModel())
}
