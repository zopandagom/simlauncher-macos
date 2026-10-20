import Core
import Foundation
import SimulatorInterface

/// `xcrun simctl runtime list -j` 출력을 `[RuntimeImage]` 로 바꾼다 (순수).
/// 최상위는 이미지 UUID 를 키로 하는 사전이다 (Xcode 27.1 실측). 해석하지 못한 항목은 빼고 나머지를 돌려준다.
enum SimctlRuntimeListDecoder {
  /// 최상위가 사전이 아니거나 JSON 이 아니면 `.unexpectedOutput`. 결과는 런타임 식별자 → 버전 → 이미지 UUID 순이다.
  static func images(from data: Data) throws(SimulatorError) -> [RuntimeImage] {
    let entries: [String: LossyImageDTO]
    do {
      entries = try JSONDecoder().decode([String: LossyImageDTO].self, from: data)
    } catch {
      throw .unexpectedOutput
    }
    var images: [RuntimeImage] = []
    for entry in entries.values {
      if let dto = entry.value, let image = Self.image(from: dto) {
        images.append(image)
      }
    }
    return images.sorted(by: Self.precedes)
  }

  /// "Ready" 만 실제 출력에서 확인했다. 나머지는 CoreSimulator 바이너리 문자열 후보이고, 모르는 값은 `.unknown`.
  static func state(_ raw: String) -> RuntimeImage.State {
    switch raw {
    case "Ready": .ready
    case "Copying", "Verifying", "Reading", "Expanding", "Mounting": .preparing
    case "Unusable": .unusable
    case "Deleting", "Unmounting": .removing
    default: .unknown
    }
  }

  /// iphonesimulator·watchsimulator·appletvsimulator 는 실제 출력에서 확인했고, xrsimulator 는 SDK 이름에서 추정한 값이다.
  static func platform(_ platformIdentifier: String) -> DevicePlatform {
    switch platformIdentifier {
    case "com.apple.platform.iphonesimulator": .iOS
    case "com.apple.platform.watchsimulator": .watchOS
    case "com.apple.platform.appletvsimulator": .tvOS
    case "com.apple.platform.xrsimulator": .visionOS
    default: .other
    }
  }

  private static func image(from dto: ImageDTO) -> RuntimeImage? {
    guard let version = OSVersion(dto.version) else { return nil }
    return RuntimeImage(
      id: RuntimeImage.ID(dto.identifier),
      runtimeID: DeviceRuntime.ID(dto.runtimeIdentifier),
      platform: Self.platform(dto.platformIdentifier),
      version: version,
      build: dto.build,
      state: Self.state(dto.state),
      sizeBytes: dto.sizeBytes
    )
  }

  private static func precedes(_ lhs: RuntimeImage, _ rhs: RuntimeImage) -> Bool {
    if lhs.runtimeID.rawValue != rhs.runtimeID.rawValue {
      return lhs.runtimeID.rawValue < rhs.runtimeID.rawValue
    }
    if lhs.version != rhs.version {
      return lhs.version < rhs.version
    }
    return lhs.id.rawValue < rhs.id.rawValue
  }
}

/// 항목 하나를 해석하지 못해도 전체 해석을 실패시키지 않는다 (value nil).
private struct LossyImageDTO: Decodable {
  let value: ImageDTO?

  init(from decoder: any Decoder) throws {
    self.value = try? ImageDTO(from: decoder)
  }
}

private struct ImageDTO: Decodable {
  let identifier: String
  let runtimeIdentifier: String
  let platformIdentifier: String
  let version: String
  let build: String
  let state: String
  let sizeBytes: Int64?

  private enum CodingKeys: String, CodingKey {
    case identifier, runtimeIdentifier, platformIdentifier, version, build, state, sizeBytes
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.identifier = try container.decode(String.self, forKey: .identifier)
    self.runtimeIdentifier = try container.decode(String.self, forKey: .runtimeIdentifier)
    self.platformIdentifier = try container.decode(String.self, forKey: .platformIdentifier)
    self.version = try container.decode(String.self, forKey: .version)
    self.build = try container.decode(String.self, forKey: .build)
    self.state = try container.decode(String.self, forKey: .state)
    // 크기는 화면 참고용이라 형식이 달라도 항목을 버리지 않는다.
    self.sizeBytes = try? container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
  }
}
