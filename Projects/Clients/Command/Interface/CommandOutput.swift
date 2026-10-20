import Foundation

/// 실행 중 받은 출력 조각. 줄 경계와 맞지 않는다 (해석하는 쪽이 이어 붙인다).
public enum CommandOutput: Hashable, Sendable {
  case stdout(Data)
  case stderr(Data)
}
