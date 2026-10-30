# SampleAndroidApp

SimLauncher 카탈로그 예시 워크플로(`.github/workflows/sample-catalog.yml`, [docs/CATALOG.md](../../docs/CATALOG.md) 11절)가 빌드하는 최소 Android 앱이다. 앱 이름과 `versionName (versionCode)` 를 한 화면에 보인다. iOS 샘플(`Examples/SampleApp`)과 같은 id(`com.zopandagom.simlauncher.sampleapp`)·이름·버전 이름(`1.0.0`)을 쓴다.

- Java 한 파일, 의존성(AndroidX·Kotlin) 없음. AGP 9.4.0, compileSdk·targetSdk 37, minSdk 26.
- **로컬에서 빌드하지 않는다.** 워크플로의 `build-android` 잡이 GitHub Actions 러너(ubuntu-24.04, JDK 17, Gradle 9.8.2)에서 `assembleDebug` 로 빌드하고 서명을 확인한다. Gradle 래퍼(`gradlew`·래퍼 jar)는 두지 않는다: 래퍼 jar 는 검토할 수 없는 바이너리라, 워크플로가 `gradle/actions/setup-gradle` 의 `gradle-version` 으로 버전을 고정한다.
- `versionCode` 는 Gradle 속성 `sampleBuildNumber`(워크플로 실행 번호, 없으면 1)다. 버전 이름을 바꿀 때는 iOS 샘플의 `MARKETING_VERSION` 도 같이 바꾼다.

## 서명 키 `sample-signing.pem` (샘플 전용, 비밀 아님)

`sample-signing.pem` 은 **공개해 둔(비밀이 아닌) 이 샘플 전용 개인 키·인증서다.** 누구나 볼 수 있게 일부러 커밋했다 (RSA 2048 개인 키와 자체 서명 인증서를 담은 PEM 텍스트 한 파일, 바이너리 keystore 는 커밋하지 않는다).

- 키를 고정한 이유: Android 는 이미 설치된 앱을 서명이 같은 apk 로만 업데이트한다. 러너마다 새 디버그 키로 서명하면 다음 빌드를 설치할 때 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 이 된다. 그래서 워크플로는 이 PEM 을 openssl 로 PKCS12(비밀번호 `android`, 별칭 `sample`)로 바꿔 `SAMPLE_KEYSTORE` 로 넘기고, `SAMPLE_KEYSTORE` 가 없으면 빌드가 멈춘다.
- 워크플로는 빌드한 apk 의 인증서 SHA-256 이 아래 값과 다르면 실패한다:
  `7dbec183da543847432eeb8fd2ce6adeb9868ec375dc297863920b624f77b230`
- 공개해 둔 개인 키라 누구든 같은 키로 서명한 apk 로 테스터 에뮬레이터의 샘플 앱을 "업데이트" 할 수 있다. 영향은 이 샘플 앱뿐이고, 샘플 밖에는 쓰지 않는다.
- **자기 앱에서는 이 키를 쓰지 않는다.** 회사의 서명 키(keystore)를 GitHub Secret 으로 넣고, 빌드 잡에서 Secret 을 파일로 풀어 서명 설정에 넘긴다. 키를 레포에 커밋하지 않는다.

키를 바꿀 때 (보통 필요 없다. 바꾸면 이미 설치한 샘플 앱은 지운 뒤 다시 설치해야 한다):

```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 10950 \
  -subj "/CN=SimLauncher Sample (public, not secret)" -keyout k.pem -out c.pem
# 맨 위 안내 두 줄을 남기고 k.pem·c.pem 내용으로 바꾼 뒤 둘을 지운다
openssl x509 -in sample-signing.pem -outform DER | shasum -a 256   # 이 값으로 README·워크플로의 SHA-256 을 바꾼다
```
