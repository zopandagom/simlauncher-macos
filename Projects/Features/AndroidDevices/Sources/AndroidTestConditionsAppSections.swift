import AndroidEmulatorInterface
import Core
import SwiftUI

/// Android 테스트 조건 시트 `Form` 의 앱 단위 구역: 앱(패키지 고르기·앱 목록 다시 읽기) → 권한(앱이 요청한 런타임 권한마다 허용 토글,
/// 허용된 행의 종료 안내, 상시 안내) → 푸시 알림(보낼 수 없다는 안내만). 앱을 고르지 않았으면 권한 구역은 한 줄 안내만 보인다.
/// 앱 목록을 다시 읽는 동안은 마지막 목록·고른 패키지·권한 구역을 그대로 두고, 앱 구역의 다시 읽기 버튼 자리에만 읽는 중을 보인다.
/// Model 은 `let model` 로 받아 이벤트 메서드만 부른다. 그 기기에 적용 중인 명령이 있으면 권한 토글을 끈다 (앱 고르기는 켜 둔다).
struct AndroidTestConditionsAppSections: View {
  let model: AndroidTestConditionsModel
  let draft: AndroidTestConditionsDraft
  let isApplying: Bool

  private var app: AndroidTestConditionsAppDraft {
    self.draft.app
  }

  var body: some View {
    Section(AndroidDevicesText.appSection) {
      self.packagePicker
    }
    Section(AndroidDevicesText.privacySection) {
      if self.app.selectedPackage != nil, self.app.loadedPackages != nil {
        self.permissions
      } else {
        self.caption(AndroidDevicesText.selectAppFirst)
      }
    }
    Section(AndroidDevicesText.pushSection) {
      self.caption(AndroidDevicesText.pushUnsupportedNote)
    }
  }

  // MARK: - 앱

  @ViewBuilder
  private var packagePicker: some View {
    switch self.app.packages {
    case .loading:
      ProgressView {
        Text(AndroidDevicesText.readingApps)
      }
      .frame(maxWidth: .infinity)
    case let .failed(error):
      VStack(alignment: .leading, spacing: 6) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(AndroidDevicesText.appsReadFailed)
              .fontWeight(.semibold)
            Text(AndroidDevicesText.testConditionsFailure(error))
              .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        self.refreshButton
      }
    case .loaded, .reloading:
      let packages = self.app.loadedPackages ?? []
      if packages.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(AndroidDevicesText.noInstalledAppsForConditions)
            .fixedSize(horizontal: false, vertical: true)
          self.refreshControl
        }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Picker(AndroidDevicesText.appSection, selection: Binding<AndroidPackageName?>(
              get: { self.app.selectedPackage },
              set: { new in Task { await self.model.packageSelected(new) } }
            )) {
              Text(AndroidDevicesText.noAppSelected).tag(AndroidPackageName?.none)
              ForEach(packages, id: \.self) { package in
                // 패키지 이름은 앱이 정한 값이라 번역하지 않는다.
                Text(verbatim: package.rawValue).tag(Optional(package))
              }
            }
            .pickerStyle(.menu)
            self.refreshControl
          }
          self.caption(AndroidDevicesText.appsRefreshNote)
        }
      }
    }
  }

  /// 목록 행의 다시 읽기 자리: 다시 읽는 중이면 버튼 대신 작은 진행 표시 (Model 도 읽는 중의 다시 읽기를 무시한다).
  @ViewBuilder
  private var refreshControl: some View {
    if self.app.isReadingPackages {
      HStack(spacing: 4) {
        ProgressView()
          .controlSize(.small)
        self.caption(AndroidDevicesText.readingApps)
      }
    } else {
      self.refreshButton
    }
  }

  private var refreshButton: some View {
    Button(AndroidDevicesText.refreshAppsButton) {
      Task { await self.model.packagesRefreshTapped() }
    }
  }

  // MARK: - 권한

  @ViewBuilder
  private var permissions: some View {
    switch self.app.permissions {
    case .idle:
      self.caption(AndroidDevicesText.selectAppFirst)
    case .loading:
      ProgressView {
        Text(AndroidDevicesText.readingConditions)
      }
      .frame(maxWidth: .infinity)
    case .appNotInstalled:
      VStack(alignment: .leading, spacing: 6) {
        Text(AndroidDevicesText.permissionsAppNotInstalled)
          .fixedSize(horizontal: false, vertical: true)
        // 같은 패키지의 권한을 다시 읽어도 앱이 없으면 같은 상태라, 앱 목록을 다시 읽게 한다. 앱 목록을 읽는 중이면 Model 이 무시하므로
        // 끈다.
        self.refreshButton
          .disabled(self.app.isReadingPackages)
      }
    case let .failed(error):
      VStack(alignment: .leading, spacing: 6) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(AndroidDevicesText.conditionsReadFailed)
              .fontWeight(.semibold)
            Text(AndroidDevicesText.testConditionsFailure(error))
              .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        Button(AndroidDevicesText.rereadButton) {
          Task { await self.model.permissionsRetryTapped() }
        }
      }
    case .loaded where self.app.sortedPermissions.isEmpty:
      self.caption(AndroidDevicesText.noRuntimePermissions)
    case .loaded:
      ForEach(self.app.sortedPermissions, id: \.permission) { grant in
        VStack(alignment: .leading, spacing: 2) {
          Toggle(AndroidDevicesText.permissionName(grant.permission), isOn: Binding(
            get: { grant.isGranted },
            set: { new in Task { await self.model.permissionChanged(grant.permission, granted: new) } }
          ))
          .disabled(self.isApplying)
          if grant.isGranted {
            self.caption(AndroidDevicesText.permissionTerminationNote)
          }
        }
      }
      self.caption(AndroidDevicesText.permissionDenyNote)
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
