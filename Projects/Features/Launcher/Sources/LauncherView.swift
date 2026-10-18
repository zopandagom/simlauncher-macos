import SwiftUI

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
public struct LauncherView: View {
  let model: LauncherModel

  public init(model: LauncherModel) {
    self.model = model
  }

  public var body: some View {
    ContentUnavailableView {
      Label("SimLauncher", systemImage: "hand.wave")
    } description: {
      Text(self.model.greeting.message)
    } actions: {
      Button("인사하기") {
        self.model.waveButtonTapped()
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
