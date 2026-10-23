import Core
import SwiftUI
import UniformTypeIdentifiers

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
/// 화면 문자열은 `LauncherText` 가 이 모듈의 `Localizable.xcstrings` 에서 찾는다.
public struct LauncherView: View {
  let model: LauncherModel
  /// 카탈로그에서 설치 시트. 기기 목록 상태를 함께 쓰지 않아 따로 둔 Model 이다 (App 이 소유한다).
  let catalogModel: CatalogInstallModel
  /// 지금 띄운 알림. 닫히는 동안 Model 의 줄에서 빠져도 글자가 비지 않도록 View 가 들고 있는다.
  @State private var presentedNotice: LauncherNoticeItem?
  /// 알림을 띄웠는지. 다음 알림을 띄울 때 false → true 전이가 생기도록 Model 의 줄과 따로 둔다.
  @State private var isNoticePresented = false
  /// 마지막으로 띄운 삭제·초기화 확인. 닫히는 동안 Model 값이 nil 이어도 제목이 비지 않도록 View 가 들고 있는다.
  @State private var presentedConfirmation: DeviceConfirmation?
  /// 앱 설치 메뉴에서 "파일에서 고르기…" 를 고른 기기. 파일 패널이 닫힌 뒤 완료 처리에서 읽으므로 패널 표시 여부와 따로 둔다.
  @State private var importDeviceID: VirtualDevice.ID?
  @State private var isImporterPresented = false

  public init(model: LauncherModel, catalogModel: CatalogInstallModel) {
    self.model = model
    self.catalogModel = catalogModel
  }

  public var body: some View {
    self.content
      .toolbar {
        ToolbarItem {
          if self.model.isRefreshing || self.model.isCreating {
            HStack(spacing: 6) {
              ProgressView()
                .controlSize(.small)
              if self.model.isCreating {
                Text(LauncherText.creatingLabel)
              }
            }
          }
        }
        ToolbarItem {
          Button {
            self.model.createButtonTapped()
          } label: {
            Label(LauncherText.createDeviceButton, systemImage: "plus")
          }
          .disabled(!self.model.canCreateDevice)
          // 비활성 툴바 버튼에는 툴팁이 잘 뜨지 않아 보조로만 둔다. 이유는 글자로 보인다
          // (기기가 있으면 목록 위 안내 줄, 없으면 빈 화면 안내).
          .help(
            self.model.isCreationUnavailable ? LauncherText.createUnavailableNotice : LauncherText.createDeviceButton
          )
        }
        ToolbarItem {
          Button {
            Task { await self.model.refreshButtonTapped() }
          } label: {
            Label(LauncherText.refreshButton, systemImage: "arrow.clockwise")
          }
          .disabled(self.model.isRefreshing)
        }
        ToolbarItem {
          Button {
            self.model.setupButtonTapped()
          } label: {
            Label(LauncherText.setupButton, systemImage: "wrench.and.screwdriver")
          }
          // 오류 문구가 "오른쪽 위 개발 환경"으로 이 버튼을 가리키므로 글자를 함께 보인다.
          .labelStyle(.titleAndIcon)
          .help(LauncherText.setupButtonHelp)
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
      .sheet(
        isPresented: Binding(
          get: { self.model.createDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.model.createSheetDismissed()
            }
          }
        )
      ) {
        DeviceCreationSheet(model: self.model)
      }
      // 생성·링크·URL 설치·카탈로그 시트는 같은 체인에 둔다. 앞의 셋은 Model 이 둘 이상 함께 열리지 않게 막고, 카탈로그 시트는
      // 다른 Model 이라 시트가 창을 막는 모달과 행 메뉴의 비활성에 기댄다.
      .sheet(
        isPresented: Binding(
          get: { self.model.openURLDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.model.openURLSheetDismissed()
            }
          }
        )
      ) {
        OpenURLSheet(model: self.model)
      }
      .sheet(
        isPresented: Binding(
          get: { self.model.installURLDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.model.installURLSheetDismissed()
            }
          }
        )
      ) {
        InstallURLSheet(model: self.model)
      }
      .sheet(
        isPresented: Binding(
          get: { self.catalogModel.draft != nil },
          set: { isPresented in
            if !isPresented {
              self.catalogModel.sheetDismissed()
            }
          }
        )
      ) {
        CatalogInstallSheet(model: self.catalogModel)
      }
      .confirmationDialog(
        LauncherText.confirmationTitle(for: self.model.pendingConfirmation ?? self.presentedConfirmation),
        isPresented: Binding(
          get: { self.model.pendingConfirmation != nil },
          set: { isPresented in
            if !isPresented {
              self.model.confirmationDismissed()
            }
          }
        ),
        titleVisibility: .visible,
        // 여는 첫 렌더는 Model 값, 닫히는 동안은 들고 있던 값.
        presenting: self.model.pendingConfirmation ?? self.presentedConfirmation
      ) { confirmation in
        Button(LauncherText.confirmButton(for: confirmation.action), role: .destructive) {
          // 버튼 동작 뒤 SwiftUI 가 곧바로 confirmationDismissed() 를 부르므로 값을 넘긴다.
          Task { await self.model.confirmationConfirmed(confirmation) }
        }
        Button(LauncherText.cancelButton, role: .cancel) {
          self.model.confirmationDismissed()
        }
      } message: { confirmation in
        Text(LauncherText.confirmationMessage(for: confirmation.action))
      }
      .onChange(of: self.model.pendingConfirmation, initial: true) { _, new in
        if let new {
          self.presentedConfirmation = new
        }
      }
      // 목록 단위에 하나만 둔다 (같은 계층에 여러 fileImporter 를 두면 서로 충돌한다).
      // zip 은 Model 이 풀어 설치한다. .ipa 도 고를 수 있게 한다: 골라야 설치할 수 없는 이유를 보일 수 있다.
      .fileImporter(
        isPresented: self.$isImporterPresented,
        allowedContentTypes: [.applicationBundle, .zip] + [UTType("com.apple.itunes.ipa")].compactMap(\.self)
      ) { result in
        // 취소·실패는 무시한다.
        if case let .success(url) = result, let id = self.importDeviceID {
          Task { await self.model.appFileSelected(url, for: id) }
        }
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
        // 읽기 실패는 대개 Xcode 준비 문제라 Setup 화면으로 가는 길을 함께 둔다.
        Button(LauncherText.openSetupButton) {
          self.model.setupButtonTapped()
        }
      }
    case let .loaded(list):
      if let reason = list.emptyReason {
        ContentUnavailableView {
          Label(LauncherText.emptyTitle(for: reason), systemImage: "iphone.slash")
        } description: {
          Text(LauncherText.emptyMessage(for: reason))
        } actions: {
          if reason == .noDevices {
            Button(LauncherText.createDeviceButton) {
              self.model.createButtonTapped()
            }
            .disabled(!self.model.canCreateDevice)
          }
          if let install = LauncherText.installButton(for: reason) {
            Button(install) {
              self.model.setupButtonTapped()
            }
            .buttonStyle(.borderedProminent)
          }
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
}

// MARK: - 기기 목록

extension LauncherView {
  private func deviceList(_ list: DeviceList) -> some View {
    self.deviceRows(list)
      .safeAreaInset(edge: .top, spacing: 0) {
        if self.model.isCreationUnavailable {
          self.createUnavailableNotice
        }
      }
  }

  /// 기기는 있지만 만들 수 있는 종류가 없을 때 목록 위에 고정해 보이는 안내 줄 (툴바 + 가 비활성인 이유)과,
  /// 해결책 하나인 "다른 iOS 버전 설치" 버튼 (Setup 화면의 iOS 시뮬레이터 설치 단계를 연다).
  /// 목록이 비어 있으면 빈 화면 안내가 같은 이유와 버튼을 보이므로 목록이 있을 때만 쓴다.
  private var createUnavailableNotice: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Label {
          Text(LauncherText.createUnavailableNotice)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        if let install = LauncherText.installButton(for: .noCreatableDeviceType) {
          Button(install) {
            self.model.setupButtonTapped()
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      Divider()
    }
    .background(.bar)
  }

  private func deviceRows(_ list: DeviceList) -> some View {
    List {
      ForEach(list.sections) { section in
        Section {
          ForEach(section.devices) { device in
            DeviceRow(
              device: device,
              task: self.model.activity.task(on: device.id),
              downloadStage: self.model.activity.downloadStage(on: device.id),
              installFromFileTapped: {
                self.importDeviceID = device.id
                self.isImporterPresented = true
              },
              installFromURLTapped: {
                self.model.installFromURLMenuTapped(device.id)
              },
              installFromCatalogTapped: {
                Task { await self.catalogModel.menuTapped(device) }
              },
              cancelDownloadTapped: {
                self.model.downloadCancelTapped(device.id)
              },
              appDropped: { urls in
                Task { await self.model.appDropped(urls, on: device.id) }
              },
              openURLTapped: {
                self.model.openURLButtonTapped(device.id)
              },
              bootTapped: {
                Task { await self.model.bootButtonTapped(device.id) }
              },
              shutdownTapped: {
                Task { await self.model.shutdownButtonTapped(device.id) }
              },
              eraseTapped: {
                self.model.eraseButtonTapped(device.id)
              },
              deleteTapped: {
                self.model.deleteButtonTapped(device.id)
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
