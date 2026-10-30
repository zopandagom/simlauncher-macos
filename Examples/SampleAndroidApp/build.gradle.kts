// 의존성 없는 Java 앱 하나. 빌드: gradle assembleDebug -PsampleBuildNumber=<번호> (SAMPLE_KEYSTORE 필요, README.md)
plugins {
  id("com.android.application") version "9.4.0"
}

// 서명 키: sample-signing.pem 을 openssl 로 바꾼 PKCS12 파일 경로 (비밀번호 android, 별칭 sample).
// 없으면 멈춘다. 기본 디버그 키로 조용히 서명하면 빌드마다 서명이 달라져 다음 빌드로 업데이트할 수 없다.
val sampleKeystore = providers.environmentVariable("SAMPLE_KEYSTORE").orNull
  ?: throw GradleException("SAMPLE_KEYSTORE 에 샘플 서명 키(PKCS12) 경로가 필요합니다 (Examples/SampleAndroidApp/README.md).")

android {
  // iOS 샘플(Examples/SampleApp)의 번들 id 와 같다
  namespace = "com.zopandagom.simlauncher.sampleapp"
  compileSdk = 37

  defaultConfig {
    applicationId = "com.zopandagom.simlauncher.sampleapp"
    minSdk = 26
    targetSdk = 37
    // 워크플로 실행 번호. iOS 의 CFBundleVersion 과 같은 값이다
    versionCode = providers.gradleProperty("sampleBuildNumber").map(String::toInt).getOrElse(1)
    // iOS 샘플의 MARKETING_VERSION 과 같게 둔다 (바꿀 때 둘 다)
    versionName = "1.0.0"
  }

  signingConfigs {
    create("sample") {
      storeFile = file(sampleKeystore)
      storeType = "PKCS12"
      storePassword = "android"
      keyAlias = "sample"
      keyPassword = "android"
    }
  }

  buildTypes {
    getByName("debug") {
      signingConfig = signingConfigs.getByName("sample")
    }
  }
}
