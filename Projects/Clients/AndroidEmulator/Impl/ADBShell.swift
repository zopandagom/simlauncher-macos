/// `adb shell` 인자 인용. adb 는 `shell` 뒤 인자를 공백으로 이어 기기의 `sh` 에 넘긴다 (실측: 인용 없이
/// `…&c=2;id` 를 넘기면 `&` 에서 잘리고 `id` 가 실행된다). 사용자 값(링크)·기기에서 읽은 값(component)은 이것을 거친다.
enum ADBShell {
  /// 작은따옴표로 감싸고 안의 `'` 는 `'\''` 로 바꾼다. 원격 셸이 `$(…)`·`;`·`&`·`"`·`*`·한글·줄바꿈을 그대로 넘긴다 (실측).
  static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
  }
}
