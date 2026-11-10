import Testing
@testable import Core

struct IOSLayoutRunnerTests {
  @Test("러너 앱 ID 는 테스트 번들 ID 에 .xctrunner 를 붙인 값")
  func appBundleIDIsTestBundleIDWithSuffix() {
    #expect(IOSLayoutRunner.appBundleID == IOSLayoutRunner.testBundleID + ".xctrunner")
  }

  @Test("세 값 모두 AppBundleID 형식이다 (simctl 인자로 쓸 수 있다)")
  func valuesAreValidBundleIDs() {
    #expect(AppBundleID(IOSLayoutRunner.productName) != nil)
    #expect(AppBundleID(IOSLayoutRunner.testBundleID) != nil)
    #expect(AppBundleID(IOSLayoutRunner.appBundleID) != nil)
  }
}
