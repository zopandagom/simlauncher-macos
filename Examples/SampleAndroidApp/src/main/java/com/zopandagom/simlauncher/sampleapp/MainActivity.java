package com.zopandagom.simlauncher.sampleapp;

import android.app.Activity;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.TextView;

/** 앱 이름과 "versionName (versionCode)" 를 보인다 (iOS 샘플과 같은 내용). */
public final class MainActivity extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    TextView text = new TextView(this);
    text.setGravity(Gravity.CENTER);
    text.setTextSize(20);
    text.setText("SimLauncher Sample\n" + this.versionText());
    this.setContentView(text);
  }

  private String versionText() {
    try {
      PackageInfo info = this.getPackageManager().getPackageInfo(this.getPackageName(), 0);
      return info.versionName + " (" + versionCode(info) + ")";
    } catch (PackageManager.NameNotFoundException e) {
      return "?";
    }
  }

  @SuppressWarnings("deprecation")
  private static long versionCode(PackageInfo info) {
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode;
  }
}
