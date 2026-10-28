import AndroidEmulatorInterface
import Core
import Foundation

/// 화면 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// 기기 표시 이름·API 값·시스템 이미지 태그·경로는 번역하지 않는 값이라 `%@` 자리에 그대로 넣는다.
/// 케이스를 기본값 없이 모두 적어, 상태·오류가 늘면 컴파일러가 잡는다. 에러 본문·행 이유는 `AndroidDevicesText+Error.swift`, 확인 대화상자·만들기 시트는
/// `AndroidDevicesText+Dialogs.swift`.
enum AndroidDevicesText {
  // MARK: - 기기 라벨

  /// `“표시 이름” (API 37.0)`. 이미지 정보가 없으면 `“표시 이름”`.
  static func label(_ device: AndroidDeviceLabel) -> String {
    guard let api = device.apiLabel else {
      return String(localized: "“\(device.name)”", bundle: .module)
    }
    return String(localized: "“\(device.name)” (API \(api))", bundle: .module)
  }

  /// 행의 API 글자 "API 37.0".
  static func apiLabel(_ image: AndroidSystemImageRef) -> String {
    String(localized: "API \(image.apiLabel)", bundle: .module)
  }

  // MARK: - 알림

  /// 알림 제목. 알림이 없으면 빈 문자열 (알림을 띄우기 전, 표시되지 않는 `.alert` 가 읽는다).
  static func title(for notice: AndroidDevicesNotice?) -> String {
    switch notice {
    case .none:
      return ""
    case .refreshFailed:
      return String(localized: "기기 목록을 새로 고치지 못했습니다", bundle: .module)
    case let .bootFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기를 켜지 못했습니다", bundle: .module)
    case let .shutdownFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기를 끄지 못했습니다", bundle: .module)
    case .createFailed:
      return String(localized: "기기를 만들지 못했습니다", bundle: .module)
    case let .deleteFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기를 삭제하지 못했습니다", bundle: .module)
    case let .eraseFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기를 초기화하지 못했습니다", bundle: .module)
    case let .folderKept(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기를 목록에서 지웠습니다", bundle: .module)
    case let .batchBootFinished(report):
      return self.batchTitle(for: report)
    }
  }

  /// 알림 본문: 원인과 다음 할 일. 취소는 알림을 쌓지 않아 오지 않는다 (와도 빈 문자열).
  static func message(for notice: AndroidDevicesNotice) -> String {
    switch notice {
    case let .refreshFailed(error), let .bootFailed(_, error), let .shutdownFailed(_, error),
         let .createFailed(_, error), let .deleteFailed(_, error), let .eraseFailed(_, error):
      return self.message(for: error) ?? ""
    case let .folderKept(_, folder):
      let path = self.path(folder)
      return String(localized: "기기 폴더가 예상한 위치가 아니어서 지우지 않고 남겨 두었습니다: \(path)", bundle: .module)
    case let .batchBootFinished(report):
      return self.batchMessage(for: report)
    }
  }

  static var okButton: String {
    String(localized: "확인", bundle: .module)
  }

  /// 화면에 보일 폴더 경로. 디렉터리 URL 의 끝 `/` 를 뗀다.
  static func path(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    guard path.count > 1, path.hasSuffix("/") else { return path }
    return String(path.dropLast())
  }

  // MARK: - 함께 켜기

  static var bootSelectionButton: String {
    String(localized: "선택한 기기 켜기", bundle: .module)
  }

  /// 고른 기기가 없을 때 켜기 버튼 툴팁: 다중 선택 방법을 안내한다.
  static var selectionGuide: String {
    String(
      localized: "목록에서 기기를 고르세요. ⌘ 키를 누른 채 클릭하면 여러 대를, ⇧ 키를 누른 채 클릭하면 사이의 기기를 함께 고릅니다.",
      bundle: .module
    )
  }

  static var bootSelectionHelp: String {
    String(localized: "고른 기기 중 꺼진 기기를 함께 켭니다.", bundle: .module)
  }

  static var bootSelectionUnavailable: String {
    String(localized: "고른 기기 중 켤 수 있는 꺼진 기기가 없습니다.", bundle: .module)
  }

  /// 결과 알림 제목: 켠 기기가 있으면 몇 대 중 몇 대, 없으면 모두 실패.
  static func batchTitle(for report: AndroidBatchBootReport) -> String {
    let total = report.entries.count
    let succeeded = report.successCount
    guard succeeded > 0 else {
      return String(localized: "기기 \(total)대를 켜지 못했습니다", bundle: .module)
    }
    return String(localized: "기기 \(total)대 중 \(succeeded)대를 켰습니다", bundle: .module)
  }

  /// 결과 알림 본문: 같은 결과의 기기를 한 줄로 묶어(처음 나온 순서) 빈 줄로 잇는다.
  static func batchMessage(for report: AndroidBatchBootReport) -> String {
    var groups: [(error: AndroidEmulatorError?, devices: [AndroidDeviceLabel])] = []
    for entry in report.entries {
      if let index = groups.firstIndex(where: { $0.error == entry.error }) {
        groups[index].devices.append(entry.device)
      } else {
        groups.append((entry.error, [entry.device]))
      }
    }
    return groups.map { self.batchLine($0.error, devices: $0.devices.map(self.label).joined(separator: ", ")) }
      .joined(separator: "\n\n")
  }

  /// 결과 한 줄. `devices` 는 라벨을 `, ` 로 이은 이름이다.
  private static func batchLine(_ error: AndroidEmulatorError?, devices: String) -> String {
    guard let error else {
      return String(localized: "\(devices): 켰습니다.", bundle: .module)
    }
    guard let reason = self.message(for: error) else {
      return String(localized: "\(devices): 켜지 못했습니다.", bundle: .module)
    }
    return String(localized: "\(devices): 켜지 못했습니다. \(reason)", bundle: .module)
  }

  // MARK: - 툴바·목록 전체

  static var createDeviceButton: String {
    String(localized: "기기 만들기", bundle: .module)
  }

  static var refreshButton: String {
    String(localized: "새로 고침", bundle: .module)
  }

  /// 툴바의 Android 도구 화면 버튼. 오류 문구가 "오른쪽 위 Android 도구" 로 이 버튼을 가리킨다.
  static var setupButton: String {
    String(localized: "Android 도구", bundle: .module)
  }

  static var setupButtonHelp: String {
    String(localized: "Android 도구(platform-tools·emulator·시스템 이미지) 상태와 설치를 확인합니다", bundle: .module)
  }

  /// 빈 화면·안내 줄·목록 읽기 실패 화면의 Android 도구 화면 버튼.
  static var openSetupButton: String {
    String(localized: "Android 도구 열기", bundle: .module)
  }

  static var creatingLabel: String {
    String(localized: "기기를 만드는 중…", bundle: .module)
  }

  static var loading: String {
    String(localized: "기기 목록을 불러오는 중…", bundle: .module)
  }

  static var loadFailedTitle: String {
    String(localized: "기기 목록을 불러오지 못했습니다", bundle: .module)
  }

  static var retryButton: String {
    String(localized: "다시 시도", bundle: .module)
  }

  static var emptyTitle: String {
    String(localized: "Android 기기가 없습니다", bundle: .module)
  }

  static var emptyMessage: String {
    String(localized: "오른쪽 위 + 로 기기를 만드세요.", bundle: .module)
  }

  static var noImageTitle: String {
    String(localized: "만들 수 있는 시스템 이미지가 없습니다", bundle: .module)
  }

  static var noImageMessage: String {
    String(localized: "오른쪽 위 Android 도구에서 시스템 이미지를 설치하세요.", bundle: .module)
  }

  /// 기기는 있지만 만들 이미지가 없을 때 목록 위 안내 줄 (툴바 + 가 비활성인 이유).
  static var createUnavailableNotice: String {
    String(
      localized: "만들 수 있는 시스템 이미지가 없어 새 기기를 만들 수 없습니다. 오른쪽 위 Android 도구에서 시스템 이미지를 설치하세요.",
      bundle: .module
    )
  }

  // MARK: - 기기 행

  static func stateLabel(for state: AndroidVirtualDevice.State) -> String {
    switch state {
    case .shutdown:
      String(localized: "꺼짐", bundle: .module)
    case .booting:
      String(localized: "켜는 중", bundle: .module)
    case .booted:
      String(localized: "켜짐", bundle: .module)
    }
  }

  /// 앱이 진행 중인 작업의 상태 글자.
  static func taskLabel(for task: AndroidDeviceTask) -> String {
    switch task {
    case .boot:
      String(localized: "켜는 중", bundle: .module)
    case .shutdown:
      String(localized: "끄는 중", bundle: .module)
    case .delete:
      String(localized: "삭제하는 중", bundle: .module)
    case .erase:
      String(localized: "초기화하는 중", bundle: .module)
    }
  }

  static var unavailableLabel: String {
    String(localized: "사용할 수 없음", bundle: .module)
  }

  /// 앱이 켜는 중인 행의 상태 줄 안내 (진행 표시 도움말에도 쓴다).
  static var bootingHelp: String {
    String(localized: "처음 켤 때는 몇 분 걸릴 수 있습니다.", bundle: .module)
  }

  static var bootButton: String {
    String(localized: "켜기", bundle: .module)
  }

  static var shutdownButton: String {
    String(localized: "끄기", bundle: .module)
  }

  static var deviceActionsMenu: String {
    String(localized: "기기 작업", bundle: .module)
  }

  static var eraseMenuItem: String {
    String(localized: "초기화…", bundle: .module)
  }

  static var deleteMenuItem: String {
    String(localized: "삭제…", bundle: .module)
  }

  /// 기기 작업 메뉴 항목이 막힌 이유.
  static func blockReason(_ reason: DeviceActionBlockReason) -> String {
    switch reason {
    case .notShutdown:
      String(localized: "삭제·초기화는 기기를 끈 뒤에 할 수 있습니다", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기는 초기화할 수 없고 삭제만 할 수 있습니다", bundle: .module)
    }
  }
}
