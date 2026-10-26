import ProjectDescription

// 모듈 이름의 단일 출처. 새 모듈은 여기에 이름(Feature·Shared 는 case, Client 는 static 상수)을 추가한 뒤 Projects/ 아래에 매니페스트를 만든다.
// 규칙은 docs/ARCHITECTURE.md 의 "모듈 추가" 절 참고.

/// 외부 시스템(권한, 저장소, 시스템 서비스 등)을 감싸는 Client 모듈.
/// 각 Client 는 Interface / Impl / Testing / Tests 네 타깃으로 나뉜다.
/// 처음에는 Client 가 없을 수 있으므로(값이 없는 enum 은 raw value 를 가질 수 없다) static 상수로 추가한다.
public struct Client: Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var interface: String { "\(self.rawValue)Interface" }
  public var impl: String { "\(self.rawValue)Impl" }
  public var testing: String { "\(self.rawValue)Testing" }
  public var tests: String { "\(self.rawValue)Tests" }
  var path: Path { .relativeToRoot("Projects/Clients/\(self.rawValue)") }
}

// 새 Client 는 이 extension 에 static 상수로 추가한다.
public extension Client {
  /// iOS 시뮬레이터 기기·런타임 목록과 런타임 디스크 이미지 목록, 켜기·끄기·만들기·삭제·초기화, 앱 설치·실행, 화면 찍기,
  /// Simulator 앱 열기 (`xcrun simctl`).
  static let simulator = Client("Simulator")
  /// 로컬 iOS 앱 번들(.app) 검사와 zip 풀기.
  static let appBundle = Client("AppBundle")
  /// 실행 파일을 인자 배열로 실행하고 종료 코드·stdout·stderr 를 돌려준다 (셸을 거치지 않는다).
  /// 끝날 때까지 기다리는 실행과, 취소·시간 제한으로 멈추고 출력을 받는 대로 넘기는 실행 두 가지.
  /// 인자 구성·결과 해석은 이것을 조합하는 Client Impl 이 한다.
  static let command = Client("Command")
  /// 쓸 Xcode 확인·선택(xcode-select, /Applications), 라이선스·첫 실행 준비 확인, Xcode·App Store 열기,
  /// 기본 iOS 런타임 확인·설치(`xcodebuild -downloadPlatform iOS`).
  static let devEnvironment = Client("DevEnvironment")
  /// 사용자가 입력·등록한 HTTPS 주소에서 큰 파일(임시 폴더, 진행률·취소)과 작은 파일(메모리, 상한)을 받는다 (URLSession).
  /// https 로만 리다이렉트를 따라가고 인증은 하지 않는다.
  static let download = Client("Download")
  /// 사용자 설정(UserDefaults 표준 도메인 = 앱 번들 ID): 빌드 카탈로그 주소 목록 읽기·추가·삭제.
  /// 관리자가 구성 프로필로 강제한 키(`objectIsForced`)는 잠김이라 쓰지 않는다.
  static let preferences = Client("Preferences")
  /// 사용자 폴더와 Finder: 스크린샷 저장 폴더(사진 폴더의 `SimLauncher`) 준비와 파일 이름 예약(덮어쓰지 않음)·
  /// 예약 파일 지우기, Finder 에서 파일 선택해 보이기 (FileManager·NSWorkspace).
  static let workspace = Client("Workspace")
}

/// 화면 단위 기능 모듈. Feature 끼리는 서로 의존하지 않는다.
/// 각 Feature 는 Feature / Tests / Example 세 타깃으로 나뉜다.
public enum Feature: String, CaseIterable {
  case launcher = "Launcher"
  /// Xcode 설치·라이선스·첫 실행 준비 단계별 안내와 다시 확인, 기본 iOS 런타임 설치(진행·취소).
  case setup = "Setup"
  /// 설정 창(⌘,): 빌드 카탈로그 주소 등록(한 번 받아 형식 확인)·삭제, 관리자 강제 목록은 잠금 안내.
  case settings = "Settings"

  public var name: String { "\(self.rawValue)Feature" }
  public var tests: String { "\(self.name)Tests" }
  public var example: String { "\(self.name)Example" }
  var path: Path { .relativeToRoot("Projects/Features/\(self.rawValue)") }
}

/// 여러 모듈이 함께 쓰는 공용 모듈 (도메인 값 타입, 공용 UI). Apple 데이터 프레임워크와 Client 에 의존하지 않는다.
/// 각 Shared 모듈은 모듈 / Tests 두 타깃으로 나뉜다.
public enum Shared: String, CaseIterable {
  case core = "Core"

  public var name: String { self.rawValue }
  public var tests: String { "\(self.rawValue)Tests" }
  var path: Path { .relativeToRoot("Projects/Shared/\(self.rawValue)") }
}

public extension TargetDependency {
  static func client(interface client: Client) -> TargetDependency {
    .project(target: client.interface, path: client.path)
  }

  /// Impl 은 App(조립 지점)만 의존한다.
  static func client(impl client: Client) -> TargetDependency {
    .project(target: client.impl, path: client.path)
  }

  /// Testing 은 테스트 타깃과 Example 앱만 의존한다.
  static func client(testing client: Client) -> TargetDependency {
    .project(target: client.testing, path: client.path)
  }

  static func shared(_ shared: Shared) -> TargetDependency {
    .project(target: shared.name, path: shared.path)
  }

  static func feature(_ feature: Feature) -> TargetDependency {
    .project(target: feature.name, path: feature.path)
  }
}
