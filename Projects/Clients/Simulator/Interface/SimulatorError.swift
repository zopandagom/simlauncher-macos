/// 시뮬레이터 작업 실패. 화면 문구는 Feature 가 케이스별로 정하고, 명령 원문은 담지 않는다.
public enum SimulatorError: Error, Hashable, Sendable {
  /// xcrun·simctl 을 쓸 수 없다: provider 가 쓸 Xcode 가 없다고 답함(명령을 실행하지 않음), Xcode 없음,
  /// Command Line Tools 만 있음, DEVELOPER_DIR 경로 없음, xcode-select 실패.
  case developerToolsUnavailable
  /// UDID 형식이 아니거나, simctl 이 "Invalid device" 로 답했거나, 삭제·초기화 사전 확인에서 목록에 없다.
  case deviceNotFound
  /// 기기가 꺼져 있지 않아 지우거나 초기화하지 않았다 (사전 확인. erase 의 "in current state: Booted" 는 분류하지 않는다).
  case deviceNotShutdown
  /// 고른 런타임·기기 종류로 만들 수 없다: 목록에 없거나, 런타임을 쓸 수 없거나, 지원하지 않는 조합.
  /// simctl "Invalid device type"·"Invalid runtime"·"Incompatible device" 도 여기 든다.
  case creationOptionUnavailable
  /// 기기 이름이 `DeviceName.problem` 검사를 통과하지 못해 실행하지 않았다.
  case invalidDeviceName
  /// 개발자 디렉터리에서 Simulator 앱을 찾지 못했다.
  case simulatorAppNotFound
  /// `simctl list -j` 출력(JSON)을 해석하지 못했다 (목록 읽기, 또는 생성·삭제·초기화 전의 목록 확인).
  /// 생성·삭제·초기화 명령은 실행하지 않았다. `simctl runtime list -j` 출력의 최상위가 사전이 아닐 때도 (런타임 이미지 목록).
  case unexpectedOutput
  /// `simctl create` 는 성공(exit 0)했지만 출력에서 새 기기 UDID 를 읽지 못했다. 기기가 만들어졌을 수 있다. `create` 만 던진다.
  case creationResultUnknown
  /// 기기가 켜져 있지 않아 앱 설치·실행, 링크 열기, 화면 찍기·녹화를 하지 못했다: install·launch·openurl 의 SimError 405
  /// "Unable to lookup in current state", screenshot 의 실행 전 확인과 NSPOSIXErrorDomain 60 "Timeout waiting for screen
  /// surfaces", recordVideo 의 실행 전 확인.
  case deviceNotBooted
  /// 설치할 .app 이 그 경로에 없다: 파일 URL 이 아니어서 실행하지 않았거나 NSPOSIXErrorDomain 2 (install).
  case appNotFound
  /// 번들 ID 를 읽지 못했거나 폴더가 아니다: IXErrorDomain 13·42 (install).
  case appInvalid
  /// 이 기기에서 실행할 수 없는 빌드: 실행 파일의 플랫폼·아키텍처가 맞지 않거나 기기 종류(iPhone·iPad)를 지원하지 않는다.
  /// IXUserPresentableErrorDomain 4·6 (install).
  case appIncompatible
  /// 기기 iOS 가 앱의 MinimumOSVersion 보다 낮다: IXUserPresentableErrorDomain 16 (install).
  case appRequiresNewerOS
  /// 그 번들 ID 의 앱이 기기에 없다: FBSOpenApplicationServiceErrorDomain 4, 또는 1 + `reason: NotFound` (launch).
  case appNotInstalled
  /// 실행을 요청했지만 프로세스가 시작되지 않았다: NSPOSIXErrorDomain 3, 그 밖의 FBSOpenApplicationServiceErrorDomain (launch).
  case appLaunchFailed
  /// 기기에 이 링크를 처리할 앱이 없다: LSApplicationWorkspaceErrorDomain 115 (openurl).
  /// 등록되지 않은 앱 스킴, 시뮬레이터에 없는 시스템 앱(mailto:·tel:), Safari 가 받지 않는 스킴(about:·javascript:·data:)이 여기 든다.
  case urlNotHandled
  /// simctl 이 링크 형식을 거절했다: NSPOSIXErrorDomain 22 "Invalid URL", NSOSStatusErrorDomain -50 (openurl).
  /// `DeepLink` 를 거친 값으로는 확인한 범위에서 생기지 않지만, Foundation 과 simctl 판정이 어긋날 때
  /// 일반 "Xcode 준비" 문구 대신 링크를 확인하라고 알리려고 둔다.
  case invalidURL
  /// 같은 기기를 다른 녹화가 이미 쓰고 있어 녹화를 시작하지 못했다: NSPOSIXErrorDomain 16 "Host recording is already in progress"
  /// (recordVideo). Xcode 등 다른 도구의 녹화, 또는 앞선 녹화 프로세스가 비정상으로 끝나 남은 녹화 (기기를 껐다 켜면 풀린다, 측정).
  case recordingInProgress
  /// simctl 이 스스로 끝났지만(종료 코드 0) 저장된 화면이 없다 (파일이 0바이트이거나 없음) (recordVideo). 호출한 쪽은 빈 파일을 지운다.
  case recordingEmpty
  /// 멈추기를 요청했지만 마무리가 늦어 simctl 을 SIGTERM·SIGKILL 로 끝냈고 파일이 아직 비었다 (recordVideo, 시작 신호 뒤).
  /// 녹화는 CoreSimulatorService 에서 이어지다 기기를 끄는 순간 같은 경로에 마무리된다 (측정). 호출한 쪽은 파일을 지우지 않는다.
  case recordingUnfinished
  /// 그 밖의 실패. 설치·실행·링크 열기에서는 위에 없는 domain·code (예: IXUserPresentableErrorDomain 1 실행 파일 없음).
  case commandFailed
}
