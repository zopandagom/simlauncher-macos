import Core
import SwiftUI

/// 기기 한 줄: 모양 아이콘, 표시 이름, "API · 상태" 글자(쓸 수 없으면 이유 줄), 켜기·끄기 버튼(앱 작업 중이면 진행 표시),
/// 기기 작업 메뉴(… 버튼과 컨텍스트 메뉴: 초기화·삭제).
/// 앱이 켜는 중인 행은 끄기를 포함한 모든 동작을 막는다. 앱 밖에서 켜는 중인 행은 끌 수 있다.
/// 쓸 수 없는 기기는 흐리게 그리고 이유를 보인다. 실행 중이면 상태도 함께 보이고 끌 수 있다.
/// 막힌 메뉴 항목은 비활성으로 두고 이유를 메뉴 맨 위에 보인다.
struct AndroidDeviceRow: View {
  let device: AndroidVirtualDevice
  /// 이 기기에서 앱이 진행 중인 작업. nil 이면 없다.
  let task: AndroidDeviceTask?
  let bootTapped: () -> Void
  let shutdownTapped: () -> Void
  let eraseTapped: () -> Void
  let deleteTapped: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: self.iconName)
        .font(.title2)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: self.device.displayName)
        Text(verbatim: self.statusLine)
          .font(.caption)
          .foregroundStyle(.secondary)
        if case let .unavailable(reason) = self.device.availability {
          Text(AndroidDevicesText.reason(for: reason))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
      self.action
      Menu {
        self.menuItems
      } label: {
        Label(AndroidDevicesText.deviceActionsMenu, systemImage: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .disabled(self.isBusy)
      .help(self.blockReason ?? AndroidDevicesText.deviceActionsMenu)
    }
    .padding(.vertical, 4)
    .foregroundStyle(self.isAvailable ? .primary : .secondary)
    .contextMenu {
      if !self.isBusy {
        self.menuItems
      }
    }
  }

  @ViewBuilder
  private var menuItems: some View {
    if let reason = self.blockReason {
      Text(reason)
      Divider()
    }
    Button(AndroidDevicesText.eraseMenuItem, action: self.eraseTapped)
      .disabled(self.device.eraseAvailability != .allowed)
    Button(AndroidDevicesText.deleteMenuItem, role: .destructive, action: self.deleteTapped)
      .disabled(self.device.deleteAvailability != .allowed)
  }

  /// 메뉴 맨 위에 보일 이유. 켜져 있으면 삭제·초기화 모두, 쓸 수 없으면 초기화가 막힌다.
  private var blockReason: String? {
    if case .blocked(.notShutdown) = self.device.deleteAvailability {
      return AndroidDevicesText.blockReason(.notShutdown)
    }
    if case .blocked(.unavailable) = self.device.eraseAvailability {
      return AndroidDevicesText.blockReason(.unavailable)
    }
    return nil
  }

  /// 앱 작업 중이면 진행 표시(켜는 중이면 오래 걸릴 수 있다는 도움말), 켤 수 있으면 "켜기", 켜는 중·켜짐이면 "끄기".
  @ViewBuilder
  private var action: some View {
    if let task = self.task {
      ProgressView()
        .controlSize(.small)
        .help(task == .boot ? AndroidDevicesText.bootingHelp : AndroidDevicesText.taskLabel(for: task))
        .accessibilityLabel(AndroidDevicesText.taskLabel(for: task))
    } else if self.device.canBoot {
      Button(AndroidDevicesText.bootButton, action: self.bootTapped)
    } else if self.device.canShutdown {
      Button(AndroidDevicesText.shutdownButton, action: self.shutdownTapped)
    }
  }

  private var isBusy: Bool {
    self.task != nil
  }

  private var isAvailable: Bool {
    self.device.availability == .available
  }

  /// "API 37.0 · 꺼짐". 앱 작업 중이면 작업 글자(켜는 중이면 오래 걸릴 수 있다는 안내도), 쓸 수 없으면 "사용할 수 없음" (실행 중이면 상태도 함께).
  private var statusLine: String {
    var parts: [String] = []
    if let image = self.device.systemImage {
      parts.append(AndroidDevicesText.apiLabel(image))
    }
    if let task = self.task {
      parts.append(AndroidDevicesText.taskLabel(for: task))
      if task == .boot {
        parts.append(AndroidDevicesText.bootingHelp)
      }
    } else if self.isAvailable {
      parts.append(AndroidDevicesText.stateLabel(for: self.device.state))
    } else {
      parts.append(AndroidDevicesText.unavailableLabel)
      if self.device.state != .shutdown {
        parts.append(AndroidDevicesText.stateLabel(for: self.device.state))
      }
    }
    return parts.joined(separator: " · ")
  }

  private var iconName: String {
    switch self.device.formFactor {
    case .phone: "smartphone"
    case .tablet: "ipad.landscape"
    case .none: "questionmark.square.dashed"
    }
  }
}
