import Core
import SwiftUI

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
/// 화면 문자열은 `LauncherText` 가 이 모듈의 `Localizable.xcstrings` 에서 찾는다.
public struct LauncherView: View {
  let model: LauncherModel
  /// 지금 띄운 알림. 닫히는 동안 Model 의 줄에서 빠져도 글자가 비지 않도록 View 가 들고 있는다.
  @State private var presentedNotice: LauncherNoticeItem?
  /// 알림을 띄웠는지. 다음 알림을 띄울 때 false → true 전이가 생기도록 Model 의 줄과 따로 둔다.
  @State private var isNoticePresented = false

  public init(model: LauncherModel) {
    self.model = model
  }

  public var body: some View {
    self.content
      .toolbar {
        ToolbarItem {
          if self.model.isRefreshing {
            ProgressView()
              .controlSize(.small)
          }
        }
        ToolbarItem {
          Button {
            Task { await self.model.refreshButtonTapped() }
          } label: {
            Label(LauncherText.refreshButton, systemImage: "arrow.clockwise")
          }
          .disabled(self.model.isRefreshing)
        }
      }
      .alert(
        LauncherText.title(for: self.presentedNotice?.notice),
        isPresented: Binding(
          get: { self.isNoticePresented },
          set: { isPresented in
            self.isNoticePresented = isPresented
            if !isPresented, let id = self.presentedNotice?.id {
              self.model.noticeDismissed(id)
            }
          }
        ),
        presenting: self.presentedNotice
      ) { _ in
        Button(LauncherText.okButton) {}
      } message: { item in
        Text(LauncherText.message(for: item.notice))
      }
      // 줄의 첫 알림이 바뀌면(새로 쌓임, 앞 알림을 닫음) 그것을 띄운다. 떠 있는 동안 쌓인 알림은 첫 항목이 그대로라
      // 기다렸다가, 앞 알림을 닫으면 차례로 뜬다.
      .onChange(of: self.model.notices.first?.id, initial: true) { _, _ in
        self.showFirstNotice()
      }
      .task { await self.model.onAppear() }
  }

  /// 앞 알림의 닫기 처리가 끝난 뒤 false → true 전이가 생기도록 다음 실행 차례에 띄운다.
  private func showFirstNotice() {
    guard let next = self.model.notices.first else {
      self.isNoticePresented = false
      return
    }
    Task { @MainActor in
      // 그 사이 닫혔거나 다른 알림이 첫 항목이 됐으면 그쪽의 onChange 가 띄운다.
      guard self.model.notices.first?.id == next.id else { return }
      self.presentedNotice = next
      self.isNoticePresented = true
    }
  }

  @ViewBuilder
  private var content: some View {
    switch self.model.listState {
    case .loading:
      ProgressView {
        Text(LauncherText.loading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case let .failed(error):
      ContentUnavailableView {
        Label(LauncherText.loadFailedTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(LauncherText.message(for: error))
      } actions: {
        Button(LauncherText.retryButton) {
          Task { await self.model.refreshButtonTapped() }
        }
        .disabled(self.model.isRefreshing)
      }
    case let .loaded(list):
      if let reason = list.emptyReason {
        ContentUnavailableView {
          Label(LauncherText.emptyTitle(for: reason), systemImage: "iphone.slash")
        } description: {
          Text(LauncherText.emptyMessage(for: reason))
        } actions: {
          Button(LauncherText.refreshButton) {
            Task { await self.model.refreshButtonTapped() }
          }
          .disabled(self.model.isRefreshing)
        }
      } else {
        self.deviceList(list)
      }
    }
  }

  private func deviceList(_ list: DeviceList) -> some View {
    List {
      ForEach(list.sections) { section in
        Section {
          ForEach(section.devices) { device in
            DeviceRow(
              device: device,
              isBusy: self.model.busyDeviceIDs.contains(device.id),
              bootTapped: {
                Task { await self.model.bootButtonTapped(device.id) }
              },
              shutdownTapped: {
                Task { await self.model.shutdownButtonTapped(device.id) }
              }
            )
          }
        } header: {
          Text(verbatim: section.runtime.name)
        }
      }
    }
  }
}
