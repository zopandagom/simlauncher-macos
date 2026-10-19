import Core
import Foundation
import SwiftUI

/// 기기 한 줄: 종류 아이콘, 이름, 상태, 앱 설치 버튼(파일 패널)과 드롭, 켜기·끄기 버튼,
/// 기기 작업 메뉴(… 버튼과 컨텍스트 메뉴: 초기화·삭제).
/// 쓸 수 없는 기기는 흐리게 그리고 이유를 보인다. 막힌 메뉴 항목은 비활성으로 두고 이유를 메뉴 맨 위에 보인다.
struct DeviceRow: View {
  let device: VirtualDevice
  /// 이 기기에서 진행 중인 작업. nil 이면 없다.
  let task: DeviceTask?
  let installTapped: () -> Void
  let appDropped: ([URL]) -> Void
  let bootTapped: () -> Void
  let shutdownTapped: () -> Void
  let eraseTapped: () -> Void
  let deleteTapped: () -> Void
  /// 끌어다 놓는 항목이 이 줄 위에 있고 설치할 수 있다 (줄을 강조한다).
  @State private var isDropTargeted = false

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
      Button(LauncherText.installAppButton, action: self.installTapped)
        .disabled(!self.canInstall)
        .help(self.installBlockReason ?? LauncherText.installAppHelp)
      self.action
      Menu {
        self.menuItems
      } label: {
        Label(LauncherText.deviceActionsMenu, systemImage: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .disabled(self.isBusy)
      .help(self.blockReason ?? LauncherText.deviceActionsMenu)
    }
    .padding(.vertical, 4)
    .foregroundStyle(self.isAvailable ? .primary : .secondary)
    .listRowBackground(self.isDropTargeted ? Color.accentColor.opacity(0.15) : nil)
    .dropDestination(for: URL.self) { urls, _ in
      guard self.canInstall else { return false }
      self.appDropped(urls)
      return true
    } isTargeted: { isTargeted in
      self.isDropTargeted = isTargeted && self.canInstall
    }
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
    Button(LauncherText.eraseMenuItem, action: self.eraseTapped)
      .disabled(self.device.eraseAvailability != .allowed)
    Button(LauncherText.deleteMenuItem, role: .destructive, action: self.deleteTapped)
      .disabled(self.device.deleteAvailability != .allowed)
  }

  /// 메뉴 맨 위에 보일 이유. 켜져 있으면 삭제·초기화 모두, 쓸 수 없으면 초기화가 막힌다.
  private var blockReason: String? {
    if case .blocked(.notShutdown) = self.device.deleteAvailability {
      return LauncherText.blockReason(.notShutdown)
    }
    if case .blocked(.unavailable) = self.device.eraseAvailability {
      return LauncherText.blockReason(.unavailable)
    }
    return nil
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

  private var isBusy: Bool {
    self.task != nil
  }

  /// 앱 설치 버튼·드롭을 받을 수 있다: 진행 중인 작업이 없고 설치할 수 있는 기기다.
  private var canInstall: Bool {
    !self.isBusy && self.device.appInstallAvailability == .allowed
  }

  /// 앱 설치 버튼 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var installBlockReason: String? {
    guard case let .blocked(reason) = self.device.appInstallAvailability else { return nil }
    return LauncherText.installBlockReason(reason)
  }

  private var isAvailable: Bool {
    self.device.availability == .available
  }

  private var statusText: String {
    if self.task == .installApp {
      return LauncherText.installingLabel
    }
    return self.isAvailable ? LauncherText.stateLabel(for: self.device.state) : LauncherText.unavailableLabel
  }

  private var iconName: String {
    switch self.device.family {
    case .phone: "iphone"
    case .tablet: "ipad"
    case .watch, .tv, .vision, .other: "questionmark.square.dashed"
    }
  }
}
