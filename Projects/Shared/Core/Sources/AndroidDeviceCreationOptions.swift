import Foundation

/// 새 Android 기기를 만들 때 고를 수 있는 시스템 이미지와 화면 모양.
/// Model(시트 기본값·선택 검증)과 Impl(실행 직전 재확인)이 같은 규칙을 쓴다.
public struct AndroidDeviceCreationOptions: Hashable, Sendable {
  /// 호스트 abi 의 이미지만. API 내림차순(숫자 인식: `37.0` > `36` > `35`), 같으면 태그 순서. 같은 값은 하나만.
  public let images: [AndroidSystemImageRef]
  /// 고정 목록 (`AndroidDeviceProfile.all`).
  public let profiles: [AndroidDeviceProfile]

  /// - Parameter installedImages: SDK 에 설치된 이미지 (`system.img` 가 있는 것만 넘긴다. 확인은 Impl 이 한다).
  public init(installedImages: [AndroidSystemImageRef], host: AndroidHostArchitecture) {
    let abi = host.systemImageABI
    self.images = Array(Set(installedImages.filter { $0.abi == abi })).sorted(by: Self.imageOrder)
    self.profiles = AndroidDeviceProfile.all
  }

  /// 가장 높은 API (`images.first`).
  public var defaultImage: AndroidSystemImageRef? {
    self.images.first
  }

  public var isEmpty: Bool {
    self.images.isEmpty
  }

  /// 이 조합으로 만들 수 있는지.
  public func contains(image: AndroidSystemImageRef, profile: AndroidDeviceProfile.ID) -> Bool {
    self.images.contains(image) && self.profiles.contains { $0.id == profile }
  }

  private static func imageOrder(_ lhs: AndroidSystemImageRef, _ rhs: AndroidSystemImageRef) -> Bool {
    switch lhs.apiLabel.compare(rhs.apiLabel, options: .numeric) {
    case .orderedDescending: return true
    case .orderedAscending: return false
    case .orderedSame: break
    }
    return lhs.tag < rhs.tag
  }
}
