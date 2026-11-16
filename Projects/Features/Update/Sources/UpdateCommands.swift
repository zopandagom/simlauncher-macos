import SwiftUI

/// 메뉴 막대 "SimLauncher" 메뉴의 "업데이트 확인…" (앱 정보 항목 바로 뒤). 배포 저장소가 없는 빌드에는 항목이 없다.
/// 업데이트 확인 창을 여는 곳은 이 항목 하나다 (창 씬의 Window 메뉴 항목은 App 이 `.commandsRemoved()` 로 뺀다).
public struct UpdateCommands: Commands {
  let model: UpdateModel

  public init(model: UpdateModel) {
    self.model = model
  }

  public var body: some Commands {
    CommandGroup(after: .appInfo) {
      UpdateMenuButton(model: self.model)
    }
  }
}

/// 누르면 업데이트 확인 창을 열고(이미 열려 있으면 앞으로) 확인을 요청한다. 창이 확인 중이면 그 확인에 합류한다.
struct UpdateMenuButton: View {
  let model: UpdateModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    if self.model.isAvailable {
      Button(UpdateText.menuItem) {
        self.openWindow(id: UpdateCheckView.windowID)
        Task { await self.model.checkForUpdatesRequested() }
      }
    }
  }
}
