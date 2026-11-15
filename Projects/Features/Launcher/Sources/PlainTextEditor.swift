import AppKit
import SwiftUI

/// 자동 바꾸기를 끈 여러 줄 편집기 (푸시 JSON 입력). SwiftUI `TextEditor` 는 macOS 의 "스마트 따옴표 및 대시" 설정을 따라 입력한
/// `"` 를 `“ ”` 로, `--` 를 `—` 로 바꿔 JSON 을 망가뜨린다 (Xcode 27.2·macOS 26 에서 확인). 그래서 `NSTextView` 의 따옴표·대시·
/// 텍스트 대치·맞춤법 자동 고침을 끈다. 붙여 넣은 둥근 따옴표는 그대로 들어오고 Core `PushPayload` 검사가 `.smartQuotes` 로 알린다.
/// 글자는 Model 의 이벤트 메서드로만 넘긴다 (`onChange`, 양방향 바인딩 없음).
struct PlainTextEditor: NSViewRepresentable {
  let text: String
  let accessibilityLabel: String
  let onChange: @MainActor (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onChange: self.onChange)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.borderType = .bezelBorder
    guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textView.string = self.text
    textView.setAccessibilityLabel(self.accessibilityLabel)
    textView.delegate = context.coordinator
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.onChange = self.onChange
    guard let textView = scrollView.documentView as? NSTextView, textView.string != self.text else { return }
    // 입력 중 되돌아온 같은 글자는 건드리지 않는다 (커서가 끝으로 가지 않게). Model 이 글자를 바꾼 때만 넣는다.
    textView.string = self.text
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var onChange: @MainActor (String) -> Void

    init(onChange: @escaping @MainActor (String) -> Void) {
      self.onChange = onChange
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      self.onChange(textView.string)
    }
  }
}
