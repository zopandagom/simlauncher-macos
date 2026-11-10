/// SimLauncher 가 iOS 레이아웃을 읽으려고 시뮬레이터에 설치하는 XCUITest 러너 앱의 정체.
/// ScreenLayout Impl(설치·지우기·앞 앱 후보에서 빼기), Simulator Impl("앱 실행…" 목록·실행 중 앱 목록에서 빼기),
/// Launcher(`minimumOSVersion` 보다 낮은 기기의 "레이아웃 보기" 막기)가 함께 쓴다.
/// 쓰는 쪽이 `AppBundleID(IOSLayoutRunner.appBundleID)` 를 guard 한다 (강제 언래핑하지 않는다).
public enum IOSLayoutRunner {
  /// 러너 테스트 번들의 PRODUCT_NAME. 홈 화면 이름은 `<이름>-Runner`, 러너 실행 파일도 같은 이름이다.
  public static let productName = "SimLauncherLayout"
  /// 테스트 번들 ID (러너 프로젝트 pbxproj 의 PRODUCT_BUNDLE_IDENTIFIER).
  public static let testBundleID = "com.zopandagom.simlauncher.layoutrunner"
  /// 시뮬레이터에 설치되는 러너 앱 ID (= 테스트 번들 ID + ".xctrunner", 실측).
  public static let appBundleID = "com.zopandagom.simlauncher.layoutrunner.xctrunner"
  /// 러너가 도는 가장 낮은 iOS (러너 프로젝트 pbxproj 의 IPHONEOS_DEPLOYMENT_TARGET). 이보다 낮은 기기는 레이아웃 보기를 막는다.
  public static let minimumOSVersion = OSVersion(major: 17)
}
