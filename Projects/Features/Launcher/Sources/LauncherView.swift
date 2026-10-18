import Core
import SwiftUI

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
/// 화면 문자열은 `LauncherText` 가 이 모듈의 `Localizable.xcstrings` 에서 찾는다.
public struct LauncherView: View {
  let model: LauncherModel

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
        LauncherText.title(for: self.model.notice),
        isPresented: Binding(
          get: { self.model.notice != nil },
          set: { isPresented in
            if !isPresented {
              self.model.noticeDismissed()
            }
          }
        ),
        // 닫히는 동안 notice 가 nil 이 돼도 본문이 비지 않도록 보여 줄 때의 값을 쓴다.
        presenting: self.model.notice
      ) { _ in
        Button(LauncherText.okButton) {}
      } message: { notice in
        Text(LauncherText.message(for: notice))
      }
      .task { await self.model.onAppear() }
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
