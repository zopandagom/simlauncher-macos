import Core

// 상태를 바꾸지 않는 읽기 API. `private(set)` 은 쓰기만 막으므로 다른 파일의 extension 에 둘 수 있다
// (Model 상태를 직접 바꾸는 흐름은 `AndroidDevicesModel.swift` 에 둔다).
public extension AndroidDevicesModel {
  /// + 버튼을 누를 수 있는지: 목록을 읽었고, 선택지에 이미지가 있고, 만드는 중이 아니고, 시트·확인 대화상자가 없다.
  var canCreateDevice: Bool {
    guard case .loaded = self.listState else { return false }
    return !self.creationOptions.isEmpty && !self.isCreating && !self.hasPresentedSheet
  }

  /// 앱 실행·링크 열기 시트를 열 수 있는 기기: 목록에 있고, 그 작업(`.launchApp`·`.openURL`)을 시작할 수 있고(켜짐·쓸 수
  /// 있음·작업 없음), 만들기 시트·확인 대화상자가 없다. 아니면 nil. App 이 `AndroidAppSheetsModel` 의 `target` 으로 잇는다
  /// (그 Model 이 자기 두 시트를 따로 본다).
  func appSheetTarget(_ id: AndroidVirtualDevice.ID, for task: AndroidDeviceTask) -> AndroidVirtualDevice? {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.canStart(task, on: device),
          self.creationDraft == nil,
          self.confirmation == nil
    else { return nil }
    return device
  }

  /// 목록을 읽었지만 만들 수 있는 시스템 이미지가 없어 + 버튼을 쓸 수 없다. 기기가 있으면 목록 위 안내 줄로 이유와
  /// "Android 도구 열기" 버튼을 보인다 (목록이 비면 빈 화면 안내가 보인다).
  var isCreationUnavailable: Bool {
    guard case .loaded = self.listState else { return false }
    return self.creationOptions.isEmpty
  }

  /// 닫지 않은 알림. 쌓인 순서이고, 화면은 첫 항목을 보인다.
  var notices: [AndroidDevicesNoticeItem] {
    self.noticeQueue.items
  }

  /// 고른 기기 (지금 목록 순서). 목록이 없으면 빈 배열.
  var selectedDevices: [AndroidVirtualDevice] {
    guard case let .loaded(list) = self.listState else { return [] }
    return list.devices.filter { self.selection.contains($0.id) }
  }

  /// 고른 기기 중 하나라도 켤 수 있다 (툴바 "선택한 기기 켜기").
  var canBootSelection: Bool {
    self.selectedDevices.contains { self.activity.canStart(.boot, on: $0) }
  }
}

extension AndroidDevicesModel {
  /// 목록에 앱 작업 없이 켜는 중인 기기가 있다 (자동 다시 읽기를 이어 가는 조건).
  var hasBootingDeviceWithoutTask: Bool {
    guard case let .loaded(list) = self.listState else { return false }
    return list.devices.contains { $0.state == .booting && self.activity.task(on: $0.id) == nil }
  }
}
