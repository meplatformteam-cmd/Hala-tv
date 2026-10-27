set -e
[ -f logo.png ] || { echo 'logo.png is missing next to build.sh'; exit 1; }
mkdir -p android/app/src/main/res/xml android/app/src/main/java/com/hala/tv android/app/src/main/assets android/app/src/main/res/drawable android/app/src/main/res/mipmap-xxhdpi
cp index.html android/app/src/main/assets/index.html
BUILD_TS=$(date -u '+%Y-%m-%d %H:%M')
sed -i "s|__OS_KEY__|${OS_KEY:-}|g;s|__OS_USER__|${OS_USER:-}|g;s|__OS_PASS__|${OS_PASS:-}|g;s|__TMDB_KEY__|${TMDB_KEY:-}|g;s|__PAIR_URL__|${PAIR_URL:-https://meplatformteam-cmd.github.io/Hala-tv/index.html}|g;s|__APP_VER__|${APP_VER:-}|g;s|__BUILD__|${BUILD_TS}|g;s|__SUB_SRV__|${SUB_SRV:-}|g" android/app/src/main/assets/index.html
cat > android/settings.gradle <<'EOF'
pluginManagement {
  repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
  repositories { google(); mavenCentral() }
}
rootProject.name = "HalaTV"
include ':app'
EOF
cat > android/build.gradle <<'EOF'
plugins { id 'com.android.application' version '8.5.2' apply false }
EOF
printf "android.useAndroidX=true\n" > android/gradle.properties
if [ -n "${KEYSTORE_B64:-}" ]; then echo "$KEYSTORE_B64" | base64 -d > android/hala.jks; elif [ -f hala.jks ]; then cp hala.jks android/hala.jks; fi
printf '<?xml version="1.0" encoding="utf-8"?>\n<paths><cache-path name="u" path="updates/"/></paths>\n' > android/app/src/main/res/xml/fp.xml
VC=$(printf '%s' "${APP_VER:-1}" | tr -dc '0-9'); VC=${VC:-1}
cat > android/app/build.gradle <<EOF
plugins { id 'com.android.application' }
android {
  namespace 'com.hala.tv'
  compileSdk 34
  defaultConfig {
    applicationId 'com.hala.tv'
    minSdk 21
    targetSdk 34
    versionCode $VC
    versionName '${APP_VER:-1}'
  }
  signingConfigs {
    debug {
      if (file('../hala.jks').exists()) { storeFile file('../hala.jks'); storePassword '${KS_PASS:-halatv123}'; keyAlias '${KS_ALIAS:-hala}'; keyPassword '${KS_PASS:-halatv123}' }
    }
  }
  compileOptions {
    sourceCompatibility JavaVersion.VERSION_17
    targetCompatibility JavaVersion.VERSION_17
  }
}
dependencies { implementation 'androidx.core:core:1.12.0' }
EOF
cat > android/app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
  <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
  <uses-feature android:name="android.software.leanback" android:required="false"/>
  <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
  <application
    android:label="Hala TV"
    android:icon="@mipmap/ic_launcher"
    android:banner="@drawable/banner"
    android:usesCleartextTraffic="true"
    android:hardwareAccelerated="true"
    android:largeHeap="true"
    android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
    <provider android:name="androidx.core.content.FileProvider" android:authorities="com.hala.tv.fp" android:exported="false" android:grantUriPermissions="true"><meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/fp"/></provider>
    <activity
      android:name=".MainActivity"
      android:exported="true"
      android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout|uiMode|density">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
        <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF
cat > android/app/src/main/java/com/hala/tv/MainActivity.java <<'EOF'
package com.hala.tv;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.net.Uri;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.util.Base64;
import android.os.Bundle;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Iterator;

public class MainActivity extends Activity {
  private WebView web;
  private ValueCallback<Uri[]> fcb;

  public class Bridge {
    @JavascriptInterface
    public String ssid() {
      try {
        ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
        NetworkInfo n = cm.getActiveNetworkInfo();
        if (n != null && n.getType() == ConnectivityManager.TYPE_ETHERNET) return "Ethernet";
        WifiManager wm = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        WifiInfo i = wm.getConnectionInfo();
        String s = (i == null) ? "" : i.getSSID();
        if (s == null || s.contains("unknown ssid")) return "";
        return s.replace("\"", "");
      } catch (Exception e) {
        return "";
      }
    }

    @JavascriptInterface
    public String lastCrash() {
      android.content.SharedPreferences p = getSharedPreferences("h", 0);
      String s = p.getString("crash", "");
      p.edit().remove("crash").apply();
      return s;
    }

    @JavascriptInterface
    public void install(final String url) {
      new Thread(new Runnable() {
        public void run() {
          try {
            java.io.File dir = new java.io.File(getCacheDir(), "updates");
            dir.mkdirs();
            final java.io.File f = new java.io.File(dir, "app.apk");
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(15000);
            c.setReadTimeout(60000);
            InputStream is = c.getInputStream();
            java.io.FileOutputStream os = new java.io.FileOutputStream(f);
            byte[] buf = new byte[16384];
            int n;
            while ((n = is.read(buf)) > 0) os.write(buf, 0, n);
            os.close();
            is.close();
            runOnUiThread(new Runnable() {
              public void run() {
                try {
                  android.net.Uri u = androidx.core.content.FileProvider.getUriForFile(MainActivity.this, "com.hala.tv.fp", f);
                  Intent i = new Intent(Intent.ACTION_VIEW);
                  i.setDataAndType(u, "application/vnd.android.package-archive");
                  i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                  startActivity(i);
                } catch (Exception e) {}
              }
            });
          } catch (Exception e) {}
        }
      }).start();
    }

    @JavascriptInterface
    public void http(final String id, final String method, final String url, final String headers, final String body) {
      new Thread(new Runnable() {
        public void run() {
          String out;
          try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setRequestMethod(method);
            c.setConnectTimeout(15000);
            c.setReadTimeout(url.contains("/ai") ? 240000 : 30000);
            JSONObject h = new JSONObject(headers);
            boolean raw = h.has("X-Hala-Raw");
            h.remove("X-Hala-Raw");
            Iterator<String> it = h.keys();
            while (it.hasNext()) { String k = it.next(); c.setRequestProperty(k, h.getString(k)); }
            if (body != null && body.length() > 0) {
              c.setDoOutput(true);
              OutputStream os = c.getOutputStream();
              os.write(body.getBytes("UTF-8"));
              os.close();
            }
            int code = c.getResponseCode();
            InputStream is = code >= 400 ? c.getErrorStream() : c.getInputStream();
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            if (is != null) {
              byte[] buf = new byte[8192];
              int n;
              while ((n = is.read(buf)) > 0) bo.write(buf, 0, n);
              is.close();
            }
            JSONObject r = new JSONObject();
            r.put("status", code);
            r.put("body", bo.toString("UTF-8"));
            if (raw || url.contains("/subtitleserve/")) r.put("b64", Base64.encodeToString(bo.toByteArray(), Base64.NO_WRAP));
            out = r.toString();
          } catch (Exception e) {
            out = "{\"status\":0,\"body\":\"\"}";
          }
          final String res = out;
          runOnUiThread(new Runnable() {
            public void run() {
              web.evaluateJavascript("window.__http('" + id + "'," + JSONObject.quote(res) + ")", null);
            }
          });
        }
      }).start();
    }
  }

  @Override
  protected void onCreate(Bundle b) {
    super.onCreate(b);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().getDecorView().setSystemUiVisibility(
      View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    if (Build.VERSION.SDK_INT >= 23
        && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION}, 1);
    }
    web = new WebView(this);
    setContentView(web);
    WebSettings s = web.getSettings();
    s.setJavaScriptEnabled(true);
    s.setDomStorageEnabled(true);
    s.setMediaPlaybackRequiresUserGesture(false);
    s.setAllowFileAccess(true);
    s.setAllowFileAccessFromFileURLs(true);
    s.setAllowUniversalAccessFromFileURLs(true);
    s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
    s.setUseWideViewPort(true);
    s.setLoadWithOverviewMode(true);
    web.setBackgroundColor(0xFF000000);
    web.setWebChromeClient(new WebChromeClient() {
      @Override
      public boolean onShowFileChooser(WebView w, ValueCallback<Uri[]> cb, FileChooserParams p) {
        if (fcb != null) fcb.onReceiveValue(null);
        fcb = cb;
        try {
          Intent i = new Intent(Intent.ACTION_GET_CONTENT);
          i.addCategory(Intent.CATEGORY_OPENABLE);
          i.setType("*/*");
          startActivityForResult(i, 7);
        } catch (Exception e) {
          fcb = null;
          cb.onReceiveValue(null);
          web.evaluateJavascript("window.__nopicker&&window.__nopicker()", null);
        }
        return true;
      }
    });
    web.setWebViewClient(new WebViewClient() {
      @Override
      public boolean onRenderProcessGone(WebView view, android.webkit.RenderProcessGoneDetail detail) {
        getSharedPreferences("h", 0).edit().putString("crash", detail.didCrash() ? "renderer crashed" : "renderer killed (memory)").apply();
        runOnUiThread(new Runnable() { public void run() { recreate(); } });
        return true;
      }
    });
    web.addJavascriptInterface(new Bridge(), "HalaNative");
    web.loadUrl("file:///android_asset/index.html");
    web.requestFocus();
  }

  @Override
  protected void onActivityResult(int rq, int rs, Intent d) {
    if (rq == 7 && fcb != null) {
      Uri[] r = null;
      if (rs == RESULT_OK && d != null) r = WebChromeClient.FileChooserParams.parseResult(rs, d);
      fcb.onReceiveValue(r);
      fcb = null;
      return;
    }
    super.onActivityResult(rq, rs, d);
  }

  @Override
  public void onBackPressed() {
    web.evaluateJavascript("(function(){return window.halaBack?window.halaBack():false})()", new ValueCallback<String>() {
      @Override
      public void onReceiveValue(String v) {
        if (!"true".equals(v)) finish();
      }
    });
  }

  @Override
  protected void onDestroy() {
    if (web != null) web.destroy();
    super.onDestroy();
  }
}
EOF
cat > android/gen.py <<'EOF'
from PIL import Image
logo = Image.open('logo.png').convert('RGBA')
def make(w, h, path, scale):
    im = Image.new('RGB', (w, h), (0, 0, 0))
    k = min(w * scale / logo.width, h * scale / logo.height)
    l = logo.resize((max(1, int(logo.width * k)), max(1, int(logo.height * k))), Image.LANCZOS)
    im.paste(l, ((w - l.width) // 2, (h - l.height) // 2), l)
    im.save(path)
make(320, 180, 'android/app/src/main/res/drawable/banner.png', 0.78)
make(192, 192, 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 0.62)
EOF
pip install pillow
python3 android/gen.py
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null || true
(cd android && gradle assembleDebug --no-daemon)
cp android/app/build/outputs/apk/debug/app-debug.apk hala-tv.apk
