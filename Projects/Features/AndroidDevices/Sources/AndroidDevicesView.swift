import AppKit
import Core
import SwiftUI
import UniformTypeIdentifiers

/// 상태를 읽어 그리기만 하고, 사용자 동작은 Model 의 이벤트 메서드로 넘긴다.
/// 화면 문자열은 `AndroidDevicesText` 가 이 모듈의 `Localizable.xcstrings` 에서 찾는다.
/// 목록은 ⌘·⇧ 클릭으로 여러 기기를 고를 수 있고(선택은 Model 상태), 툴바의 "선택한 기기 켜기" 가 고른 기기를 함께 켠다.
/// 행의 버튼·메뉴·드롭(스크린샷·녹화 포함)은 그 행 한 대에만 동작한다. 사라질 때(`onDisappear`) 자동 다시 읽기를 멈추게 알린다.
/// 행의 URL·카탈로그 시트는 `downloadModel`, 앱 실행·링크 열기 시트는 `appSheetsModel`(둘 다 App 소유)의 초안으로 띄운다.
public struct AndroidDevicesView: View {
  let model: AndroidDevicesModel
  let downloadModel: AndroidDownloadInstallModel
  let appSheetsModel: AndroidAppSheetsModel
  /// 지금 띄운 알림. 닫히는 동안 Model 의 줄에서 빠져도 글자가 비지 않도록 View 가 들고 있는다.
  @State private var presentedNotice: AndroidDevicesNoticeItem?
  /// 알림을 띄웠는지. 다음 알림을 띄울 때 false → true 전이가 생기도록 Model 의 줄과 따로 둔다.
  @State private var isNoticePresented = false
  /// 마지막으로 띄운 삭제·초기화 확인. 닫히는 동안 Model 값이 nil 이어도 제목이 비지 않도록 View 가 들고 있는다.
  @State private var presentedConfirmation: AndroidDeviceConfirmation?
  /// "파일에서 고르기…" 를 고른 행의 기기. 파일 패널이 닫힌 뒤 완료 처리에서 읽으므로 패널 표시 여부와 따로 둔다.
  @State private var importTarget: AndroidVirtualDevice.ID?
  @State private var isImporterPresented = false

  public init(
    model: AndroidDevicesModel,
    downloadModel: AndroidDownloadInstallModel,
    appSheetsModel: AndroidAppSheetsModel
  ) {
    self.model = model
    self.downloadModel = downloadModel
    self.appSheetsModel = appSheetsModel
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
                Text(AndroidDevicesText.creatingLabel)
              }
            }
          }
        }
        ToolbarItem {
          self.bootSelectionButton
        }
        ToolbarItem {
          Button {
            self.model.createButtonTapped()
          } label: {
            Label(AndroidDevicesText.createDeviceButton, systemImage: "plus")
          }
          .disabled(!self.model.canCreateDevice)
          // 비활성 툴바 버튼에는 툴팁이 잘 뜨지 않아 보조로만 둔다. 이유는 글자로 보인다
          // (기기가 있으면 목록 위 안내 줄, 없으면 빈 화면 안내).
          .help(
            self.model.isCreationUnavailable
              ? AndroidDevicesText.createUnavailableNotice : AndroidDevicesText.createDeviceButton
          )
        }
        ToolbarItem {
          Button {
            Task { await self.model.refreshButtonTapped() }
          } label: {
            Label(AndroidDevicesText.refreshButton, systemImage: "arrow.clockwise")
          }
          .disabled(self.model.isRefreshing)
        }
        ToolbarItem {
          Button {
            self.model.setupButtonTapped()
          } label: {
            Label(AndroidDevicesText.setupButton, systemImage: "wrench.and.screwdriver")
          }
          // 오류 문구가 "오른쪽 위 Android 도구"로 이 버튼을 가리키므로 글자를 함께 보인다.
          .labelStyle(.titleAndIcon)
          .help(AndroidDevicesText.setupButtonHelp)
        }
      }
      .alert(
        AndroidDevicesText.title(for: self.presentedNotice?.notice),
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
        Button(AndroidDevicesText.okButton) {}
      } message: { item in
        Text(AndroidDevicesText.message(for: item.notice))
      }
      // 줄의 첫 알림이 바뀌면(새로 쌓임, 앞 알림을 닫음) 그것을 띄운다. 떠 있는 동안 쌓인 알림은 첫 항목이 그대로라
      // 기다렸다가, 앞 알림을 닫으면 차례로 뜬다.
      .onChange(of: self.model.notices.first?.id, initial: true) { _, _ in
        self.showFirstNotice()
      }
      .sheet(
        isPresented: Binding(
          get: { self.model.creationDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.model.creationSheetDismissed()
            }
          }
        )
      ) {
        AndroidDeviceCreationSheet(model: self.model)
      }
      // 만들기·앱 실행·링크 시트는 같은 체인에 두고, 두 Model(App 이 잇는다)이 둘 이상 함께 열리지 않게 막는다.
      .sheet(
        isPresented: Binding(
          get: { self.appSheetsModel.launchAppDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.appSheetsModel.launchAppSheetDismissed()
            }
          }
        )
      ) {
        AndroidLaunchAppSheet(model: self.appSheetsModel)
      }
      .sheet(
        isPresented: Binding(
          get: { self.appSheetsModel.openURLDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.appSheetsModel.openURLSheetDismissed()
            }
          }
        )
      ) {
        AndroidOpenURLSheet(model: self.appSheetsModel)
      }
      .modifier(AndroidDownloadSheets(model: self.downloadModel))
      .confirmationDialog(
        AndroidDevicesText.confirmationTitle(for: self.model.confirmation ?? self.presentedConfirmation),
        isPresented: Binding(
          get: { self.model.confirmation != nil },
          set: { isPresented in
            if !isPresented {
              self.model.confirmationCancelled()
            }
          }
        ),
        titleVisibility: .visible,
        // 여는 첫 렌더는 Model 값, 닫히는 동안은 들고 있던 값.
        presenting: self.model.confirmation ?? self.presentedConfirmation
      ) { confirmation in
        Button(AndroidDevicesText.confirmButton(for: confirmation.action), role: .destructive) {
          // 버튼 동작 뒤 SwiftUI 가 곧바로 confirmationCancelled() 를 부르므로 값을 넘긴다.
          Task { await self.model.confirmationConfirmTapped(confirmation) }
        }
        Button(AndroidDevicesText.cancelButton, role: .cancel) {
          self.model.confirmationCancelled()
        }
      } message: { confirmation in
        Text(AndroidDevicesText.confirmationMessage(for: confirmation.action))
      }
      .onChange(of: self.model.confirmation, initial: true) { _, new in
        if let new {
          self.presentedConfirmation = new
        }
      }
      // 목록 단위에 하나만 둔다 (같은 계층에 여러 fileImporter 를 두면 서로 충돌한다).
      // .aab 도 고를 수 있게 한다: 골라야 설치할 수 없는 이유를 보일 수 있다.
      .fileImporter(
        isPresented: self.$isImporterPresented,
        allowedContentTypes: [UTType(filenameExtension: "apk"), UTType(filenameExtension: "aab")].compactMap(\.self)
      ) { result in
        // 취소·실패는 무시한다.
        guard case let .success(url) = result, let id = self.importTarget else { return }
        Task { await self.model.appFileSelected(url, for: id) }
      }
      .task { await self.model.onAppear() }
      .onDisappear { self.model.viewDisappeared() }
      // macOS 에서는 다른 앱에 갔다 돌아와도 scenePhase 가 바뀌지 않아, 앱 활성화 알림으로 돌아옴을 안다
      // (에뮬레이터 창을 닫거나 Android Studio 에서 바꾼 것을 반영한다).
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        Task { await self.model.appBecameActive() }
      }
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
        Text(AndroidDevicesText.loading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case let .failed(error):
      ContentUnavailableView {
        Label(AndroidDevicesText.loadFailedTitle, systemImage: "exclamationmark.triangle")
      } description: {
        Text(AndroidDevicesText.message(for: error) ?? "")
      } actions: {
        Button(AndroidDevicesText.retryButton) {
          Task { await self.model.refreshButtonTapped() }
        }
        .disabled(self.model.isRefreshing)
        // 읽기 실패는 대개 Android 도구 문제라 도구 화면으로 가는 길을 함께 둔다.
        Button(AndroidDevicesText.openSetupButton) {
          self.model.setupButtonTapped()
        }
      }
    case let .loaded(list):
      if list.emptyReason != nil {
        self.emptyView
      } else {
        self.deviceList(list)
      }
    }
  }

  /// 기기가 없을 때. 만들 이미지가 없으면 도구 화면으로, 있으면 만들기로 안내한다.
  private var emptyView: some View {
    let noImage = self.model.isCreationUnavailable
    return ContentUnavailableView {
      Label(
        noImage ? AndroidDevicesText.noImageTitle : AndroidDevicesText.emptyTitle,
        systemImage: "smartphone"
      )
    } description: {
      Text(noImage ? AndroidDevicesText.noImageMessage : AndroidDevicesText.emptyMessage)
    } actions: {
      if noImage {
        Button(AndroidDevicesText.openSetupButton) {
          self.model.setupButtonTapped()
        }
        .buttonStyle(.borderedProminent)
      } else {
        Button(AndroidDevicesText.createDeviceButton) {
          self.model.createButtonTapped()
        }
        .disabled(!self.model.canCreateDevice)
      }
      Button(AndroidDevicesText.refreshButton) {
        Task { await self.model.refreshButtonTapped() }
      }
      .disabled(self.model.isRefreshing)
    }
  }
}

// MARK: - 기기 목록

extension AndroidDevicesView {
  private func deviceList(_ list: AndroidDeviceList) -> some View {
    // 선택은 `Binding(get:set:)` 으로 Model 의 이벤트에 잇는다 (클릭·⌘·⇧ 클릭·⌘A·빈 곳 클릭).
    List(selection: Binding(get: { self.model.selection }, set: { self.model.selectionChanged($0) })) {
      ForEach(list.devices) { device in
        self.deviceRow(device)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if self.model.isCreationUnavailable {
        self.createUnavailableNotice
      }
    }
  }

  /// 기기는 있지만 만들 이미지가 없을 때 목록 위에 고정해 보이는 안내 줄 (툴바 + 가 비활성인 이유)과 도구 화면 버튼.
  private var createUnavailableNotice: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Label {
          Text(AndroidDevicesText.createUnavailableNotice)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        Button(AndroidDevicesText.openSetupButton) {
          self.model.setupButtonTapped()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      Divider()
    }
    .background(.bar)
  }

  private func deviceRow(_ device: AndroidVirtualDevice) -> some View {
    let task = self.model.activity.task(on: device.id)
    return AndroidDeviceRow(
      device: device,
      task: task,
      downloadStage: self.model.activity.downloadStage(on: device.id),
      bootTapped: { Task { await self.model.bootTapped(device.id) } },
      shutdownTapped: { Task { await self.model.shutdownTapped(device.id) } },
      eraseTapped: { self.model.eraseTapped(device.id) },
      deleteTapped: { self.model.deleteTapped(device.id) },
      installFromFileTapped: {
        self.importTarget = device.id
        self.isImporterPresented = true
      },
      installFromURLTapped: {
        self.downloadModel.urlMenuTapped(device)
      },
      installFromCatalogTapped: {
        Task { await self.downloadModel.catalogMenuTapped(device) }
      },
      cancelDownloadTapped: {
        self.model.downloadCancelTapped(device.id)
      },
      appDropped: { urls in
        Task { await self.model.appDropped(urls, on: device.id) }
      },
      launchAppTapped: {
        Task { await self.appSheetsModel.launchAppTapped(device.id) }
      },
      openURLTapped: {
        self.appSheetsModel.openURLTapped(device.id)
      },
      canTakeScreenshot: self.model.screenshots.canStart(on: device, during: task),
      isTakingScreenshot: self.model.screenshots.isTaking(on: device.id),
      screenshotTapped: {
        Task { await self.model.screenshotTapped(device.id) }
      },
      recordingPhase: self.model.recordings.phase(on: device.id),
      canStartRecording: self.model.recordings.canStart(on: device, during: task),
      recordTapped: {
        Task { await self.model.recordTapped(device.id) }
      },
      stopRecordingTapped: {
        self.model.recordingStopTapped(device.id)
      }
    )
  }

  /// 켤 수 있는 기기가 없으면 비활성이다. 비활성 툴바 버튼에는 툴팁이 잘 뜨지 않아 툴팁은 보조다.
  private var bootSelectionButton: some View {
    Button {
      Task { await self.model.bootSelectedTapped() }
    } label: {
      Label(AndroidDevicesText.bootSelectionButton, systemImage: "power")
    }
    .labelStyle(.titleAndIcon)
    .disabled(!self.model.canBootSelection)
    .help(
      self.model.selectedDevices.isEmpty
        ? AndroidDevicesText.selectionGuide
        : self.model.canBootSelection
        ? AndroidDevicesText.bootSelectionHelp : AndroidDevicesText.bootSelectionUnavailable
    )
  }
}

/// 행 "URL 에서…"·"카탈로그에서…" 시트. `AndroidDownloadInstallModel` 이 둘이 함께 열리지 않게 막고, 기기 목록의 시트·확인
/// 대화상자와의 겹침은 모달 시트가 막는다. 닫기는 `Binding(get:set:)` 으로 Model 의 이벤트에 잇는다.
private struct AndroidDownloadSheets: ViewModifier {
  let model: AndroidDownloadInstallModel

  func body(content: Content) -> some View {
    content
      .sheet(
        isPresented: Binding(
          get: { self.model.urlDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.model.urlSheetDismissed()
            }
          }
        )
      ) {
        AndroidInstallURLSheet(model: self.model)
      }
      .sheet(
        isPresented: Binding(
          get: { self.model.catalogDraft != nil },
          set: { isPresented in
            if !isPresented {
              self.model.catalogSheetDismissed()
            }
          }
        )
      ) {
        AndroidCatalogInstallSheet(model: self.model)
      }
  }
}
