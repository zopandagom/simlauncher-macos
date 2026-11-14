/// 테스트 조건 시트의 자주 쓰는 위치. 이름 문구는 Feature 가 정한다 (iOS·Android 두 카탈로그 동기화).
/// 음수 위도(시드니)·음수 경도(쿠퍼티노·뉴욕·런던)가 모두 들어 있어 수동 확인에서 인자 순서·부호를 함께 본다.
public enum LocationPreset: String, CaseIterable, Hashable, Sendable {
  case seoul
  case tokyo
  case cupertino
  case newYork
  case london
  case sydney

  public var coordinate: GeoCoordinate {
    switch self {
    // 서울시청
    case .seoul: GeoCoordinate(validLatitude: 37.5665, longitude: 126.9780)
    // 도쿄역
    case .tokyo: GeoCoordinate(validLatitude: 35.6812, longitude: 139.7671)
    // Apple Park
    case .cupertino: GeoCoordinate(validLatitude: 37.3349, longitude: -122.0090)
    // 타임스스퀘어
    case .newYork: GeoCoordinate(validLatitude: 40.7580, longitude: -73.9855)
    case .london: GeoCoordinate(validLatitude: 51.5072, longitude: -0.1276)
    case .sydney: GeoCoordinate(validLatitude: -33.8688, longitude: 151.2093)
    }
  }
}
