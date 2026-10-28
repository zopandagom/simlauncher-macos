import Core
import CryptoKit
import Foundation

/// 받은 파일의 크기·체크섬 확인. 2.1 GB 를 8 MiB 조각으로 약 1.1초에 읽는다 (CryptoKit `Insecure.SHA1`, 실측).
enum ArchiveChecksumVerifier {
  enum Outcome: Equatable {
    case match
    /// 크기가 다르거나 체크섬이 다르거나 읽지 못했다.
    case mismatch
    case cancelled
  }

  static let chunkSize = 8 * 1024 * 1024

  /// 링크를 따라간 일반 파일의 크기가 `size` 와 같고, 내용의 체크섬이 `checksum` 과 같은지. 조각마다 `Task.isCancelled` 를 본다.
  @concurrent
  static func verify(_ file: URL, size: Int64, checksum: ArchiveChecksum) async -> Outcome {
    guard
      let attributes = try? FileManager.default
      .attributesOfItem(atPath: file.resolvingSymlinksInPath().path(percentEncoded: false)),
      attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.size] as? NSNumber)?.int64Value == size
    else {
      return .mismatch
    }
    guard let hex = self.hex(of: file, algorithm: checksum.algorithm) else {
      return Task.isCancelled ? .cancelled : .mismatch
    }
    return hex == checksum.hex ? .match : .mismatch
  }

  /// 파일 내용의 소문자 hex. 읽지 못하거나 취소되면 nil.
  static func hex(of file: URL, algorithm: ArchiveChecksum.Algorithm) -> String? {
    switch algorithm {
    case .sha1:
      var hasher = Insecure.SHA1()
      guard self.readChunks(file, { hasher.update(data: $0) }) else {
        return nil
      }
      return self.hex(hasher.finalize())
    case .sha256:
      var hasher = SHA256()
      guard self.readChunks(file, { hasher.update(data: $0) }) else {
        return nil
      }
      return self.hex(hasher.finalize())
    }
  }

  /// 조각마다 `update` 를 부른다. 끝까지 읽으면 true, 읽지 못하거나 취소되면 false.
  private static func readChunks(_ file: URL, _ update: (Data) -> Void) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: file) else {
      return false
    }
    defer { try? handle.close() }
    while true {
      guard !Task.isCancelled else {
        return false
      }
      let chunk: Data?
      do {
        chunk = try handle.read(upToCount: self.chunkSize)
      } catch {
        return false
      }
      guard let chunk, !chunk.isEmpty else {
        return true
      }
      update(chunk)
    }
  }

  private static func hex(_ digest: some Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
