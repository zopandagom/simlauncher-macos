import Core
import SwiftUI

/// 저장된 카탈로그 주소 한 줄: 주소(선택 가능, 가운데 생략, 도움말에 전체), 쓸 수 없거나 중복이면 그 이유, 삭제 버튼.
struct CatalogRow: View {
  let entry: CatalogURLEntry
  let canRemove: Bool
  let removeTapped: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        // 저장된 문자열은 번역하지 않는다.
        Text(verbatim: self.entry.raw)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
          .help(self.entry.raw)
          .foregroundStyle(self.isUsable ? .primary : .secondary)
        if let note = SettingsText.entryNote(self.entry.status) {
          Text(note)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
      if self.canRemove {
        Button(action: self.removeTapped) {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(SettingsText.removeAccessibilityLabel)
        .help(SettingsText.removeAccessibilityLabel)
      }
    }
  }

  private var isUsable: Bool {
    if case .usable = self.entry.status {
      return true
    }
    return false
  }
}
