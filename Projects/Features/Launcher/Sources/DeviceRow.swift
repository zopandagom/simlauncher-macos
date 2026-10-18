import Core
import SwiftUI

/// 기기 한 줄: 종류 아이콘, 이름, 상태, 켜기·끄기 버튼. 쓸 수 없는 기기는 흐리게 그리고 이유를 보인다.
struct DeviceRow: View {
  let device: VirtualDevice
  let isBusy: Bool
  let bootTapped: () -> Void
  let shutdownTapped: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: self.iconName)
        .font(.title2)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: self.device.name)
        Text(self.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
        if case let .unavailable(reason) = self.device.availability {
          Text(LauncherText.reason(for: reason))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
      self.action
    }
    .padding(.vertical, 4)
    .foregroundStyle(self.isAvailable ? .primary : .secondary)
  }

  @ViewBuilder
  private var action: some View {
    if self.isBusy {
      ProgressView()
        .controlSize(.small)
    } else if self.isAvailable, self.device.state == .shutdown {
      Button(LauncherText.bootButton, action: self.bootTapped)
    } else if self.device.state == .booted {
      Button(LauncherText.shutdownButton, action: self.shutdownTapped)
    }
  }

  private var isAvailable: Bool {
    self.device.availability == .available
  }

  private var statusText: String {
    self.isAvailable ? LauncherText.stateLabel(for: self.device.state) : LauncherText.unavailableLabel
  }

  private var iconName: String {
    switch self.device.family {
    case .phone: "iphone"
    case .tablet: "ipad"
    case .watch, .tv, .vision, .other: "questionmark.square.dashed"
    }
  }
}
