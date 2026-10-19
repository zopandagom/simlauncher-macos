import Foundation
import Synchronization
import Testing

enum Fixture {
  static func data(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }
}

/// provider 가 몇 번 불렸는지 센다.
final class ProviderCounter: Sendable {
  private let count = Mutex(0)
  private let url: URL?

  init(returning url: URL?) {
    self.url = url
  }

  var calls: Int {
    self.count.withLock { $0 }
  }

  func provide() -> URL? {
    self.count.withLock { $0 += 1 }
    return self.url
  }
}
