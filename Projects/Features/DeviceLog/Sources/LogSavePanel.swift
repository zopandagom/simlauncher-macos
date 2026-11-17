import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 로그 창 "저장…" 의 저장 패널. Model 단계가 `.choosingLocation` 이 되면 이 뷰가 놓인 창(NSWindow)에 시트로 띄우고,
/// 고른 파일 URL(또는 취소)을 그 요청 번호와 함께 돌려준다. 파일 쓰기는 하지 않는다 (Model → Workspace Client).
/// `fileImporter` 처럼 표시와 결과 전달만 하는 View 의 일시 UI다. `fileExporter` 는 쓰지 않는다 (쓰기가 View 쪽에서 일어난다).
/// 기본 폴더는 정하지 않는다 (시스템이 마지막 폴더를 기억한다. 홈 경로를 코드에 두지 않는다). 같은 이름 덮어쓰기는 패널이 묻는다.
/// 창이 아직 없으면(드묾) 떠 있는 패널로 띄운다.
struct LogSavePanel: NSViewRepresentable {
  /// 띄울 요청 (`.choosingLocation` 의 이름·번호). nil 이면 아무것도 하지 않는다.
  let request: Request?
  let chosen: @MainActor (URL, Int) -> Void
  let cancelled: @MainActor (Int) -> Void

  struct Request: Equatable {
    let suggestedFileName: String
    let number: Int
  }

  final class Coordinator {
    /// 이미 띄운 요청 번호 (다시 그릴 때 겹쳐 띄우지 않는다).
    var presented: Int?
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context _: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ view: NSView, context: Context) {
    guard let request = self.request, context.coordinator.presented != request.number else { return }
    context.coordinator.presented = request.number
    let chosen = self.chosen
    let cancelled = self.cancelled
    // 화면 갱신 중에 모달을 띄우지 않고 다음 차례에 띄운다.
    Task { @MainActor [weak view] in
      Self.present(request, in: view?.window, chosen: chosen, cancelled: cancelled)
    }
  }

  private static func present(
    _ request: Request,
    in window: NSWindow?,
    chosen: @escaping @MainActor (URL, Int) -> Void,
    cancelled: @escaping @MainActor (Int) -> Void
  ) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = request.suggestedFileName
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    let completion: @MainActor (NSApplication.ModalResponse) -> Void = { response in
      if response == .OK, let url = panel.url {
        chosen(url, request.number)
      } else {
        cancelled(request.number)
      }
    }
    if let window {
      panel.beginSheetModal(for: window) { response in
        MainActor.assumeIsolated { completion(response) }
      }
    } else {
      panel.begin { response in
        MainActor.assumeIsolated { completion(response) }
      }
    }
  }
}
