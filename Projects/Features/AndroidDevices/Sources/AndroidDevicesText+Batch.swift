import AndroidEmulatorInterface
import Core
import Foundation

/// 여러 기기 설치 문구 (툴바 "선택한 기기에 앱 설치", 대상이 여러 대인 시트, 받기 묶음, 결과 알림). 함께 켜기 문구는
/// `AndroidDevicesText.swift` 에 있다. iOS `LauncherText+Batch` 와 같은 키·값이고(꺼진 기기를 켜지 않아 "설치할 수 있는 기기가
/// 없다" 이유만 다르다), 기기 이름은 라벨(`“이름” (API 37.0)`)을 `, ` 로 이은 문자열을 한 자리(`%@`)에 넣는다 (`deviceNames(_:)`).
extension AndroidDevicesText {
  // MARK: - 툴바

  static var installOnSelectionMenu: String {
    String(localized: "선택한 기기에 앱 설치", bundle: .module)
  }

  /// 설치할 수 있는 기기가 있을 때 설치 메뉴 맨 위 글자와 툴팁. `count` 는 고른 기기 수 (설치할 수 없는 기기 포함).
  static func installOnSelectionHelp(count: Int) -> String {
    String(localized: "고른 기기 \(count)대에 앱을 설치하고 실행합니다. 설치할 수 없는 기기는 이유와 함께 건너뜁니다.", bundle: .module)
  }

  /// 고른 기기 중 설치할 수 있는 기기가 없을 때 설치 메뉴 맨 위 글자와 툴팁 (꺼진 기기는 켜고 설치하지 않는다).
  static var installOnSelectionUnavailable: String {
    String(
      localized: "고른 기기 중 앱을 설치할 수 있는 기기가 없습니다. 켜져 있지 않거나, 사용할 수 없거나, 다른 작업 중입니다.",
      bundle: .module
    )
  }

  // MARK: - 시트

  /// URL 에서 설치 시트 제목. 한 대면 행 메뉴와 같은 제목이다.
  static func installURLSheetTitle(for targets: [AndroidTargetDevice]) -> String {
    guard targets.count > 1 else {
      return targets.first.map { self.installURLSheetTitle(for: $0.label) } ?? ""
    }
    return String(localized: "기기 \(targets.count)대에 URL 에서 앱 설치", bundle: .module)
  }

  /// 카탈로그에서 설치 시트 제목. 한 대면 행 메뉴와 같은 제목이다.
  static func catalogSheetTitle(for targets: [AndroidTargetDevice]) -> String {
    guard targets.count > 1 else {
      return targets.first.map { self.catalogSheetTitle(for: $0.label) } ?? ""
    }
    return String(localized: "기기 \(targets.count)대에 카탈로그에서 앱 설치", bundle: .module)
  }

  /// 대상이 여러 대인 시트의 제목 아래 대상 줄. 한 대면 제목에 이름이 있으므로 nil.
  static func batchTargetsLine(_ targets: [AndroidTargetDevice]) -> String? {
    guard targets.count > 1 else { return nil }
    let names = self.deviceNames(targets.map(\.label))
    return String(localized: "대상: \(names)", bundle: .module)
  }

  // MARK: - 기기 행

  /// 받기 묶음에 든 행의 취소 버튼 툴팁. `count` 는 같은 묶음에서 받는 중인 기기 수 (2 이상).
  static func batchCancelDownloadHelp(count: Int) -> String {
    String(localized: "기기 \(count)대에 함께 받는 중입니다. 취소하면 모두 멈추고 받은 부분을 지웁니다.", bundle: .module)
  }

  // MARK: - 알림

  /// 여러 기기 설치 알림의 제목. `title(for:)` 가 두 케이스를 한 줄로 넘긴다 (그 밖의 알림이면 빈 문자열, 쓰이지 않는다).
  static func batchInstallNoticeTitle(for notice: AndroidDevicesNotice?) -> String {
    switch notice {
    case let .batchInstallFailed(devices, _):
      self.batchInstallFailedTitle(total: devices.count)
    case let .batchInstallFinished(report):
      self.batchInstallTitle(for: report)
    default:
      ""
    }
  }

  /// 여러 기기 설치 알림의 본문. 공통 단계(받기·검사) 실패는 한 기기 설치와 같은 원인 문구다.
  /// `message(for:)` 가 두 케이스를 넘긴다 (그 밖의 알림이면 빈 문자열, 쓰이지 않는다).
  static func batchInstallNoticeMessage(for notice: AndroidDevicesNotice) -> String {
    switch notice {
    case let .batchInstallFailed(_, failure):
      self.message(for: failure)
    case let .batchInstallFinished(report):
      self.batchInstallMessage(for: report)
    default:
      ""
    }
  }

  /// 결과 알림 제목: 설치한 기기가 있으면 몇 대 중 몇 대, 없으면 모두 실패 (설치 수는 `successCount`).
  static func batchInstallTitle(for report: AndroidBatchInstallReport) -> String {
    let total = report.entries.count
    let succeeded = report.successCount
    guard succeeded > 0 else {
      return self.batchInstallFailedTitle(total: total)
    }
    return String(localized: "기기 \(total)대 중 \(succeeded)대에 앱을 설치했습니다", bundle: .module)
  }

  /// 결과 알림 본문: 같은 결과의 기기를 한 줄로 묶어(처음 나온 순서) 빈 줄로 잇는다.
  static func batchInstallMessage(for report: AndroidBatchInstallReport) -> String {
    var groups: [(result: AndroidBatchDeviceResult, devices: [AndroidDeviceLabel])] = []
    for entry in report.entries {
      if let index = groups.firstIndex(where: { $0.result == entry.result }) {
        groups[index].devices.append(entry.device)
      } else {
        groups.append((entry.result, [entry.device]))
      }
    }
    return groups.map { self.batchInstallLine($0.result, devices: self.deviceNames($0.devices)) }
      .joined(separator: "\n\n")
  }

  /// 기기 이름 목록 (라벨 `“이름” (API 37.0)` 을 `, ` 로 잇는다). 사용자 데이터라 번역하지 않는다.
  static func deviceNames(_ devices: [AndroidDeviceLabel]) -> String {
    devices.map(self.label).joined(separator: ", ")
  }

  private static func batchInstallFailedTitle(total: Int) -> String {
    String(localized: "기기 \(total)대에 앱을 설치하지 못했습니다", bundle: .module)
  }

  /// 결과 한 줄. `devices` 는 `deviceNames(_:)` 로 이은 이름이다. 실행 실패의 이유는 한 기기 알림과 같은 본문이다.
  private static func batchInstallLine(_ result: AndroidBatchDeviceResult, devices: String) -> String {
    switch result {
    case .succeeded:
      return String(localized: "\(devices): 설치하고 실행했습니다.", bundle: .module)
    case let .installFailed(failure):
      let reason = self.message(for: failure)
      return String(localized: "\(devices): 설치하지 못했습니다. \(reason)", bundle: .module)
    case let .launchFailed(error):
      let reason = self.installedButNotLaunchedMessage(for: error)
      return String(localized: "\(devices): 설치했지만 실행하지 못했습니다. \(reason)", bundle: .module)
    }
  }
}
