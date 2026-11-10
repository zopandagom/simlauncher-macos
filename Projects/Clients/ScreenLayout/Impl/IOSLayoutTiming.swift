/// iOS 레이아웃 러너의 시간 값 묶음. 테스트는 줄인 값을 넣는다. 근거는 설계(실측)와 각 값의 주석.
struct IOSLayoutTiming: Sendable {
  /// 러너 빌드(`xcodebuild build-for-testing`) 시간 제한. 깨끗한 빌드 4~10초(실측), 느린 Mac·디스크 여유.
  var buildTimeout: Duration = .seconds(300)
  /// xcodebuild 시작부터 ready.json 까지. 같은 부팅 4~9초, 재부팅 직후 25~45초, 새 기기 첫 부팅 85초(실측).
  var readyTimeout: Duration = .seconds(180)
  /// ready.json 을 확인하는 간격.
  var readyPollInterval: Duration = .milliseconds(200)
  /// 러너가 앞 앱이 하나가 되기를 기다리는 최대 초 (요청에 실어 보낸다). 전환 중 두 앱이 함께 앞인 시간 1~3초 넘음(실측).
  var settleSeconds: Double = 8
  /// 요청 하나의 응답 제한. settle 8 + 뒤로 간 앱 실패 약 3초 + 읽기 + 여유.
  var requestTimeout: Duration = .seconds(40)
  /// response.json 을 확인하는 간격.
  var responsePollInterval: Duration = .milliseconds(50)
  /// quit 요청 뒤 xcodebuild 가 끝나기를 기다리는 시간 (실측 0.6초).
  var quitGrace: Duration = .seconds(2)
  /// SIGTERM 뒤 xcodebuild 가 끝나기를 기다리는 시간 (실측 0.0~0.1초).
  var terminateGrace: Duration = .seconds(3)
  /// 준비됨 동안 러너 생존을, 준비 중 기기 켜짐을 확인하는 간격. 러너가 죽고 약 18초 뒤 xcodebuild 가 기기를 다시 켠다(실측).
  var monitorInterval: Duration = .seconds(2)
  /// 남은 러너가 quit 를 읽고 끝나기를 기다리는 시간 (0.6초 + 여유).
  var orphanQuitWait: Duration = .seconds(3)
  /// 남은 러너 pid 를 다시 확인하는 간격.
  var orphanPollInterval: Duration = .milliseconds(200)
  /// 요청 없이 러너가 스스로 끝나기까지의 초 (사용자 결정 2).
  var idleSeconds: Int = 600
  /// 앱 종료 때 모든 러너 정리를 기다리는 상한.
  var stopAllLimit: Duration = .seconds(5)

  static let standard = IOSLayoutTiming()
}
