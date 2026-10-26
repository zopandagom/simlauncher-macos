import Core

// 상태를 바꾸지 않는 읽기 API. `private(set)` 은 쓰기만 막으므로 다른 파일의 extension 에 둘 수 있다
// (Model 상태를 직접 바꾸는 흐름은 `LauncherModel.swift` 에, Model 상태를 직접 바꾸지 않고(바꾸는 것은 창구로만)
// Client 를 잇는 앱 설치·기기 명령·화면 캡처 흐름은 Model 이 소유한
// `AppInstallFlow.swift`·`DeviceCommandFlow.swift`·`ScreenCaptureFlow.swift` 에 둔다).
public extension LauncherModel {
  /// + 버튼을 누를 수 있는지: 목록을 읽었고, 선택지가 있고, 만드는 중이 아니고, 생성·링크·URL 설치 시트가 닫혀 있다.
  var canCreateDevice: Bool {
    guard case .loaded = self.listState else { return false }
    let isSheetClosed = self.createDraft == nil && self.openURLDraft == nil && self.installURLDraft == nil
    return !self.creationOptions.isEmpty && !self.isCreating && isSheetClosed
  }

  /// 생성·링크 열기·URL 설치 시트나 삭제·초기화 확인 대화상자가 열려 있다.
  var isSheetOrDialogOpen: Bool {
    self.createDraft != nil || self.openURLDraft != nil || self.installURLDraft != nil || self
      .pendingConfirmation != nil
  }

  /// 목록을 읽었지만 만들 수 있는 기기 종류가 없어 + 버튼을 쓸 수 없다. 툴바 + 툴팁 문구를 고르고,
  /// 기기가 있으면 목록 위 안내 줄로 이유와 iOS 설치 버튼을 보인다 (목록이 비면 빈 화면 안내가 보인다).
  /// 만드는 중·시트 열림·읽는 중은 다른 표시가 이유를 보이므로 여기 들지 않는다.
  var isCreationUnavailable: Bool {
    guard case .loaded = self.listState else { return false }
    return self.creationOptions.isEmpty
  }

  /// 작업이 진행 중인 기기 (`activity.busyDeviceIDs` 와 같다). 화면은 행마다 `activity.task(on:)` 를 읽고,
  /// 이 값은 진행 중인 기기 전체를 한 번에 볼 때(테스트) 쓴다.
  var busyDeviceIDs: Set<VirtualDevice.ID> {
    self.activity.busyDeviceIDs
  }

  /// 닫지 않은 알림. 쌓인 순서이고, 화면은 첫 항목을 보인다. `noticeQueue` 에서 계산하는 읽기 API 다.
  var notices: [LauncherNoticeItem] {
    self.noticeQueue.items
  }

  /// 어느 기기든 녹화 중이다 (시작 중·저장 중 포함, `recordings.isActive`). App 의 앱 종료 확인이 읽는다.
  var isRecording: Bool {
    self.recordings.isActive
  }

  /// 고른 기기 (지금 목록 순서: 섹션 → 행). 목록이 없으면 빈 배열.
  var selectedDevices: [VirtualDevice] {
    guard case let .loaded(list) = self.listState else { return [] }
    return list.sections.flatMap(\.devices).filter { self.selection.contains($0.id) }
  }

  /// 고른 기기 중 하나라도 앱 설치를 시작할 수 있다 (툴바 설치 메뉴 항목).
  var canInstallOnSelection: Bool {
    self.selectedDevices.contains { self.activity.canStart(.installApp, on: $0) }
  }

  /// 고른 기기 중 하나라도 켤 수 있다 (툴바 "선택한 기기 켜기").
  var canBootSelection: Bool {
    self.selectedDevices.contains { self.activity.canStart(.boot, on: $0) }
  }
}
