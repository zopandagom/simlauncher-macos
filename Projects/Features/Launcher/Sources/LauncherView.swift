import SwiftUI

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
/// 화면 문자열은 이 모듈의 `Localizable.xcstrings` 에서 찾도록 `bundle: .module` 을 넘긴다.
public struct LauncherView: View {
  let model: LauncherModel

  public init(model: LauncherModel) {
    self.model = model
  }

  public var body: some View {
    ContentUnavailableView {
      Label {
        Text(verbatim: "SimLauncher")
      } icon: {
        Image(systemName: "iphone")
      }
    } description: {
      Text("iOS 시뮬레이터 기기 목록이 여기에 표시됩니다.", bundle: .module)
    }
  }
}
