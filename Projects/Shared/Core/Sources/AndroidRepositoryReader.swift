import Foundation

/// 저장소 XML 을 `AndroidRepository` 로 읽는다. 요소는 로컬 이름(접두를 뗀 이름)과 조상 경로로 알아보고, 모르는 요소는 무시한다.
/// 읽는 구조 (1단계 실측, 설계 §6):
/// ```
/// <sdk:sdk-repository> | <sys-img:sdk-sys-img>
///   <license id="…" type="text">원문</license>
///   <channel id="channel-0">stable</channel>
///   <remotePackage path="…" obsolete="true">
///     <type-details><api-level/><codename/><tag><id/></tag>…<abi/><base-extension/></type-details>
///     <revision><major/><minor/><micro/><preview/></revision>
///     <display-name/> <uses-license ref="…"/> <channelRef ref="channel-N"/>
///     <dependencies><dependency path="…"><min-revision>…</min-revision></dependency></dependencies>
///     <archives><archive><host-os/><host-arch/><complete><size/><checksum
/// type="sha1"/><url/></complete></archive></archives>
/// ```
enum AndroidRepositoryReader {
  static let roots: Set<String> = ["sdk-repository", "sdk-sys-img"]

  static func read(_ data: Data) throws(AndroidRepositoryProblem) -> AndroidRepository {
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    let delegate = Delegate()
    parser.delegate = delegate
    let parsed = parser.parse()
    if delegate.unexpectedRoot {
      throw .unexpectedRoot
    }
    guard parsed, delegate.sawRoot else {
      throw .malformedXML
    }
    return delegate.repository()
  }

  /// `prefix:name` → `name`.
  static func localName(_ name: String) -> String {
    guard let colon = name.lastIndex(of: ":") else {
      return name
    }
    return String(name[name.index(after: colon)...])
  }
}

// MARK: - 초안

private struct RevisionDraft {
  var major: String?
  var minor: String?
  var micro: String?
  var preview: String?

  /// major 가 필수. 숫자가 아닌 값이 하나라도 있으면 nil.
  var revision: AndroidRevision? {
    guard let major = self.major.flatMap(Self.number) else {
      return nil
    }
    var parts: [Int] = []
    for value in [self.minor, self.micro] {
      guard let value else {
        parts.append(0)
        continue
      }
      guard let number = Self.number(value) else {
        return nil
      }
      parts.append(number)
    }
    var preview: Int?
    if let raw = self.preview {
      guard let number = Self.number(raw) else {
        return nil
      }
      preview = number
    }
    return AndroidRevision(major: major, minor: parts[0], micro: parts[1], preview: preview)
  }

  private static func number(_ raw: String) -> Int? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.allSatisfy(\.isASCIIDigit) else {
      return nil
    }
    return Int(trimmed)
  }
}

private struct ArchiveDraft {
  var hostOS: String?
  var hostArch: String?
  var size: String?
  var checksumType: String?
  var checksum: String?
  var url: String?

  /// size(0 이상 정수)·checksum(sha1·sha256 의 hex)·url(빈 문자열 아님)이 모두 있어야 한다.
  var archive: AndroidArchive? {
    guard
      let sizeText = self.size?.trimmingCharacters(in: .whitespacesAndNewlines),
      let size = Int64(sizeText),
      size >= 0,
      let algorithm = self.checksumType.flatMap(Self.algorithm),
      let checksum = self.checksum.flatMap({ ArchiveChecksum(algorithm: algorithm, hex: $0) }),
      let url = self.url?.trimmingCharacters(in: .whitespacesAndNewlines),
      !url.isEmpty
    else {
      return nil
    }
    return AndroidArchive(
      hostOS: Self.trimmed(self.hostOS),
      hostArch: Self.trimmed(self.hostArch),
      size: size,
      checksum: checksum,
      fileName: url
    )
  }

  private static func algorithm(_ type: String) -> ArchiveChecksum.Algorithm? {
    switch type {
    case "sha1": .sha1
    case "sha256": .sha256
    default: nil
    }
  }

  private static func trimmed(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}

private struct DependencyDraft {
  var path: String
  var minRevision = RevisionDraft()
  var hasMinRevision = false
}

private struct PackageDraft {
  var path: String?
  var obsolete = false
  var revision = RevisionDraft()
  var displayName: String?
  var licenseRef: String?
  var channelRef: String?
  var apiLevel: String?
  var codename: String?
  var tags: [String] = []
  var abi: String?
  var baseExtension: String?
  var dependencies: [DependencyDraft] = []
  var archives: [ArchiveDraft] = []
}

// MARK: - XMLParser delegate

/// 한 번의 `parse()` 동안만 쓰는 상태 (Sendable 이 아니다).
private final class Delegate: NSObject, XMLParserDelegate {
  private(set) var sawRoot = false
  private(set) var unexpectedRoot = false

  /// 로컬 이름 스택. 0 번이 루트.
  private var stack: [String] = []
  private var text = ""
  private var licenses: [String: AndroidLicense] = [:]
  private var channels: [String: String] = [:]
  private var packages: [PackageDraft] = []
  private var license: (id: String, text: String)?
  private var channelID: String?
  private var package: PackageDraft?
  private var dependency: DependencyDraft?
  private var archive: ArchiveDraft?

  func repository() -> AndroidRepository {
    AndroidRepository(licenses: self.licenses, packages: self.packages.compactMap(self.package(from:)))
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
    attributes: [String: String] = [:]
  ) {
    let name = AndroidRepositoryReader.localName(elementName)
    if self.stack.isEmpty {
      guard AndroidRepositoryReader.roots.contains(name) else {
        self.unexpectedRoot = true
        parser.abortParsing()
        return
      }
      self.sawRoot = true
    }
    self.stack.append(name)
    self.text = ""
    switch self.stack.count {
    case 2:
      self.startTopLevel(name, attributes: attributes)
    default:
      self.startInPackage(name, attributes: attributes)
    }
  }

  func parser(_: XMLParser, foundCharacters string: String) {
    self.text += string
  }

  func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
    self.text += String(bytes: CDATABlock, encoding: .utf8) ?? ""
  }

  func parser(
    _: XMLParser,
    didEndElement _: String,
    namespaceURI _: String?,
    qualifiedName _: String?
  ) {
    guard let name = self.stack.last else {
      return
    }
    let parent = self.stack.count >= 2 ? self.stack[self.stack.count - 2] : nil
    self.end(name, parent: parent, depth: self.stack.count)
    self.stack.removeLast()
    self.text = ""
  }

  private func startTopLevel(_ name: String, attributes: [String: String]) {
    switch name {
    case "license":
      self.license = attributes["id"].map { ($0, "") }
    case "channel":
      self.channelID = attributes["id"]
    case "remotePackage":
      self.package = PackageDraft(path: attributes["path"], obsolete: attributes["obsolete"] == "true")
    default:
      break
    }
  }

  private func startInPackage(_ name: String, attributes: [String: String]) {
    guard self.package != nil, self.stack.count >= 3 else {
      return
    }
    let parent = self.stack[self.stack.count - 2]
    switch (parent, name) {
    case ("remotePackage", "uses-license"):
      self.package?.licenseRef = attributes["ref"]
    case ("remotePackage", "channelRef"):
      self.package?.channelRef = attributes["ref"]
    case ("dependencies", "dependency"):
      self.dependency = attributes["path"].map { DependencyDraft(path: $0) }
    case ("dependency", "min-revision"):
      self.dependency?.hasMinRevision = true
    case ("archives", "archive"):
      self.archive = ArchiveDraft()
    case ("complete", "checksum"):
      self.archive?.checksumType = attributes["type"]
    default:
      break
    }
  }

  private func end(_ name: String, parent: String?, depth: Int) {
    if depth == 2 {
      self.endTopLevel(name)
      return
    }
    guard self.package != nil, let parent else {
      return
    }
    let value = self.text
    let grandparent = depth >= 3 ? self.stack[depth - 3] : nil
    switch parent {
    case "remotePackage", "type-details", "tag":
      self.endDetail(name, parent: parent, grandparent: grandparent, value: value)
    case "revision", "min-revision", "dependencies":
      self.endRevisionOrDependency(name, parent: parent, grandparent: grandparent, value: value)
    case "archive", "complete", "archives":
      self.endArchive(name, parent: parent, value: value)
    default:
      break
    }
  }

  /// 표시 이름과 시스템 이미지 정보 (앞뒤 공백을 뺀다).
  private func endDetail(_ name: String, parent: String, grandparent: String?, value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch (parent, name) {
    case ("remotePackage", "display-name"):
      self.package?.displayName = trimmed
    case ("type-details", "api-level"):
      self.package?.apiLevel = trimmed
    case ("type-details", "codename"):
      self.package?.codename = trimmed
    case ("type-details", "abi"):
      self.package?.abi = trimmed
    case ("type-details", "base-extension"):
      self.package?.baseExtension = trimmed
    case ("tag", "id") where grandparent == "type-details":
      self.package?.tags.append(trimmed)
    default:
      break
    }
  }

  /// 패키지 revision, 의존과 그 min-revision.
  private func endRevisionOrDependency(_ name: String, parent: String, grandparent: String?, value: String) {
    switch (parent, name) {
    case ("revision", _) where grandparent == "remotePackage":
      if var package = self.package {
        Self.set(name, value, in: &package.revision)
        self.package = package
      }
    case ("min-revision", _):
      if var dependency = self.dependency {
        Self.set(name, value, in: &dependency.minRevision)
        self.dependency = dependency
      }
    case ("dependencies", "dependency"):
      if let dependency = self.dependency {
        self.package?.dependencies.append(dependency)
      }
      self.dependency = nil
    default:
      break
    }
  }

  private func endArchive(_ name: String, parent: String, value: String) {
    switch (parent, name) {
    case ("archive", "host-os"):
      self.archive?.hostOS = value
    case ("archive", "host-arch"):
      self.archive?.hostArch = value
    case ("complete", "size"):
      self.archive?.size = value
    case ("complete", "checksum"):
      self.archive?.checksum = value
    case ("complete", "url"):
      self.archive?.url = value
    case ("archives", "archive"):
      if let archive = self.archive {
        self.package?.archives.append(archive)
      }
      self.archive = nil
    default:
      break
    }
  }

  private func endTopLevel(_ name: String) {
    switch name {
    case "license":
      if let license = self.license, self.licenses[license.id] == nil {
        self.licenses[license.id] = AndroidLicense(id: license.id, text: self.text)
      }
      self.license = nil
    case "channel":
      if let id = self.channelID {
        self.channels[id] = self.text
      }
      self.channelID = nil
    case "remotePackage":
      if let package = self.package {
        self.packages.append(package)
      }
      self.package = nil
      self.dependency = nil
      self.archive = nil
    default:
      break
    }
  }

  private static func set(_ name: String, _ value: String, in revision: inout RevisionDraft) {
    switch name {
    case "major": revision.major = value
    case "minor": revision.minor = value
    case "micro": revision.micro = value
    case "preview": revision.preview = value
    default: break
    }
  }
}

// MARK: - 드래프트 → 패키지

extension Delegate {
  /// 필수 값(path·revision)이 없거나 읽히지 않으면 nil. 시스템 이미지는 api-level·abi 가 모두 있을 때만.
  private func package(from draft: PackageDraft) -> AndroidRemotePackage? {
    guard
      let raw = draft.path,
      let path = AndroidPackagePath(raw),
      let revision = draft.revision.revision
    else {
      return nil
    }
    let channel: AndroidChannel = draft.channelRef.map { ref in
      self.channels[ref].map { AndroidChannel(name: $0) } ?? .unknown
    } ?? .stable
    var systemImage: AndroidSystemImageDetails?
    if let apiLevel = draft.apiLevel, let abi = draft.abi {
      let baseExtension: Bool? = switch draft.baseExtension {
      case "true": true
      case "false": false
      default: nil
      }
      systemImage = AndroidSystemImageDetails(
        apiLevel: apiLevel,
        codename: draft.codename.flatMap { $0.isEmpty ? nil : $0 },
        tags: draft.tags,
        abi: abi,
        baseExtension: baseExtension
      )
    }
    let dependencies = draft.dependencies.compactMap { dependency -> AndroidPackageDependency? in
      guard let path = AndroidPackagePath(dependency.path) else {
        return nil
      }
      return AndroidPackageDependency(
        path: path,
        minRevision: dependency.hasMinRevision ? dependency.minRevision.revision : nil
      )
    }
    let displayName = draft.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? raw
    return AndroidRemotePackage(
      path: path,
      revision: revision,
      displayName: displayName,
      licenseID: draft.licenseRef,
      channel: channel,
      obsolete: draft.obsolete,
      systemImage: systemImage,
      dependencies: dependencies,
      archives: draft.archives.compactMap(\.archive)
    )
  }
}
