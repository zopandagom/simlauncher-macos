import SwiftUI

/// "업데이트" 절: 새 버전 자동 확인 토글과 캡션, 관리자 잠금 안내. 배포 저장소가 있는 빌드(`isUpdateCheckAvailable`)에만 보인다.
/// 잠기면 토글은 강제 값으로 보이고 바꿀 수 없다.
struct UpdateSettingsSection: View {
  let model: SettingsModel

  var body: some View {
    if self.model.isUpdateCheckAvailable {
      Section(SettingsText.updateSectionTitle) {
        if self.model.automaticUpdateCheck.isLocked {
          Label(SettingsText.automaticUpdateCheckLockedNote, systemImage: "lock.fill")
            .fixedSize(horizontal: false, vertical: true)
        }
        Toggle(
          SettingsText.automaticUpdateCheckToggle,
          isOn: Binding(
            get: { self.model.automaticUpdateCheck.isEnabled },
            set: { self.model.automaticUpdateCheckChanged($0) }
          )
        )
        .disabled(self.model.automaticUpdateCheck.isLocked)
        Text(SettingsText.automaticUpdateCheckCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
