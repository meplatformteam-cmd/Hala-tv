set -e
[ -f logo.png ] || { echo 'ERROR: logo.png is missing next to build.sh - upload it to the repo root'; exit 1; }
mkdir -p android/app/src/main/res/xml android/app/src/main/java/com/hala/tv android/app/src/main/assets android/app/src/main/res/drawable android/app/src/main/res/mipmap-xxhdpi
cp index.html android/app/src/main/assets/index.html
BUILD_TS=$(date -u '+%Y-%m-%d %H:%M')
sed -i "s|__OS_KEY__|${OS_KEY:-}|g;s|__OS_USER__|${OS_USER:-}|g;s|__OS_PASS__|${OS_PASS:-}|g;s|__TMDB_KEY__|${TMDB_KEY:-}|g;s|__PAIR_URL__|${PAIR_URL:-https://meplatformteam-cmd.github.io/Hala-tv/index.html}|g;s|__APP_VER__|${APP_VER:-}|g;s|__BUILD__|${BUILD_TS}|g;s|__SUB_SRV__|${SUB_SRV:-}|g;s|__STT_KEY__|${STT_KEY:-}|g" android/app/src/main/assets/index.html
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
plugins { id 'com.android.application' version '8.9.1' apply false }
EOF
printf "android.useAndroidX=true\norg.gradle.jvmargs=-Xmx3g\n" > android/gradle.properties
if [ -n "${KEYSTORE_B64:-}" ]; then echo "$KEYSTORE_B64" | base64 -d > android/hala.jks; elif [ -f hala.jks ]; then cp hala.jks android/hala.jks; fi
printf '<?xml version="1.0" encoding="utf-8"?>\n<paths><cache-path name="u" path="updates/"/></paths>\n' > android/app/src/main/res/xml/fp.xml
VC=$(printf '%s' "${APP_VER:-1}" | tr -dc '0-9'); VC=${VC:-1}
cat > android/app/build.gradle <<EOF
plugins { id 'com.android.application' }
android {
  namespace 'com.hala.tv'
  compileSdk 36
  defaultConfig {
    applicationId 'com.hala.tv'
    minSdk 21
    targetSdk 34
    versionCode $VC
    versionName '${APP_VER:-1}'
    ndk { abiFilters 'armeabi-v7a', 'arm64-v8a' }
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
dependencies {
  implementation 'androidx.core:core:1.12.0'
  implementation 'androidx.media3:media3-exoplayer:1.4.1'
  implementation 'androidx.media3:media3-exoplayer-hls:1.4.1'
  implementation 'androidx.media3:media3-ui:1.4.1'
  implementation 'org.videolan.android:libvlc-all:${VLC_VER:-3.7.6}'
}
EOF
cat > android/app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
  <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>
  <uses-feature android:name="android.hardware.microphone" android:required="false"/>
  <queries>
    <intent><action android:name="android.speech.RecognitionService"/></intent>
    <intent><action android:name="android.speech.action.RECOGNIZE_SPEECH"/></intent>
  </queries>
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
      android:windowSoftInputMode="adjustPan|stateHidden"
      android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout|uiMode|density">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
        <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
      </intent-filter>
    </activity>
    <activity
      android:name=".PlayerActivity"
      android:exported="false"
      android:theme="@android:style/Theme.NoTitleBar.Fullscreen"
      android:windowSoftInputMode="stateHidden"
      android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout|uiMode|density"/>
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
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.SurfaceView;
import android.view.TextureView;
import android.widget.FrameLayout;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.TrackSelectionParameters;
import androidx.media3.common.Tracks;
import androidx.media3.common.VideoSize;
import androidx.media3.common.text.CueGroup;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.SubtitleView;
import androidx.media3.ui.CaptionStyleCompat;
import android.os.SystemClock;
import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.interfaces.IMedia;
import org.videolan.libvlc.util.VLCVideoLayout;

public class MainActivity extends Activity {
  private WebView web;
  private ValueCallback<Uri[]> fcb;
  private FrameLayout exoRoot;
  private AspectRatioFrameLayout exoFrame;
  private TextureView exoSurface;
  private SubtitleView exoSubs;
  private ExoPlayer exo;
  private final Handler hnd = new Handler(Looper.getMainLooper());
  private final java.util.ArrayList<Object[]> aTr = new java.util.ArrayList<Object[]>();
  private final java.util.ArrayList<Object[]> tTr = new java.util.ArrayList<Object[]>();
  private boolean sideSub = false;
  private int sid = 0;
  private int cueTotal = 0;
  private Player.Listener exoListener;
  private int subN = 0;
  private java.io.File lastSub;
  private String eng = "exo";
  private VLCVideoLayout vlcLayout;
  private LibVLC vlcLib;
  private MediaPlayer vlc;
  private MediaPlayer.ScaleType vlcScale = MediaPlayer.ScaleType.SURFACE_BEST_FIT;
  private String vlcUrl = "";
  private long vlcStartMs, vlcT0, vlcMoveAt, vlcLastT = -1, vlcPlayAt;
  private int vlcVout;
  private boolean vlcHw = true, vlcRetried, vlcErr, vlcPlayed, vlcBuf, vlcHasVideo, vlcBroken;
  private final java.util.ArrayList<Integer> vA = new java.util.ArrayList<Integer>();
  private final java.util.ArrayList<Integer> vT = new java.util.ArrayList<Integer>();
  private final Runnable vlcSoon = new Runnable() { public void run() { vlcTracks(); vlcInfo(); } };
  private final Runnable tick = new Runnable() {
    public void run() {
      if (vlcOn() && exoRoot.getVisibility() == View.VISIBLE) { vlcTick(); hnd.postDelayed(this, 250); return; }
      if (exo == null || exoRoot.getVisibility() != View.VISIBLE) return;
      long d = exo.getDuration();
      boolean live = exo.isCurrentMediaItemLive() || d == C.TIME_UNSET;
      js("time", "{\"t\":" + exo.getCurrentPosition() + ",\"d\":" + (live ? -1 : d) + "}");
      hnd.postDelayed(this, 250);
    }
  };

  public class Bridge {
    @JavascriptInterface
    public void setSttKey(String k) { sttKey = k == null ? "" : k.trim(); }

    @JavascriptInterface
    public void voiceStop() {
      runOnUiThread(new Runnable() { public void run() { if (recRun) recRun = false; else { voiceKill(); vjs2("__voiceErr", "cancel", ""); } } });
    }

    @JavascriptInterface
    public void voiceStart(final String lang) {
      runOnUiThread(new Runnable() { public void run() { voiceBegin(lang); } });
    }

    @JavascriptInterface
    public void exoPlay(final String url, final long startMs, final int session) { runOnUiThread(new Runnable() { public void run() { exoStart(url, startMs, session); } }); }

    @JavascriptInterface
    public void exoResume() { runOnUiThread(new Runnable() { public void run() { if (vlcOn()) vlc.play(); else if (exo != null) exo.play(); } }); }

    @JavascriptInterface
    public void exoPause() { runOnUiThread(new Runnable() { public void run() { if (vlcOn()) vlc.pause(); else if (exo != null) exo.pause(); } }); }

    @JavascriptInterface
    public void exoSeek(final long ms) { runOnUiThread(new Runnable() { public void run() { if (vlcOn()) vlc.setTime(Math.max(0, ms)); else if (exo != null) exo.seekTo(Math.max(0, ms)); } }); }

    @JavascriptInterface
    public void exoStop() { runOnUiThread(new Runnable() { public void run() { exoHalt(); } }); }

    @JavascriptInterface
    public void exoFit(final int m) {
      runOnUiThread(new Runnable() { public void run() {
        vlcScale = m == 1 ? MediaPlayer.ScaleType.SURFACE_FIT_SCREEN : m == 2 ? MediaPlayer.ScaleType.SURFACE_FILL : MediaPlayer.ScaleType.SURFACE_BEST_FIT;
        if (vlc != null) vlc.setVideoScale(vlcScale);
        exoFrame.setResizeMode(m == 1 ? AspectRatioFrameLayout.RESIZE_MODE_ZOOM : m == 2 ? AspectRatioFrameLayout.RESIZE_MODE_FILL : AspectRatioFrameLayout.RESIZE_MODE_FIT);
      } });
    }

    @JavascriptInterface
    public void exoSub(final String vtt, final String lang) { runOnUiThread(new Runnable() { public void run() { exoSetSub(vtt, lang); } }); }

    @JavascriptInterface
    public void exoSubClear() { runOnUiThread(new Runnable() { public void run() { exoClearSub(); } }); }

    @JavascriptInterface
    public void exoTrack(final int type, final int idx) { runOnUiThread(new Runnable() { public void run() { if (vlcOn()) vlcPick(type, idx); else exoPick(type, idx); } }); }

    @JavascriptInterface
    public void extPlay(final String url, final long startMs, final String engine, final String title, final boolean live, final boolean ar) {
      runOnUiThread(new Runnable() { public void run() {
        try {
          exoHalt();
          Intent i = new Intent(MainActivity.this, PlayerActivity.class);
          i.putExtra("url", url);
          i.putExtra("start", startMs);
          i.putExtra("eng", engine);
          i.putExtra("title", title);
          i.putExtra("live", live);
          i.putExtra("ar", ar);
          i.putExtra("ua", web.getSettings().getUserAgentString());
          startActivityForResult(i, 8);
        } catch (Throwable e) {
          web.evaluateJavascript("window.__extDone&&window.__extDone({\"err\":\"LAUNCH\"})", null);
        }
      } });
    }

    @JavascriptInterface
    public void exitApp() { runOnUiThread(new Runnable() { public void run() { finish(); } }); }

    @JavascriptInterface
    public void engine(String e) { eng = "vlc".equals(e) ? "vlc" : "exo"; }

    @JavascriptInterface
    public boolean vlcOk() {
      if (vlcBroken || Build.VERSION.SDK_INT < 21) return false;
      for (String a : Build.SUPPORTED_ABIS) if (a.startsWith("arm")) return true;
      return false;
    }

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
            JSONObject h = new JSONObject(headers);
            boolean raw = h.has("X-Hala-Raw");
            h.remove("X-Hala-Raw");
            String cur = url;
            HttpURLConnection c;
            int code;
            for (int hop = 0; ; hop++) {
              c = (HttpURLConnection) new URL(cur).openConnection();
              c.setInstanceFollowRedirects(false);
              c.setRequestMethod(method);
              c.setConnectTimeout(15000);
              c.setReadTimeout(url.contains("/ai") ? 240000 : 30000);
              Iterator<String> it = h.keys();
              while (it.hasNext()) { String k = it.next(); c.setRequestProperty(k, h.getString(k)); }
              if (body != null && body.length() > 0) {
                c.setDoOutput(true);
                OutputStream os = c.getOutputStream();
                os.write(body.getBytes("UTF-8"));
                os.close();
              }
              code = c.getResponseCode();
              if ("GET".equals(method) && hop < 5 && (code == 301 || code == 302 || code == 303 || code == 307 || code == 308)) {
                String loc = c.getHeaderField("Location");
                if (loc != null && loc.length() > 0) { cur = new URL(new URL(cur), loc).toString(); c.disconnect(); continue; }
              }
              break;
            }
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
    getWindow().setFormat(android.graphics.PixelFormat.TRANSLUCENT);
    getWindow().getDecorView().setSystemUiVisibility(
      View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    if (Build.VERSION.SDK_INT >= 23
        && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION}, 1);
    }
    try {
      android.graphics.Bitmap lb = android.graphics.BitmapFactory.decodeResource(getResources(), R.drawable.splash_logo);
      android.graphics.drawable.BitmapDrawable lbd = new android.graphics.drawable.BitmapDrawable(getResources(), lb);
      lbd.setGravity(Gravity.CENTER);
      getWindow().setBackgroundDrawable(new android.graphics.drawable.LayerDrawable(new android.graphics.drawable.Drawable[]{new ColorDrawable(Color.BLACK), lbd}));
    } catch (Exception e) {
      getWindow().setBackgroundDrawable(new ColorDrawable(Color.BLACK));
    }
    FrameLayout root = new FrameLayout(this);
    exoRoot = new FrameLayout(this);
    exoRoot.setVisibility(View.GONE);
    exoFrame = new AspectRatioFrameLayout(this);
    exoSurface = new TextureView(this);
    exoFrame.addView(exoSurface, new FrameLayout.LayoutParams(-1, -1));
    exoRoot.addView(exoFrame, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
    vlcLayout = new VLCVideoLayout(this);
    vlcLayout.setVisibility(View.GONE);
    exoRoot.addView(vlcLayout, new FrameLayout.LayoutParams(-1, -1));
    exoSubs = new SubtitleView(this);
    exoSubs.setApplyEmbeddedStyles(false);
    exoSubs.setApplyEmbeddedFontSizes(false);
    exoSubs.setStyle(new CaptionStyleCompat(Color.WHITE, Color.TRANSPARENT, Color.TRANSPARENT, CaptionStyleCompat.EDGE_TYPE_OUTLINE, Color.BLACK, null));
    exoSubs.setFractionalTextSize(0.06f);
    exoSubs.setBottomPaddingFraction(0.08f);
    exoRoot.addView(exoSubs, new FrameLayout.LayoutParams(-1, -1));
    root.addView(exoRoot, new FrameLayout.LayoutParams(-1, -1));
    web = new WebView(this);
    root.addView(web, new FrameLayout.LayoutParams(-1, -1));
    setContentView(root);
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
    s.setSupportZoom(false);
    s.setBuiltInZoomControls(false);
    s.setDisplayZoomControls(false);
    s.setTextZoom(100);
    s.setSaveFormData(false);
    web.setOverScrollMode(View.OVER_SCROLL_NEVER);
    web.setVerticalScrollBarEnabled(false);
    web.setHorizontalScrollBarEnabled(false);
    web.setBackgroundColor(Color.TRANSPARENT);
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


  // ===== Voice search: in-app SpeechRecognizer (RECORD_AUDIO), Arabic + English, intent fallback, diagnostics =====
  private android.speech.SpeechRecognizer sr;
  private String pendingLang = "ar";
  private String voiceCur = "ar-JO";
  private int voiceTry = 0;
  private boolean voiceViaIntent = false, voiceReady = false;
  private final Runnable voiceWd = new Runnable() { public void run() { if (sr != null && !voiceReady) voiceFail(5); } };

  private void vjs(String fn, String arg) {
    if (web != null) web.evaluateJavascript("window." + fn + "&&window." + fn + "(" + JSONObject.quote(arg) + ")", null);
  }

  private void vjs2(String fn, String a, String b2) {
    if (web != null) web.evaluateJavascript("window." + fn + "&&window." + fn + "(" + JSONObject.quote(a) + "," + JSONObject.quote(b2) + ")", null);
  }

  private String voiceDiag() {
    StringBuilder d = new StringBuilder();
    try {
      d.append("dev=").append(Build.MANUFACTURER).append(' ').append(Build.MODEL).append(" sdk=").append(Build.VERSION.SDK_INT);
      d.append(";perm=").append(Build.VERSION.SDK_INT < 23 || checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED);
      d.append(";avail=").append(android.speech.SpeechRecognizer.isRecognitionAvailable(this));
      d.append(";def=").append(android.provider.Settings.Secure.getString(getContentResolver(), "voice_recognition_service"));
      d.append(";svc=");
      for (android.content.pm.ResolveInfo ri : getPackageManager().queryIntentServices(new Intent("android.speech.RecognitionService"), 0)) d.append(ri.serviceInfo.packageName).append(',');
      d.append(";act=").append(getPackageManager().queryIntentActivities(new Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH), 0).size());
    } catch (Throwable e) { d.append(";diagErr=").append(e); }
    return d.toString();
  }

  private android.content.ComponentName voiceService() {
    try {
      android.content.ComponentName first = null;
      for (android.content.pm.ResolveInfo ri : getPackageManager().queryIntentServices(new Intent("android.speech.RecognitionService"), 0)) {
        if (ri.serviceInfo == null) continue;
        android.content.ComponentName c = new android.content.ComponentName(ri.serviceInfo.packageName, ri.serviceInfo.name);
        if (ri.serviceInfo.packageName.contains("google")) return c;
        if (first == null) first = c;
      }
      return first;
    } catch (Throwable e) { return null; }
  }

  private String voiceTag(String l) { return l != null && l.startsWith("en") ? "en-US" : "ar-JO"; }

  private Intent voiceIntentFor(String tag) {
    String other = tag.startsWith("ar") ? "en-US" : "ar-JO";
    Intent vi = new Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, tag);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, tag);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 5);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_CALLING_PACKAGE, getPackageName());
    java.util.ArrayList<String> more = new java.util.ArrayList<String>();
    more.add(other);
    vi.putStringArrayListExtra("android.speech.extra.ADDITIONAL_LANGUAGES", more);
    return vi;
  }

  private void voiceBegin(String lang) {
    voiceTry = 0;
    voiceViaIntent = false;
    if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      pendingLang = lang;
      requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 2);
      return;
    }
    pendingLang = lang;
    voiceKill();
    nativeFirst = voicePreferNative();
    if (nativeFirst) voiceListen(voiceTag(lang)); else voiceRecStart(lang);
  }

  private volatile boolean nativeFirst = false;

  private boolean voicePreferNative() {
    try {
      if ("Amazon".equalsIgnoreCase(Build.MANUFACTURER)) return false;
      android.app.UiModeManager um = (android.app.UiModeManager) getSystemService(android.content.Context.UI_MODE_SERVICE);
      boolean tv = um != null && um.getCurrentModeType() == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION;
      return tv && android.speech.SpeechRecognizer.isRecognitionAvailable(this);
    } catch (Throwable e) { return false; }
  }

  // ===== Voice v2: own recorder (live level meter) + cloud STT in Arabic AND English =====
  private static final String STT_KEY = "AIzaSyBOti4mM-6x9WDnZIjIeyEU21OpBXqWBgw";
  private volatile boolean recRun = false, recSpeech = false, recAny = false;
  private volatile int recPeak = 0;
  private volatile String sttKey = "";

  private void vjsU(final String fn, final String arg) { hnd.post(new Runnable() { public void run() { vjs(fn, arg); } }); }
  private void vjsU2(final String fn, final String a, final String b2) { hnd.post(new Runnable() { public void run() { vjs2(fn, a, b2); } }); }

  private void voiceRecStart(final String lang) {
    if (recRun) return;
    recRun = true;
    final String tagA = voiceTag(lang);
    final String tagB = tagA.startsWith("ar") ? "en-US" : "ar-JO";
    new Thread(new Runnable() { public void run() {
      try { voiceRecRun(tagA, tagB); }
      catch (Throwable e) { vjsU2("__voiceErr", "audio", "rec:" + e); }
      finally { recRun = false; }
    } }).start();
  }

  private byte[] voiceCapture(int src, boolean last) {
    final int RATE = 16000, CH = 1600;
    int minBuf = android.media.AudioRecord.getMinBufferSize(RATE, android.media.AudioFormat.CHANNEL_IN_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT);
    int bufBytes = Math.max(minBuf, CH * 2) * 4;
    android.media.AudioRecord ar = null;
    try {
      ar = new android.media.AudioRecord(src, RATE, android.media.AudioFormat.CHANNEL_IN_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT, bufBytes);
      if (ar.getState() != android.media.AudioRecord.STATE_INITIALIZED) { ar.release(); return null; }
      ar.startRecording();
      if (ar.getRecordingState() != android.media.AudioRecord.RECORDSTATE_RECORDING) { ar.release(); return null; }
    } catch (Throwable e) {
      try { if (ar != null) ar.release(); } catch (Throwable x) {}
      return null;
    }
    recAny = true;
    java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
    short[] sb = new short[CH];
    long t0 = System.currentTimeMillis(), lastLoud = 0;
    double floor = -1;
    int peak = 0;
    boolean speech = false, probed = false, skip = false;
    long total = 0;
    vjsU("__voiceState", "listening");
    try {
      while (recRun) {
        int n = Build.VERSION.SDK_INT >= 23 ? ar.read(sb, 0, CH, android.media.AudioRecord.READ_NON_BLOCKING) : ar.read(sb, 0, CH);
        if (n < 0) break;
        long el0 = System.currentTimeMillis() - t0;
        if (n == 0) {
          if (el0 > 3000 && total == 0) { skip = !last; break; }
          if (el0 > 10000) break;
          try { Thread.sleep(20); } catch (InterruptedException ie) { break; }
          continue;
        }
        total += n;
        long sum = 0;
        int pk = 0;
        byte[] bb = new byte[n * 2];
        for (int i = 0; i < n; i++) {
          int v = sb[i];
          sum += (long) v * v;
          int a = v < 0 ? -v : v;
          if (a > pk) pk = a;
          bb[2 * i] = (byte) (v & 0xff);
          bb[2 * i + 1] = (byte) ((v >> 8) & 0xff);
        }
        bo.write(bb, 0, n * 2);
        double rms = Math.sqrt(sum / (double) n);
        if (pk > peak) peak = pk;
        long el = System.currentTimeMillis() - t0;
        vjsU("__voiceLvl", String.valueOf((int) Math.min(100, Math.log10(1 + rms) * 25)));
        if (el < 500) floor = floor < 0 ? rms : floor * 0.7 + rms * 0.3;
        else if (rms > Math.max(floor * 3, 250)) { speech = true; lastLoud = el; }
        if (!probed && el >= 1500) { probed = true; if (peak <= 6 && !last) { skip = true; break; } }
        if (speech && el - lastLoud > 1400) break;
        if (!speech && el > 6500) break;
        if (el > 10000) break;
      }
    } catch (Throwable e) {
    } finally {
      try { ar.stop(); } catch (Throwable e) {}
      try { ar.release(); } catch (Throwable e) {}
    }
    if (!speech && peak > 1200) speech = true;
    recPeak = peak;
    recSpeech = speech;
    return skip ? null : bo.toByteArray();
  }

  private String[] voiceStt(byte[] pcm, String tag) throws Exception {
    java.net.URL u = new java.net.URL("https://www.google.com/speech-api/v2/recognize?output=json&lang=" + tag + "&maxresults=6&pfilter=0&key=" + STT_KEY);
    java.net.HttpURLConnection c = (java.net.HttpURLConnection) u.openConnection();
    try {
      c.setConnectTimeout(8000);
      c.setReadTimeout(15000);
      c.setRequestMethod("POST");
      c.setDoOutput(true);
      c.setRequestProperty("Content-Type", "audio/l16; rate=16000");
      c.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/120 Safari/537.36");
      c.setFixedLengthStreamingMode(pcm.length);
      java.io.OutputStream o = c.getOutputStream();
      o.write(pcm);
      o.close();
      int code = c.getResponseCode();
      if (code != 200) throw new java.io.IOException("HTTPERR" + code);
      java.io.BufferedReader br = new java.io.BufferedReader(new java.io.InputStreamReader(c.getInputStream(), "UTF-8"));
      java.util.ArrayList<String> r = new java.util.ArrayList<String>();
      String ln;
      while ((ln = br.readLine()) != null) {
        ln = ln.trim();
        if (ln.length() < 3) continue;
        org.json.JSONObject jo = new org.json.JSONObject(ln);
        org.json.JSONArray res = jo.optJSONArray("result");
        if (res == null) continue;
        for (int i = 0; i < res.length(); i++) {
          org.json.JSONObject ro = res.optJSONObject(i);
          if (ro == null) continue;
          org.json.JSONArray alt = ro.optJSONArray("alternative");
          if (alt == null) continue;
          for (int j = 0; j < alt.length(); j++) {
            org.json.JSONObject ao = alt.optJSONObject(j);
            if (ao == null) continue;
            String tr = ao.optString("transcript", "");
            if (tr.length() > 0) r.add(tr);
          }
        }
      }
      return r.toArray(new String[0]);
    } finally {
      c.disconnect();
    }
  }

  private String[] voiceSttGoogle(byte[] pcm, String tagA, String tagB, String key) throws Exception {
    org.json.JSONObject cfg = new org.json.JSONObject();
    cfg.put("encoding", "LINEAR16");
    cfg.put("sampleRateHertz", 16000);
    cfg.put("languageCode", tagA);
    cfg.put("alternativeLanguageCodes", new org.json.JSONArray().put(tagB));
    cfg.put("maxAlternatives", 5);
    org.json.JSONObject au = new org.json.JSONObject();
    au.put("content", android.util.Base64.encodeToString(pcm, android.util.Base64.NO_WRAP));
    org.json.JSONObject body = new org.json.JSONObject();
    body.put("config", cfg);
    body.put("audio", au);
    byte[] bd = body.toString().getBytes("UTF-8");
    java.net.URL u = new java.net.URL("https://speech.googleapis.com/v1/speech:recognize?key=" + java.net.URLEncoder.encode(key, "UTF-8"));
    java.net.HttpURLConnection c = (java.net.HttpURLConnection) u.openConnection();
    try {
      c.setConnectTimeout(8000);
      c.setReadTimeout(20000);
      c.setRequestMethod("POST");
      c.setDoOutput(true);
      c.setRequestProperty("Content-Type", "application/json; charset=utf-8");
      c.setFixedLengthStreamingMode(bd.length);
      java.io.OutputStream o = c.getOutputStream();
      o.write(bd);
      o.close();
      int code = c.getResponseCode();
      java.io.InputStream is = code == 200 ? c.getInputStream() : c.getErrorStream();
      java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
      if (is != null) { byte[] b2 = new byte[4096]; int r; while ((r = is.read(b2)) > 0) bo.write(b2, 0, r); }
      String txt = bo.toString("UTF-8");
      if (code != 200) {
        String m = txt;
        try { m = new org.json.JSONObject(txt).getJSONObject("error").optString("message", txt); } catch (Throwable e) {}
        if (m.length() > 160) m = m.substring(0, 160);
        throw new java.io.IOException("HTTPERR" + code + ": " + m);
      }
      java.util.ArrayList<String> r2 = new java.util.ArrayList<String>();
      org.json.JSONArray res = new org.json.JSONObject(txt).optJSONArray("results");
      if (res != null) for (int i = 0; i < res.length(); i++) {
        org.json.JSONArray alt = res.getJSONObject(i).optJSONArray("alternatives");
        if (alt == null) continue;
        for (int k = 0; k < alt.length(); k++) { String tr = alt.getJSONObject(k).optString("transcript", ""); if (tr.length() > 0) r2.add(tr); }
      }
      return r2.toArray(new String[0]);
    } finally {
      c.disconnect();
    }
  }

  private void voiceRecRun(final String tagA, final String tagB) {
    int[] srcs = {6, 1, 7, 5, 9, 0};
    byte[] pcm = null;
    String used = "";
    int maxPeak = 0;
    recAny = false;
    for (int i = 0; i < srcs.length && recRun; i++) {
      byte[] p = voiceCapture(srcs[i], i == srcs.length - 1);
      if (recPeak > maxPeak) maxPeak = recPeak;
      if (p != null) { pcm = p; used = String.valueOf(srcs[i]); break; }
    }
    if (pcm == null) {
      if (!recAny) vjsU2("__voiceErr", "audio", "norec;" + voiceDiag());
      else vjsU2("__voiceErr", "silent", "peak=" + maxPeak + ";" + voiceDiag());
      return;
    }
    if (!recSpeech) { vjsU2("__voiceErr", "silent", "peak=" + recPeak + ";src=" + used + ";" + voiceDiag()); return; }
    vjsU("__voiceState", "processing");
    final byte[] fp = pcm;
    if (sttKey != null && sttKey.length() > 10) {
      try {
        String[] g = voiceSttGoogle(fp, tagA, tagB, sttKey);
        if (g.length == 0) { vjsU2("__voiceErr", "unclear", "peak=" + recPeak + ";src=" + used); return; }
        org.json.JSONArray gj = new org.json.JSONArray();
        for (String s3 : g) gj.put(s3);
        vjsU("__voice", gj.toString());
      } catch (Throwable e) {
        String m = String.valueOf(e);
        if (m.contains("HTTPERR")) vjsU2("__voiceErr", "stt", m.substring(m.indexOf("HTTPERR")));
        else vjsU2("__voiceErr", "network", "stt:" + m);
      }
      return;
    }
    final String[][] out = new String[2][];
    final String[] err = new String[2];
    final String[] tags = {tagA, tagB};
    Thread[] th = new Thread[2];
    for (int k = 0; k < 2; k++) {
      final int kk = k;
      th[k] = new Thread(new Runnable() { public void run() {
        try { out[kk] = voiceStt(fp, tags[kk]); } catch (Throwable e) { err[kk] = String.valueOf(e); }
      } });
      th[k].start();
    }
    for (Thread x : th) { try { x.join(22000); } catch (InterruptedException e) {} }
    org.json.JSONArray ja = new org.json.JSONArray();
    java.util.HashSet<String> seen = new java.util.HashSet<String>();
    for (int k = 0; k < 2; k++) {
      if (out[k] == null) continue;
      for (String s2 : out[k]) { if (seen.add(s2)) ja.put(s2); }
    }
    if (ja.length() == 0) {
      boolean http = (err[0] != null && err[0].contains("HTTPERR")) || (err[1] != null && err[1].contains("HTTPERR"));
      if (err[0] != null && err[1] != null) {
        if (http) {
          vjsU("__voiceState", "fallback");
          hnd.post(new Runnable() { public void run() { voiceViaIntent = false; voiceTry = 0; voiceListen(tagA); } });
        } else vjsU2("__voiceErr", "network", "stt:" + err[0]);
      } else vjsU2("__voiceErr", "unclear", "peak=" + recPeak + ";src=" + used);
      return;
    }
    vjsU("__voice", ja.toString());
  }

  private void voiceKill() {
    hnd.removeCallbacks(voiceWd);
    android.speech.SpeechRecognizer x = sr;
    sr = null;
    if (x != null) {
      try { x.cancel(); } catch (Throwable e) {}
      try { x.destroy(); } catch (Throwable e) {}
    }
  }

  private void voiceListen(String tag) {
    voiceKill();
    voiceCur = tag;
    voiceReady = false;
    boolean ok = false;
    try { ok = android.speech.SpeechRecognizer.isRecognitionAvailable(this); } catch (Throwable e) {}
    android.content.ComponentName cn = ok ? null : voiceService();
    if (!ok && cn == null) { voiceIntent(tag, "noservice"); return; }
    try {
      final android.speech.SpeechRecognizer me = ok ? android.speech.SpeechRecognizer.createSpeechRecognizer(this) : android.speech.SpeechRecognizer.createSpeechRecognizer(this, cn);
      sr = me;
      me.setRecognitionListener(new android.speech.RecognitionListener() {
        public void onReadyForSpeech(Bundle p) { if (sr == me) { voiceReady = true; hnd.removeCallbacks(voiceWd); vjs("__voiceState", "listening"); } }
        public void onBeginningOfSpeech() { if (sr == me) { voiceReady = true; hnd.removeCallbacks(voiceWd); } }
        public void onRmsChanged(float v) { if (sr == me) vjs("__voiceLvl", String.valueOf((int) Math.max(0, Math.min(100, (v + 2) * 8)))); }
        public void onBufferReceived(byte[] bf) {}
        public void onEndOfSpeech() {}
        public void onPartialResults(Bundle p) {}
        public void onEvent(int t, Bundle p) {}
        public void onError(int e) { if (sr == me) voiceFail(e); }
        public void onResults(Bundle r) {
          if (sr != me) return;
          voiceGot(r == null ? null : r.getStringArrayList(android.speech.SpeechRecognizer.RESULTS_RECOGNITION));
        }
      });
      hnd.postDelayed(voiceWd, 6000);
      me.startListening(voiceIntentFor(tag));
    } catch (Throwable e) {
      voiceKill();
      voiceIntent(tag, "create:" + e);
    }
  }

  private void voiceGot(java.util.ArrayList<String> l) {
    if (l == null || l.isEmpty()) { voiceFail(7); return; }
    voiceKill();
    org.json.JSONArray ja = new org.json.JSONArray();
    for (String s : l) ja.put(s);
    vjs("__voice", ja.toString());
  }

  private void voiceFail(int e) {
    String tag = voiceCur;
    if (nativeFirst && (e == 3 || e == 4 || e == 5 || e == 6 || e == 7 || e == 8)) {
      nativeFirst = false;
      voiceKill();
      vjs("__voiceState", "fallback");
      voiceRecStart(pendingLang);
      return;
    }
    if (e == 7 && voiceTry == 0) {
      voiceTry = 1;
      final String o = tag.startsWith("ar") ? "en-US" : "ar-JO";
      vjs("__voiceState", o.startsWith("en") ? "retry-en" : "retry-ar");
      voiceKill();
      hnd.postDelayed(new Runnable() { public void run() { voiceListen(o); } }, 350);
      return;
    }
    voiceKill();
    if (e == 9 && Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      pendingLang = tag;
      requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, 2);
      return;
    }
    if (e == 6 || e == 7) { vjs2("__voiceErr", "none", "E" + e); return; }
    if (e == 1 || e == 2) { vjs2("__voiceErr", "network", "E" + e + ";" + voiceDiag()); return; }
    if (e == 3) { vjs2("__voiceErr", "audio", "E3;" + voiceDiag()); return; }
    if (!voiceViaIntent) { voiceIntent(tag, "E" + e); return; }
    vjs2("__voiceErr", "none", "E" + e + ";" + voiceDiag());
  }

  private void voiceIntent(String tag, String why) {
    voiceViaIntent = true;
    try {
      startActivityForResult(voiceIntentFor(tag), 9);
    } catch (Throwable ex) {
      vjs2("__voiceErr", "unavailable", why + ";" + voiceDiag());
    }
  }

  @Override
  public void onRequestPermissionsResult(int rq, String[] p, int[] g) {
    super.onRequestPermissionsResult(rq, p, g);
    if (rq == 2) {
      if (g != null && g.length > 0 && g[0] == PackageManager.PERMISSION_GRANTED) { voiceTry = 0; voiceViaIntent = false; voiceRecStart(pendingLang); }
      else vjs2("__voiceErr", "denied", "perm-denied;" + voiceDiag());
    }
  }

  private void js(String k, String json) {
    if (web == null) return;
    web.evaluateJavascript("window.__exo&&window.__exo('" + k + "'," + json + "," + sid + ")", null);
  }

  private void exoEnsure() {
    if (exo != null) return;
    DefaultLoadControl lc = new DefaultLoadControl.Builder().setBufferDurationsMs(15000, 60000, 2500, 5000).build();
    DefaultHttpDataSource.Factory hf = new DefaultHttpDataSource.Factory()
      .setAllowCrossProtocolRedirects(true)
      .setConnectTimeoutMs(15000)
      .setReadTimeoutMs(30000)
      .setUserAgent(web.getSettings().getUserAgentString());
    exo = new ExoPlayer.Builder(this, new DefaultRenderersFactory(this).setEnableDecoderFallback(true))
      .setMediaSourceFactory(new DefaultMediaSourceFactory(new DefaultDataSource.Factory(this, hf)))
      .setLoadControl(lc)
      .build();
    exo.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true);
    exo.setVideoTextureView(exoSurface);
    exoListener = new Player.Listener() {
      @Override public void onPlaybackStateChanged(int st) {
        if (st == Player.STATE_BUFFERING) js("buf", "1");
        else if (st == Player.STATE_READY) {
          long d = exo.getDuration();
          js("ready", "{\"d\":" + ((d == C.TIME_UNSET || exo.isCurrentMediaItemLive()) ? -1 : d) + "}");
        } else if (st == Player.STATE_ENDED) js("end", "1");
      }
      @Override public void onIsPlayingChanged(boolean p) { if (p) js("play", "1"); }
      @Override public void onPlayWhenReadyChanged(boolean pw, int reason) { js("pw", pw ? "true" : "false"); }
      @Override public void onVideoSizeChanged(VideoSize vs) {
        if (vs.height > 0) exoFrame.setAspectRatio(vs.width * vs.pixelWidthHeightRatio / vs.height);
        js("size", "{\"h\":" + vs.height + "}");
      }
      @Override public void onCues(CueGroup g) { exoSubs.setCues(g.cues); cueTotal += g.cues.size(); js("cues", "{\"n\":" + g.cues.size() + ",\"c\":" + cueTotal + "}"); }
      @Override public void onTracksChanged(Tracks t) { if (exo != null) exoTracks(t); }
      @Override public void onPlayerError(PlaybackException e) {
        if (e.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) { exo.seekToDefaultPosition(); exo.prepare(); return; }
        js("err", JSONObject.quote(e.getErrorCodeName()));
      }
    };
    exo.addListener(exoListener);
  }

  // ===== LibVLC engine: same JS event protocol (__exo) as ExoPlayer =====
  private boolean vlcOn() { return "vlc".equals(eng) && vlc != null; }

  private final MediaPlayer.EventListener vlcEv = new MediaPlayer.EventListener() {
    public void onEvent(MediaPlayer.Event e) {
      if (vlc == null) return;
      switch (e.type) {
        case MediaPlayer.Event.Buffering:
          vlcBuf = e.getBuffering() < 100f;
          if (vlcBuf) js("buf", "1"); else vlcReady();
          break;
        case MediaPlayer.Event.Playing: vlcReady(); js("play", "1"); js("pw", "true"); hnd.removeCallbacks(vlcSoon); hnd.postDelayed(vlcSoon, 300); break;
        case MediaPlayer.Event.Paused: js("pw", "false"); break;
        case MediaPlayer.Event.EndReached: js("end", "1"); break;
        case MediaPlayer.Event.EncounteredError: vlcFail("ERROR"); break;
        case MediaPlayer.Event.Vout: vlcVout = e.getVoutCount(); break;
        case MediaPlayer.Event.ESAdded:
        case MediaPlayer.Event.ESDeleted:
        case MediaPlayer.Event.ESSelected: hnd.removeCallbacks(vlcSoon); hnd.postDelayed(vlcSoon, 400); break;
        default: break;
      }
    }
  };

  private void vlcStart(String url, long startMs, int session) {
    exoRelease();
    vlcRelease();
    sid = session;
    vlcErr = false; vlcRetried = false; vlcHw = true; vlcUrl = url; vlcStartMs = startMs;
    try {
      if (vlcLib == null) {
        java.util.ArrayList<String> o = new java.util.ArrayList<String>();
        o.add("--http-reconnect");
        o.add("--audio-time-stretch");
        vlcLib = new LibVLC(this, o);
      }
      vlcRun(startMs);
    } catch (Throwable e) {
      vlcBroken = true;
      vlcRelease();
      js("err", JSONObject.quote("VLC_INIT"));
    }
  }

  private void vlcRun(long startMs) {
    vlcRelease();
    exoFrame.setVisibility(View.GONE);
    vlcLayout.setVisibility(View.VISIBLE);
    exoRoot.setVisibility(View.VISIBLE);
    web.setBackgroundColor(Color.TRANSPARENT);
    vlc = new MediaPlayer(vlcLib);
    vlc.attachViews(vlcLayout, null, true, true);
    vlc.setVideoScale(vlcScale);
    vlc.setEventListener(vlcEv);
    Media m = new Media(vlcLib, Uri.parse(vlcUrl));
    m.setHWDecoderEnabled(vlcHw, false);
    boolean vod = vlcUrl.matches("(?i).*\\.(mp4|mkv|avi|mov|wmv|webm|m4v)(\\?.*)?$") || vlcUrl.contains("/movie/") || vlcUrl.contains("/series/");
    m.addOption(":network-caching=" + (vod ? 3000 : 1500));
    m.addOption(":http-user-agent=" + web.getSettings().getUserAgentString());
    if (startMs > 0) m.addOption(":start-time=" + (startMs / 1000));
    vlc.setMedia(m);
    m.release();
    long now = SystemClock.uptimeMillis();
    vlcT0 = now; vlcMoveAt = now; vlcLastT = -1; vlcPlayAt = now;
    vlcPlayed = false; vlcBuf = false; vlcVout = 0; vlcHasVideo = false;
    vlc.play();
    hnd.removeCallbacks(tick);
    hnd.post(tick);
  }

  private void vlcRelease() {
    hnd.removeCallbacks(vlcSoon);
    final MediaPlayer p = vlc;
    vlc = null;
    if (p != null) {
      try { p.setEventListener(null); } catch (Throwable e) {}
      try { p.detachViews(); } catch (Throwable e) {}
      new Thread(new Runnable() { public void run() {
        try { p.stop(); } catch (Throwable e) {}
        try { p.release(); } catch (Throwable e) {}
      } }).start();
    }
    vA.clear();
    vT.clear();
    if (vlcLayout != null) vlcLayout.setVisibility(View.GONE);
    if (exoFrame != null) exoFrame.setVisibility(View.VISIBLE);
  }

  private void vlcReady() {
    if (vlc == null) return;
    long d = vlc.getLength();
    js("ready", "{\"d\":" + ((d > 0 && vlc.isSeekable()) ? d : -1) + "}");
  }

  /* hardware decode stalled / black screen / frozen frame: retry once in software, then report so JS falls back */
  private void vlcFail(String code) {
    if (vlc == null || vlcErr) return;
    if (vlcHw && !vlcRetried) {
      vlcRetried = true;
      vlcHw = false;
      long p = Math.max(0, vlc.getTime());
      vlcRun(p > 0 ? p : vlcStartMs);
      return;
    }
    vlcErr = true;
    js("err", JSONObject.quote("VLC_" + code));
  }

  private void vlcTick() {
    if (vlcErr) return;
    long t = vlc.getTime(), d = vlc.getLength(), now = SystemClock.uptimeMillis();
    js("time", "{\"t\":" + Math.max(0, t) + ",\"d\":" + ((d > 0 && vlc.isSeekable()) ? d : -1) + "}");
    if (!vlcPlayed && (vlcVout > 0 || (t > 0 && t != vlcLastT))) { vlcPlayed = true; vlcPlayAt = now; vlcMoveAt = now; }
    if (t > 0 && t != vlcLastT) { vlcLastT = t; vlcMoveAt = now; }
    else if (vlcBuf || !vlc.isPlaying()) vlcMoveAt = now;
    else if (vlcPlayed && vlcLastT > 0 && now - vlcMoveAt > 7000) { vlcFail("FROZEN"); return; }
    if (!vlcPlayed && now - vlcT0 > 15000) { vlcFail("STARTUP"); return; }
    if (vlcPlayed && vlcHasVideo && vlcVout == 0 && now - vlcPlayAt > 6000) vlcFail("NOVIDEO");
  }

  private void vlcInfo() {
    if (vlc == null) return;
    String vc = "";
    int h = 0, w = 0;
    IMedia m = null;
    try {
      m = vlc.getMedia();
      if (m != null) for (int i = 0; i < m.getTrackCount(); i++) {
        IMedia.Track tk = m.getTrack(i);
        if (tk.type == IMedia.Track.Type.Video) {
          vlcHasVideo = true;
          vc = String.valueOf(tk.codec);
          if (tk instanceof IMedia.VideoTrack) { h = ((IMedia.VideoTrack) tk).height; w = ((IMedia.VideoTrack) tk).width; }
        }
      }
    } catch (Throwable e) {
    } finally {
      if (m != null) { try { m.release(); } catch (Throwable e) {} }
    }
    if (h > 0) js("size", "{\"h\":" + h + "}");
    js("info", "{\"v\":" + JSONObject.quote(vc) + ",\"w\":" + w + ",\"h\":" + h + ",\"sw\":" + (vlcHw ? 0 : 1) + "}");
  }

  private void vlcTracks() {
    if (vlc == null) return;
    vA.clear();
    vT.clear();
    org.json.JSONArray ja = new org.json.JSONArray();
    org.json.JSONArray jt = new org.json.JSONArray();
    int ca = vlc.getAudioTrack(), cs = vlc.getSpuTrack();
    try {
      MediaPlayer.TrackDescription[] a = vlc.getAudioTracks();
      MediaPlayer.TrackDescription[] s = vlc.getSpuTracks();
      if (a != null) for (MediaPlayer.TrackDescription x : a) {
        if (x.id < 0) continue;
        vA.add(x.id);
        JSONObject o = new JSONObject();
        o.put("l", x.name == null ? "#" + vA.size() : x.name); o.put("s", x.id == ca); o.put("g", ""); o.put("c", "");
        ja.put(o);
      }
      if (s != null) for (MediaPlayer.TrackDescription x : s) {
        if (x.id < 0) continue;
        vT.add(x.id);
        JSONObject o = new JSONObject();
        o.put("l", x.name == null ? "#" + vT.size() : x.name); o.put("s", x.id == cs); o.put("g", ""); o.put("c", "");
        jt.put(o);
      }
    } catch (Exception e) {}
    js("tracks", "{\"a\":" + ja.toString() + ",\"t\":" + jt.toString() + ",\"na\":0,\"nu\":0,\"all\":[],\"td\":" + (cs < 0 ? 1 : 0) + "}");
  }

  private void vlcPick(int type, int idx) {
    if (vlc == null) return;
    if (type == 0) { if (idx >= 0 && idx < vA.size()) vlc.setAudioTrack(vA.get(idx)); }
    else vlc.setSpuTrack(idx >= 0 && idx < vT.size() ? vT.get(idx) : -1);
    hnd.removeCallbacks(vlcSoon);
    hnd.postDelayed(vlcSoon, 200);
  }

  private void exoRelease() {
    hnd.removeCallbacks(tick);
    if (exo != null) {
      try { if (exoListener != null) exo.removeListener(exoListener); } catch (Exception e) {}
      try { exo.clearVideoSurface(); } catch (Exception e) {}
      try { exo.stop(); exo.clearMediaItems(); } catch (Exception e) {}
      try { exo.release(); } catch (Exception e) {}
      exo = null;
    }
    exoListener = null;
    aTr.clear();
    tTr.clear();
    sideSub = false;
    cueTotal = 0;
    if (exoSubs != null) exoSubs.setCues(java.util.Collections.<androidx.media3.common.text.Cue>emptyList());
  }

  private void exoStart(String url, long startMs, int session) {
    if ("vlc".equals(eng)) { vlcStart(url, startMs, session); return; }
    vlcRelease();
    exoRelease();
    sid = session;
    exoEnsure();
    exo.setTrackSelectionParameters(exo.getTrackSelectionParameters().buildUpon().clearOverrides().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false).build());
    exoRoot.setVisibility(View.VISIBLE);
    web.setBackgroundColor(Color.TRANSPARENT);
    exo.setMediaItem(MediaItem.fromUri(url), startMs > 0 ? startMs : C.TIME_UNSET);
    exo.prepare();
    exo.setPlayWhenReady(true);
    hnd.post(tick);
  }

  private void exoHalt() {
    vlcRelease();
    exoRelease();
    if (exoRoot != null) exoRoot.setVisibility(View.GONE);
    if (web != null) web.setBackgroundColor(0xFF000000);
  }

  private void exoReload(java.util.List<MediaItem.SubtitleConfiguration> subs) {
    MediaItem cur = exo.getCurrentMediaItem();
    if (cur == null) return;
    long pos = exo.getCurrentPosition();
    boolean pw = exo.getPlayWhenReady();
    exo.setMediaItem(cur.buildUpon().setSubtitleConfigurations(subs).build(), pos);
    exo.prepare();
    exo.setPlayWhenReady(pw);
  }

  private void exoSetSub(String vtt, String lang) {
    if (exo == null || exo.getCurrentMediaItem() == null) return;
    try {
      java.io.File f = new java.io.File(getCacheDir(), "sub" + (++subN) + ".vtt");
      java.io.FileOutputStream os = new java.io.FileOutputStream(f);
      os.write(vtt.getBytes("UTF-8"));
      os.close();
      if (lastSub != null) lastSub.delete();
      lastSub = f;
      MediaItem.SubtitleConfiguration sc = new MediaItem.SubtitleConfiguration.Builder(Uri.fromFile(f))
        .setMimeType(MimeTypes.TEXT_VTT)
        .setLanguage(lang == null || lang.length() == 0 ? null : lang)
        .setLabel("OpenSubtitles")
        .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
        .build();
      sideSub = true;
      exoReload(java.util.Collections.singletonList(sc));
    } catch (Exception e) {}
  }

  private void exoClearSub() {
    if (exo == null || !sideSub) return;
    sideSub = false;
    exoReload(java.util.Collections.<MediaItem.SubtitleConfiguration>emptyList());
  }

  private void exoPick(int type, int idx) {
    if (exo == null) return;
    int ty = type == 0 ? C.TRACK_TYPE_AUDIO : C.TRACK_TYPE_TEXT;
    java.util.ArrayList<Object[]> l = type == 0 ? aTr : tTr;
    TrackSelectionParameters.Builder b = exo.getTrackSelectionParameters().buildUpon();
    if (idx < 0 || idx >= l.size()) {
      if (ty == C.TRACK_TYPE_TEXT) b.setTrackTypeDisabled(ty, true);
    } else {
      Object[] e = l.get(idx);
      b.setTrackTypeDisabled(ty, false).setOverrideForType(new TrackSelectionOverride((TrackGroup) e[0], (Integer) e[1]));
    }
    exo.setTrackSelectionParameters(b.build());
  }

  private void exoTracks(Tracks tr) {
    aTr.clear();
    tTr.clear();
    org.json.JSONArray ja = new org.json.JSONArray();
    org.json.JSONArray jt = new org.json.JSONArray();
    int audAll = 0, audOk = 0, txtBad = 0;
    org.json.JSONArray jall = new org.json.JSONArray();
    try {
      for (Tracks.Group g : tr.getGroups()) {
        int ty = g.getType();
        if (ty != C.TRACK_TYPE_AUDIO && ty != C.TRACK_TYPE_TEXT) continue;
        for (int i = 0; i < g.length; i++) {
          if (ty == C.TRACK_TYPE_AUDIO) { audAll++; if (g.isTrackSupported(i)) audOk++; }
          Format f = g.getTrackFormat(i);
          if (ty == C.TRACK_TYPE_TEXT) {
            String m0 = f.sampleMimeType == null ? "" : f.sampleMimeType;
            if (m0.contains("media3-cues") && f.codecs != null) m0 = f.codecs;
            JSONObject al = new JSONObject();
            al.put("l", f.label != null ? f.label : (f.language != null ? f.language : "#"));
            al.put("m", m0);
            al.put("u", g.isTrackSupported(i));
            al.put("s", g.isTrackSelected(i));
            jall.put(al);
          }
          if (!g.isTrackSupported(i)) { if (ty == C.TRACK_TYPE_TEXT) txtBad++; continue; }
          int n = (ty == C.TRACK_TYPE_AUDIO ? aTr.size() : tTr.size()) + 1;
          String l = f.label;
          if (l == null && f.language != null && !"und".equals(f.language)) l = new java.util.Locale(f.language).getDisplayLanguage();
          if (l == null) l = "#" + n;
          if (ty == C.TRACK_TYPE_AUDIO && f.channelCount > 2) l += " " + f.channelCount + "ch";
          JSONObject o = new JSONObject();
          o.put("l", l);
          o.put("s", g.isTrackSelected(i));
          o.put("g", f.language == null ? "" : f.language);
          String mt = f.sampleMimeType == null ? "" : f.sampleMimeType;
          if (mt.contains("media3-cues") && f.codecs != null) mt = f.codecs;
          o.put("c", mt.contains("subrip") ? "SRT" : mt.contains("ssa") ? "ASS" : mt.contains("pgs") ? "PGS" : mt.contains("vtt") ? "VTT" : mt.contains("ttml") ? "TTML" : mt.contains("cea") ? "CC" : "");
          if (ty == C.TRACK_TYPE_AUDIO) { aTr.add(new Object[]{g.getMediaTrackGroup(), Integer.valueOf(i)}); ja.put(o); }
          else { tTr.add(new Object[]{g.getMediaTrackGroup(), Integer.valueOf(i)}); jt.put(o); }
        }
      }
    } catch (Exception e) {}
    boolean td = exo != null && exo.getTrackSelectionParameters().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT);
    js("tracks", "{\"a\":" + ja.toString() + ",\"t\":" + jt.toString() + ",\"na\":" + (audAll > 0 && audOk == 0 ? 1 : 0) + ",\"nu\":" + txtBad + ",\"all\":" + jall.toString() + ",\"td\":" + (td ? 1 : 0) + "}");
  }

  @Override
  protected void onPause() {
    if (sr != null) { voiceKill(); vjs("__voiceErr", "cancel"); }
    if (exo != null) exo.pause();
    if (vlc != null) vlc.pause();
    super.onPause();
  }

  @Override
  protected void onActivityResult(int rq, int rs, Intent d) {
    if (rq == 8) {
      String er = d == null ? null : d.getStringExtra("err");
      String j = "{\"t\":" + (d == null ? 0 : d.getLongExtra("t", 0))
        + ",\"d\":" + (d == null ? 0 : d.getLongExtra("d", 0))
        + ",\"end\":" + (d != null && d.getBooleanExtra("end", false))
        + ",\"zap\":" + (d == null ? 0 : d.getIntExtra("zap", 0))
        + ",\"sw\":" + JSONObject.quote(d == null || d.getStringExtra("sw") == null ? "" : d.getStringExtra("sw"))
        + ",\"err\":" + JSONObject.quote(er == null ? "" : er) + "}";
      if (web != null) web.evaluateJavascript("window.__extDone&&window.__extDone(" + j + ")", null);
      return;
    }
    if (rq == 7 && fcb != null) {
      Uri[] r = null;
      if (rs == RESULT_OK && d != null) r = WebChromeClient.FileChooserParams.parseResult(rs, d);
      fcb.onReceiveValue(r);
      fcb = null;
      return;
    }
    if (rq == 9) {
      org.json.JSONArray ja = new org.json.JSONArray();
      if (rs == RESULT_OK && d != null) {
        java.util.ArrayList<String> rl = d.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS);
        if (rl != null) { for (String sv : rl) ja.put(sv); }
      }
      if (web != null) web.evaluateJavascript("window.__voice&&window.__voice(" + JSONObject.quote(ja.toString()) + ")", null);
      return;
    }
    super.onActivityResult(rq, rs, d);
  }

  @Override
  public boolean dispatchKeyEvent(android.view.KeyEvent ke) {
    int kc = ke.getKeyCode();
    if (ke.getAction() == android.view.KeyEvent.ACTION_DOWN && ke.getRepeatCount() == 0 && (kc == 84 || kc == 219 || kc == 231)) {
      if (web != null) web.evaluateJavascript("window.voiceKey&&window.voiceKey()", null);
      return true;
    }
    return super.dispatchKeyEvent(ke);
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
    voiceKill();
    exoRelease();
    vlcRelease();
    if (vlcLib != null) { try { vlcLib.release(); } catch (Throwable e) {} }
    if (web != null) web.destroy();
    super.onDestroy();
  }
}
EOF
cat > android/app/src/main/java/com/hala/tv/PlayerActivity.java <<'EOF'
package com.hala.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.view.Window;
import android.widget.ScrollView;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.TrackSelectionParameters;
import androidx.media3.common.Tracks;
import androidx.media3.common.VideoSize;
import androidx.media3.common.text.CueGroup;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.ui.AspectRatioFrameLayout;
import androidx.media3.ui.CaptionStyleCompat;
import androidx.media3.ui.SubtitleView;
import org.videolan.libvlc.LibVLC;
import org.videolan.libvlc.Media;
import org.videolan.libvlc.MediaPlayer;
import org.videolan.libvlc.util.VLCVideoLayout;
import java.util.ArrayList;

/* Standalone native player screen (no WebView on top of the video).
   Launched by MainActivity for the "external ExoPlayer / external VLC" options. */
public class PlayerActivity extends Activity {

  interface Pick { void on(int i); }

  /* transport icon: kind 0 = rewind, 1 = play, 2 = pause, 3 = fast-forward */
  static class Ico extends View {
    int kind;
    boolean hit;
    final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    final Path path = new Path();
    final RectF rc = new RectF();
    Ico(Context c, int k) { super(c); kind = k; }
    @Override protected void onDraw(Canvas cv) {
      int w = getWidth(), h = getHeight();
      p.setStyle(Paint.Style.FILL);
      p.setColor(hit ? Color.WHITE : 0x33FFFFFF);
      rc.set(0, 0, w, h);
      cv.drawRoundRect(rc, h / 2f, h / 2f, p);
      p.setColor(hit ? Color.BLACK : Color.WHITE);
      float s = h * 0.30f, a = s * 0.95f, cx = w / 2f, cy = h / 2f;
      path.reset();
      if (kind == 1) {
        path.moveTo(cx - s * 0.7f, cy - a); path.lineTo(cx + s, cy); path.lineTo(cx - s * 0.7f, cy + a); path.close();
      } else if (kind == 2) {
        cv.drawRect(cx - s * 0.85f, cy - a, cx - s * 0.2f, cy + a, p);
        cv.drawRect(cx + s * 0.2f, cy - a, cx + s * 0.85f, cy + a, p);
        return;
      } else if (kind == 0) {
        path.moveTo(cx - s, cy); path.lineTo(cx, cy - a); path.lineTo(cx, cy + a); path.close();
        path.moveTo(cx, cy); path.lineTo(cx + s, cy - a); path.lineTo(cx + s, cy + a); path.close();
      } else {
        path.moveTo(cx - s, cy - a); path.lineTo(cx - s, cy + a); path.lineTo(cx, cy); path.close();
        path.moveTo(cx, cy - a); path.lineTo(cx, cy + a); path.lineTo(cx + s, cy); path.close();
      }
      cv.drawPath(path, p);
    }
  }

  static class Dot extends View {
    boolean on, dark;
    final Paint q = new Paint(Paint.ANTI_ALIAS_FLAG);
    Dot(Context c, boolean o) { super(c); on = o; }
    @Override protected void onDraw(Canvas cv) {
      float w = getWidth(), h = getHeight(), r = Math.min(w, h) / 2f - 2f;
      int col = dark ? Color.BLACK : Color.WHITE;
      q.setStyle(Paint.Style.STROKE);
      q.setStrokeWidth(3f);
      q.setColor(on ? col : (dark ? 0x66000000 : 0x66FFFFFF));
      cv.drawCircle(w / 2f, h / 2f, r, q);
      if (on) { q.setStyle(Paint.Style.FILL); q.setColor(col); cv.drawCircle(w / 2f, h / 2f, r * 0.55f, q); }
    }
  }

  static class Seek extends View {
    float pos = 0f;
    final Paint q = new Paint(Paint.ANTI_ALIAS_FLAG);
    final RectF r = new RectF();
    Seek(Context c) { super(c); }
    @Override protected void onDraw(Canvas cv) {
      int w = getWidth(), h = getHeight();
      float th = h * 0.26f, cy = h / 2f, rad = th / 2f;
      q.setStyle(Paint.Style.FILL);
      q.setColor(0x40FFFFFF);
      r.set(0, cy - rad, w, cy + rad);
      cv.drawRoundRect(r, rad, rad, q);
      q.setColor(Color.WHITE);
      r.set(0, cy - rad, Math.max(th, w * pos), cy + rad);
      cv.drawRoundRect(r, rad, rad, q);
      float kx = Math.max(h / 2f, Math.min(w - h / 2f, w * pos));
      cv.drawCircle(kx, cy, h * 0.34f, q);
    }
  }

  private final Handler hnd = new Handler(Looper.getMainLooper());
  private String url = "", title = "", eng = "exo", ua = null;
  private boolean live, ar = true;
  private long startMs;

  private FrameLayout root;
  private AspectRatioFrameLayout frame;
  private SurfaceView surface;
  private SubtitleView subs;
  private VLCVideoLayout vlcLayout;
  private ProgressBar spin;
  private TextView tvMsg, tvTitle, tvBadge, tvT, tvD, tvHint;
  private LinearLayout bar;
  private Ico icRw, icPp, icFf;
  private Seek seek;

  private ExoPlayer exo;
  private Player.Listener exoL;
  private LibVLC vlcLib;
  private MediaPlayer vlc;
  private boolean vlcHw = true, vlcRetried, vlcPlayed, vlcBuf;
  private long vlcMoveAt, vlcLastT = -1;

  private boolean playing, paused, ended, failing, triedOther, done;
  private int dlgs = 0;
  private boolean switchInternal = false;
  private String errCode = "";
  private int zapDir = 0, fitMode = 0, vh = 0;
  private long lastT, lastD, seekTgt = -1, jumpAcc = 0, holdStart, lastSeekKey;

  private final Runnable tick = new Runnable() {
    public void run() {
      sample();
      if (vlc != null) vlcWatch();
      if (bar != null && bar.getVisibility() == View.VISIBLE) updateUi();
      hnd.postDelayed(this, 500);
    }
  };
  private final Runnable wd = new Runnable() { public void run() { if (!playing) postFail("STARTUP"); } };
  private final Runnable hideMsg = new Runnable() { public void run() { if (tvMsg != null) tvMsg.setVisibility(View.GONE); } };
  private final Runnable hideBar = new Runnable() {
    public void run() {
      if (paused || seekTgt >= 0 || dlgs > 0) { hnd.postDelayed(this, 1500); return; }
      bar.setVisibility(View.GONE);
      subs.setBottomPaddingFraction(0.08f);
    }
  };
  private final Runnable commitSeek = new Runnable() {
    public void run() {
      if (seekTgt < 0) return;
      long t = seekTgt;
      seekTgt = -1;
      lastT = t;
      doSeek(t);
      updateUi();
      hnd.removeCallbacks(clearJump);
      hnd.postDelayed(clearJump, 1400);
    }
  };
  private final Runnable clearJump = new Runnable() { public void run() { jumpAcc = 0; } };

  /* ---------------------------------------------------------------- setup */

  @Override
  protected void onCreate(Bundle b) {
    super.onCreate(b);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().setBackgroundDrawable(new ColorDrawable(Color.BLACK));
    hideSystem();
    Intent in = getIntent();
    String u = in.getStringExtra("url");
    url = u == null ? "" : u;
    String tt = in.getStringExtra("title");
    title = tt == null ? "" : tt;
    eng = "vlc".equals(in.getStringExtra("eng")) ? "vlc" : "exo";
    ua = in.getStringExtra("ua");
    live = in.getBooleanExtra("live", false);
    ar = in.getBooleanExtra("ar", true);
    startMs = in.getLongExtra("start", 0);
    build();
    begin(startMs);
  }

  private void hideSystem() {
    getWindow().getDecorView().setSystemUiVisibility(
      View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
  }

  @Override
  public void onWindowFocusChanged(boolean f) {
    super.onWindowFocusChanged(f);
    if (f) hideSystem();
  }

  private int dp(int v) { return (int) (v * getResources().getDisplayMetrics().density + 0.5f); }

  private TextView tv(float sp, int color, boolean bold) {
    TextView t = new TextView(this);
    t.setTextSize(sp);
    t.setTextColor(color);
    if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
    return t;
  }

  private void build() {
    root = new FrameLayout(this);
    root.setBackgroundColor(Color.BLACK);

    frame = new AspectRatioFrameLayout(this);
    surface = new SurfaceView(this);
    frame.addView(surface, new FrameLayout.LayoutParams(-1, -1));
    root.addView(frame, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));

    vlcLayout = new VLCVideoLayout(this);
    vlcLayout.setVisibility(View.GONE);
    root.addView(vlcLayout, new FrameLayout.LayoutParams(-1, -1));

    subs = new SubtitleView(this);
    subs.setApplyEmbeddedStyles(false);
    subs.setApplyEmbeddedFontSizes(false);
    subs.setStyle(new CaptionStyleCompat(Color.WHITE, Color.TRANSPARENT, Color.TRANSPARENT, CaptionStyleCompat.EDGE_TYPE_OUTLINE, Color.BLACK, null));
    subs.setFractionalTextSize(0.06f);
    subs.setBottomPaddingFraction(0.08f);
    root.addView(subs, new FrameLayout.LayoutParams(-1, -1));

    spin = new ProgressBar(this);
    spin.setVisibility(View.GONE);
    root.addView(spin, new FrameLayout.LayoutParams(dp(64), dp(64), Gravity.CENTER));

    tvMsg = tv(22, Color.WHITE, true);
    tvMsg.setPadding(dp(26), dp(12), dp(26), dp(12));
    GradientDrawable mg = new GradientDrawable();
    mg.setColor(0xE6000000);
    mg.setCornerRadius(dp(18));
    tvMsg.setBackground(mg);
    tvMsg.setVisibility(View.GONE);
    FrameLayout.LayoutParams ml = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    ml.topMargin = dp(36);
    root.addView(tvMsg, ml);

    bar = new LinearLayout(this);
    bar.setOrientation(LinearLayout.VERTICAL);
    bar.setPadding(dp(22), dp(8), dp(22), dp(10));
    GradientDrawable bg = new GradientDrawable();
    bg.setColor(0xDD181820);
    bg.setCornerRadius(dp(18));
    bar.setBackground(bg);

    LinearLayout top = new LinearLayout(this);
    top.setOrientation(LinearLayout.HORIZONTAL);
    tvTitle = tv(14, Color.WHITE, true);
    tvTitle.setSingleLine(true);
    tvTitle.setText(title);
    tvBadge = tv(12, 0xAAFFFFFF, false);
    top.addView(tvTitle, new LinearLayout.LayoutParams(0, -2, 1f));
    top.addView(tvBadge, new LinearLayout.LayoutParams(-2, -2));
    bar.addView(top, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout ic = new LinearLayout(this);
    ic.setOrientation(LinearLayout.HORIZONTAL);
    ic.setGravity(Gravity.CENTER);
    icRw = new Ico(this, 0);
    icPp = new Ico(this, 2);
    icFf = new Ico(this, 3);
    LinearLayout.LayoutParams il = new LinearLayout.LayoutParams(dp(72), dp(38));
    il.setMargins(dp(10), dp(4), dp(10), dp(4));
    LinearLayout.LayoutParams il2 = new LinearLayout.LayoutParams(dp(84), dp(38));
    il2.setMargins(dp(10), dp(4), dp(10), dp(4));
    if (!live) ic.addView(icRw, il);
    ic.addView(icPp, il2);
    if (!live) ic.addView(icFf, il);
    bar.addView(ic, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout tr = new LinearLayout(this);
    tr.setOrientation(LinearLayout.HORIZONTAL);
    tr.setGravity(Gravity.CENTER_VERTICAL);
    tvT = tv(16, Color.WHITE, true);
    tvT.setMinWidth(dp(70));
    tvT.setGravity(Gravity.CENTER);
    tvD = tv(16, 0xFFCFCFD4, true);
    tvD.setMinWidth(dp(70));
    tvD.setGravity(Gravity.CENTER);
    seek = new Seek(this);
    tr.addView(tvT, new LinearLayout.LayoutParams(-2, -2));
    tr.addView(seek, new LinearLayout.LayoutParams(0, dp(20), 1f));
    tr.addView(tvD, new LinearLayout.LayoutParams(-2, -2));
    if (live) seek.setVisibility(View.INVISIBLE);
    bar.addView(tr, new LinearLayout.LayoutParams(-1, -2));

    tvHint = tv(11, 0x80FFFFFF, false);
    tvHint.setGravity(Gravity.CENTER);
    tvHint.setPadding(0, dp(2), 0, 0);
    if (live) tvHint.setText(ar ? "↑ ↓  تغيير القناة    •    OK  إيقاف / تشغيل    •    رجوع  خروج" : "↑ ↓  Change channel    •    OK  Pause / Play    •    Back  Exit");
    else tvHint.setText(ar ? "← →  ترجيع / تقديم    •    OK  إيقاف / تشغيل    •    ↑  صوت وترجمة    •    رجوع  خروج" : "← →  Rewind / Forward    •    OK  Pause / Play    •    ↑  Audio & subtitles    •    Back  Exit");
    bar.addView(tvHint, new LinearLayout.LayoutParams(-1, -2));

    FrameLayout.LayoutParams bl = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
    int sw = getResources().getDisplayMetrics().widthPixels;
    bl.setMargins(sw / 6, 0, sw / 6, dp(22));
    root.addView(bar, bl);

    setContentView(root);
  }

  /* --------------------------------------------------------------- engines */

  private void begin(long pos) {
    releaseAll();
    errCode = "";
    failing = false;
    try {
      if ("vlc".equals(eng)) startVlc(pos); else startExo(pos);
    } catch (Throwable e) {
      postFail("INIT");
      return;
    }
    hnd.removeCallbacks(tick);
    hnd.post(tick);
    hnd.removeCallbacks(wd);
    hnd.postDelayed(wd, 25000);
    setSpin(true);
    updateBadge();
    showBar();
  }

  private void startExo(long pos) {
    frame.setVisibility(View.VISIBLE);
    subs.setVisibility(View.VISIBLE);
    vlcLayout.setVisibility(View.GONE);
    DefaultLoadControl lc = new DefaultLoadControl.Builder().setBufferDurationsMs(15000, 60000, 2500, 5000).build();
    DefaultHttpDataSource.Factory hf = new DefaultHttpDataSource.Factory()
      .setAllowCrossProtocolRedirects(true)
      .setConnectTimeoutMs(15000)
      .setReadTimeoutMs(30000);
    if (ua != null && ua.length() > 0) hf.setUserAgent(ua);
    exo = new ExoPlayer.Builder(this, new DefaultRenderersFactory(this).setEnableDecoderFallback(true))
      .setMediaSourceFactory(new DefaultMediaSourceFactory(new DefaultDataSource.Factory(this, hf)))
      .setLoadControl(lc)
      .build();
    exo.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true);
    exo.setVideoSurfaceView(surface);
    exo.setTrackSelectionParameters(exo.getTrackSelectionParameters().buildUpon().setPreferredTextLanguage("ar").build());
    applyFit();
    exoL = new Player.Listener() {
      @Override public void onPlaybackStateChanged(int st) {
        if (exo == null) return;
        if (st == Player.STATE_BUFFERING) setSpin(true);
        else if (st == Player.STATE_READY) { setSpin(false); playing = true; }
        else if (st == Player.STATE_ENDED) {
          if (live) { postFail("ENDED"); return; }
          sample();
          ended = true;
          finishOut();
        }
      }
      @Override public void onPlayWhenReadyChanged(boolean pw, int reason) { paused = !pw; updateUi(); }
      @Override public void onVideoSizeChanged(VideoSize vs) {
        if (vs.height > 0) frame.setAspectRatio(vs.width * vs.pixelWidthHeightRatio / vs.height);
        vh = vs.height;
        updateBadge();
      }
      @Override public void onCues(CueGroup g) { subs.setCues(g.cues); }
      @Override public void onTracksChanged(Tracks t) {
        if (exo == null) return;
        int na = 0, aok = 0, nv = 0, vok = 0;
        for (Tracks.Group g : t.getGroups()) {
          int ty = g.getType();
          for (int i = 0; i < g.length; i++) {
            if (ty == C.TRACK_TYPE_AUDIO) { na++; if (g.isTrackSupported(i)) aok++; }
            else if (ty == C.TRACK_TYPE_VIDEO) { nv++; if (g.isTrackSupported(i)) vok++; }
          }
        }
        if (na > 0 && aok == 0) postFail("NOAUDIO");
        else if (nv > 0 && vok == 0) postFail("NOVIDEO");
      }
      @Override public void onPlayerError(PlaybackException e) {
        if (exo == null) return;
        if (e.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) { exo.seekToDefaultPosition(); exo.prepare(); return; }
        postFail(e.getErrorCodeName());
      }
    };
    exo.addListener(exoL);
    exo.setMediaItem(MediaItem.fromUri(url), pos > 0 ? pos : C.TIME_UNSET);
    exo.prepare();
    exo.setPlayWhenReady(true);
  }

  private final MediaPlayer.EventListener vlcEv = new MediaPlayer.EventListener() {
    public void onEvent(MediaPlayer.Event e) {
      if (vlc == null) return;
      switch (e.type) {
        case MediaPlayer.Event.Buffering:
          vlcBuf = e.getBuffering() < 100f;
          setSpin(vlcBuf);
          break;
        case MediaPlayer.Event.Playing:
          playing = true; paused = false; vlcBuf = false; setSpin(false); updateUi();
          break;
        case MediaPlayer.Event.Paused:
          paused = true; updateUi();
          break;
        case MediaPlayer.Event.EndReached:
          if (live) { postFail("ENDED"); break; }
          sample();
          ended = true;
          finishOut();
          break;
        case MediaPlayer.Event.EncounteredError:
          postFail("ERROR");
          break;
        default:
          break;
      }
    }
  };

  private MediaPlayer.ScaleType vlcScale() {
    return fitMode == 1 ? MediaPlayer.ScaleType.SURFACE_FIT_SCREEN : fitMode == 2 ? MediaPlayer.ScaleType.SURFACE_FILL : MediaPlayer.ScaleType.SURFACE_BEST_FIT;
  }

  private void startVlc(long pos) {
    frame.setVisibility(View.GONE);
    subs.setVisibility(View.GONE);
    vlcLayout.setVisibility(View.VISIBLE);
    if (vlcLib == null) {
      ArrayList<String> o = new ArrayList<String>();
      o.add("--http-reconnect");
      o.add("--audio-time-stretch");
      vlcLib = new LibVLC(this, o);
    }
    vlc = new MediaPlayer(vlcLib);
    vlc.attachViews(vlcLayout, null, true, false);
    vlc.setVideoScale(vlcScale());
    vlc.setEventListener(vlcEv);
    Media m = new Media(vlcLib, Uri.parse(url));
    m.setHWDecoderEnabled(vlcHw, false);
    m.addOption(":network-caching=" + (live ? 1500 : 3000));
    if (ua != null && ua.length() > 0) m.addOption(":http-user-agent=" + ua);
    if (pos > 0) m.addOption(":start-time=" + (pos / 1000));
    vlc.setMedia(m);
    m.release();
    vlcMoveAt = SystemClock.uptimeMillis();
    vlcLastT = -1;
    vlcPlayed = false;
    vlcBuf = false;
    vlc.play();
  }

  private void vlcWatch() {
    if (vlc == null) return;
    long now = SystemClock.uptimeMillis();
    long t = vlc.getTime();
    if (t > 0 && t != vlcLastT) { vlcLastT = t; vlcMoveAt = now; vlcPlayed = true; }
    else if (vlcBuf || !vlc.isPlaying()) vlcMoveAt = now;
    else if (vlcPlayed && now - vlcMoveAt > 9000) postFail("FROZEN");
  }

  private void releaseAll() {
    hnd.removeCallbacks(wd);
    if (exo != null) {
      try { if (exoL != null) exo.removeListener(exoL); } catch (Throwable e) {}
      try { exo.clearVideoSurface(); } catch (Throwable e) {}
      try { exo.stop(); exo.clearMediaItems(); } catch (Throwable e) {}
      try { exo.release(); } catch (Throwable e) {}
      exo = null;
    }
    exoL = null;
    if (subs != null) subs.setCues(java.util.Collections.<androidx.media3.common.text.Cue>emptyList());
    final MediaPlayer p = vlc;
    vlc = null;
    if (p != null) {
      try { p.setEventListener(null); } catch (Throwable e) {}
      try { p.detachViews(); } catch (Throwable e) {}
      new Thread(new Runnable() { public void run() {
        try { p.stop(); } catch (Throwable e) {}
        try { p.release(); } catch (Throwable e) {}
      } }).start();
    }
    playing = false;
    paused = false;
    vlcPlayed = false;
    vlcBuf = false;
    vlcLastT = -1;
  }

  private void postFail(final String code) {
    if (failing || done) return;
    failing = true;
    hnd.post(new Runnable() { public void run() { fail(code); } });
  }

  /* HW decode -> software retry (VLC), then the other engine, then report to the app */
  private void fail(String code) {
    sample();
    long pos = lastT > 0 ? lastT : startMs;
    if ("vlc".equals(eng) && vlcHw && !vlcRetried) {
      vlcRetried = true;
      vlcHw = false;
      toast(ar ? "إعادة المحاولة بالمعالجة البرمجية…" : "Retrying with software decoding…", 2500);
      begin(pos);
      return;
    }
    if (!triedOther) {
      triedOther = true;
      eng = "vlc".equals(eng) ? "exo" : "vlc";
      vlcHw = true;
      vlcRetried = false;
      toast((ar ? "تبديل المشغّل إلى " : "Switching player to ") + ("vlc".equals(eng) ? "VLC" : "ExoPlayer"), 2500);
      begin(pos);
      return;
    }
    errCode = code == null ? "ERR" : code;
    finishOut();
  }

  private void finishOut() {
    if (done) return;
    done = true;
    sample();
    Intent r = new Intent();
    r.putExtra("t", lastT);
    r.putExtra("d", lastD);
    r.putExtra("end", ended);
    r.putExtra("zap", zapDir);
    r.putExtra("err", errCode);
    r.putExtra("sw", switchInternal ? "internal" : "");
    setResult(RESULT_OK, r);
    finish();
  }

  /* ------------------------------------------------------------- playback */

  private void sample() {
    try {
      if (exo != null) {
        lastT = Math.max(0, exo.getCurrentPosition());
        long d = exo.getDuration();
        lastD = (live || d == C.TIME_UNSET || exo.isCurrentMediaItemLive()) ? 0 : d;
      } else if (vlc != null) {
        long t = vlc.getTime();
        if (t >= 0) lastT = t;
        long d = vlc.getLength();
        lastD = (!live && d > 0 && vlc.isSeekable()) ? d : 0;
      }
    } catch (Throwable e) {}
  }

  private void doSeek(long ms) {
    try {
      if (exo != null) exo.seekTo(Math.max(0, ms));
      else if (vlc != null) vlc.setTime(Math.max(0, ms));
    } catch (Throwable e) {}
  }

  private void togglePause() {
    try {
      if (exo != null) {
        if (exo.getPlayWhenReady()) exo.pause(); else exo.play();
        paused = !exo.getPlayWhenReady();
      } else if (vlc != null) {
        if (vlc.isPlaying()) { vlc.pause(); paused = true; } else { vlc.play(); paused = false; }
      }
    } catch (Throwable e) {}
    flash(icPp);
    showBar();
  }

  private void seekBy(int dir, boolean rep, int base) {
    showBar();
    flash(dir > 0 ? icFf : icRw);
    if (live || lastD <= 0) {
      toast(live ? (ar ? "بث مباشر — التقديم غير متاح" : "Live — seeking not available") : (ar ? "المدة غير معروفة بعد" : "Duration not known yet"), 1800);
      return;
    }
    long now = SystemClock.uptimeMillis();
    if (!rep) holdStart = now;
    else if (now - lastSeekKey < 300) return;
    lastSeekKey = now;
    long hold = now - holdStart;
    int step = rep ? Math.min(60, hold > 4000 ? base * 3 : hold > 2000 ? base * 2 : base) : base;
    long cur = seekTgt >= 0 ? seekTgt : lastT;
    long tg = Math.max(0, Math.min(cur + dir * step * 1000L, Math.max(0, lastD - 1000)));
    jumpAcc += tg - cur;
    seekTgt = tg;
    hnd.removeCallbacks(clearJump);
    long secs = Math.abs(jumpAcc) / 1000;
    toast((jumpAcc >= 0 ? "+" : "−") + secs + (ar ? " ث" : "s") + "   •   " + fmt(tg), 1500);
    updateUi();
    hnd.removeCallbacks(commitSeek);
    hnd.postDelayed(commitSeek, rep ? 450 : 250);
  }

  private void zap(int d) {
    zapDir = d;
    finishOut();
  }

  private void applyFit() {
    try {
      frame.setResizeMode(fitMode == 1 ? AspectRatioFrameLayout.RESIZE_MODE_ZOOM : fitMode == 2 ? AspectRatioFrameLayout.RESIZE_MODE_FILL : AspectRatioFrameLayout.RESIZE_MODE_FIT);
      if (vlc != null) vlc.setVideoScale(vlcScale());
    } catch (Throwable e) {}
  }

  /* ------------------------------------------------------------------- UI */

  private static String two(long n) { return n < 10 ? "0" + n : String.valueOf(n); }

  private static String fmt(long ms) {
    long s = Math.max(0, ms / 1000), h = s / 3600, m = (s % 3600) / 60, x = s % 60;
    return (h > 0 ? h + ":" + two(m) : String.valueOf(m)) + ":" + two(x);
  }

  private void flash(final Ico ic) {
    ic.hit = true;
    ic.invalidate();
    hnd.postDelayed(new Runnable() { public void run() { ic.hit = false; ic.invalidate(); } }, 260);
  }

  private void toast(String s, int ms) {
    tvMsg.setText(s);
    tvMsg.setVisibility(View.VISIBLE);
    hnd.removeCallbacks(hideMsg);
    hnd.postDelayed(hideMsg, ms);
  }

  private void setSpin(boolean on) { if (spin != null) spin.setVisibility(on ? View.VISIBLE : View.GONE); }

  private void updateBadge() {
    String b = "vlc".equals(eng) ? "VLC" + (vlcHw ? " · HW" : " · SW") : "ExoPlayer" + (vh > 0 ? " · " + vh + "p" : "");
    tvBadge.setText(b);
  }

  private void updateUi() {
    long t = seekTgt >= 0 ? seekTgt : lastT;
    tvT.setText(fmt(t));
    if (live) tvD.setText(ar ? "مباشر" : "LIVE");
    else tvD.setText(lastD > 0 ? fmt(lastD) : "--:--");
    seek.pos = lastD > 0 ? Math.min(1f, Math.max(0f, (float) t / (float) lastD)) : 0f;
    seek.invalidate();
    int k = paused ? 1 : 2;
    if (icPp.kind != k) { icPp.kind = k; icPp.invalidate(); }
  }

  private void showBar() {
    updateUi();
    bar.setVisibility(View.VISIBLE);
    subs.setBottomPaddingFraction(0.22f);
    hnd.removeCallbacks(hideBar);
    hnd.postDelayed(hideBar, 4000);
  }

  /* ----------------------------------------------------- audio / subtitles */

  private ArrayList<Object[]> exoTracks(int ty) {
    ArrayList<Object[]> l = new ArrayList<Object[]>();
    if (exo == null) return l;
    try {
      for (Tracks.Group g : exo.getCurrentTracks().getGroups()) {
        if (g.getType() != ty) continue;
        for (int i = 0; i < g.length; i++) {
          if (!g.isTrackSupported(i)) continue;
          Format f = g.getTrackFormat(i);
          String n = f.label;
          if (n == null && f.language != null && !"und".equals(f.language)) n = new java.util.Locale(f.language).getDisplayLanguage();
          if (n == null) n = "#" + (l.size() + 1);
          if (ty == C.TRACK_TYPE_AUDIO && f.channelCount > 2) n += " " + f.channelCount + "ch";
          l.add(new Object[]{g.getMediaTrackGroup(), Integer.valueOf(i), n, Boolean.valueOf(g.isTrackSelected(i))});
        }
      }
    } catch (Throwable e) {}
    return l;
  }

  private void exoPickTrack(int ty, ArrayList<Object[]> l, int idx) {
    if (exo == null) return;
    TrackSelectionParameters.Builder b = exo.getTrackSelectionParameters().buildUpon();
    if (idx < 0 || idx >= l.size()) {
      b.setTrackTypeDisabled(ty, true);
    } else {
      Object[] e = l.get(idx);
      b.setTrackTypeDisabled(ty, false).setOverrideForType(new TrackSelectionOverride((TrackGroup) e[0], ((Integer) e[1]).intValue()));
    }
    exo.setTrackSelectionParameters(b.build());
  }

  private void pickList(String ttl, ArrayList<String> names, int checked, final Pick p) { sheet(ttl, names, checked, p); }

  /* dark glass option sheet, remote friendly */
  private void sheet(String ttl, ArrayList<String> names, int checked, final Pick p) {
    final Dialog d = new Dialog(this, android.R.style.Theme_Translucent_NoTitleBar);
    LinearLayout panel = new LinearLayout(this);
    panel.setOrientation(LinearLayout.VERTICAL);
    panel.setPadding(dp(22), dp(18), dp(22), dp(14));
    GradientDrawable pg = new GradientDrawable();
    pg.setColor(0xF2202026);
    pg.setCornerRadius(dp(24));
    pg.setStroke(dp(1), 0x33FFFFFF);
    panel.setBackground(pg);
    TextView t = tv(17, Color.WHITE, true);
    t.setText(ttl);
    t.setSingleLine(true);
    t.setPadding(dp(10), dp(2), dp(10), dp(10));
    panel.addView(t, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout list = new LinearLayout(this);
    list.setOrientation(LinearLayout.VERTICAL);
    View focusMe = null;
    for (int i = 0; i < names.size(); i++) {
      final int idx = i;
      final boolean on = i == checked;
      final LinearLayout row = new LinearLayout(this);
      row.setOrientation(LinearLayout.HORIZONTAL);
      row.setGravity(Gravity.CENTER_VERTICAL);
      row.setPadding(dp(16), dp(11), dp(16), dp(11));
      row.setFocusable(true);
      row.setFocusableInTouchMode(true);
      row.setClickable(true);
      final GradientDrawable nb = new GradientDrawable();
      nb.setColor(0x14FFFFFF);
      nb.setCornerRadius(dp(15));
      final GradientDrawable fb = new GradientDrawable();
      fb.setColor(Color.WHITE);
      fb.setCornerRadius(dp(15));
      row.setBackground(nb);
      final Dot dot = new Dot(this, on);
      LinearLayout.LayoutParams dl = new LinearLayout.LayoutParams(dp(20), dp(20));
      dl.setMarginEnd(dp(14));
      row.addView(dot, dl);
      final TextView tx = tv(15, Color.WHITE, on);
      tx.setText(names.get(i));
      row.addView(tx, new LinearLayout.LayoutParams(0, -2, 1f));
      row.setOnFocusChangeListener(new View.OnFocusChangeListener() {
        public void onFocusChange(View v, boolean f) {
          row.setBackground(f ? fb : nb);
          tx.setTextColor(f ? Color.BLACK : Color.WHITE);
          dot.dark = f;
          dot.invalidate();
        }
      });
      row.setOnClickListener(new View.OnClickListener() {
        public void onClick(View v) { d.dismiss(); p.on(idx); }
      });
      LinearLayout.LayoutParams rl = new LinearLayout.LayoutParams(-1, -2);
      rl.topMargin = dp(6);
      list.addView(row, rl);
      if (focusMe == null || on) focusMe = row;
    }
    ScrollView sv = new ScrollView(this);
    sv.setVerticalScrollBarEnabled(false);
    sv.addView(list, new FrameLayout.LayoutParams(-1, -2));
    panel.addView(sv, new LinearLayout.LayoutParams(-1, -2));
    d.setContentView(panel);
    Window w = d.getWindow();
    if (w != null) {
      int sw = getResources().getDisplayMetrics().widthPixels;
      w.setLayout(Math.min(dp(520), (int) (sw * 0.8f)), WindowManager.LayoutParams.WRAP_CONTENT);
      w.setGravity(Gravity.CENTER);
      w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
      w.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
      w.setDimAmount(0.55f);
    }
    final View fm = focusMe;
    d.setOnShowListener(new DialogInterface.OnShowListener() {
      public void onShow(DialogInterface x) { if (fm != null) fm.requestFocus(); }
    });
    d.setOnDismissListener(new DialogInterface.OnDismissListener() {
      public void onDismiss(DialogInterface x) { dlgs--; hideSystem(); }
    });
    dlgs++;
    d.show();
  }

  private void audioMenu() {
    final ArrayList<String> names = new ArrayList<String>();
    int cur = -1;
    if (exo != null) {
      final ArrayList<Object[]> l = exoTracks(C.TRACK_TYPE_AUDIO);
      for (int i = 0; i < l.size(); i++) { names.add((String) l.get(i)[2]); if (((Boolean) l.get(i)[3]).booleanValue()) cur = i; }
      if (names.isEmpty()) { toast(ar ? "لا توجد مسارات صوت" : "No audio tracks", 1800); return; }
      pickList(ar ? "الصوت" : "Audio", names, cur, new Pick() { public void on(int i) { exoPickTrack(C.TRACK_TYPE_AUDIO, l, i); } });
    } else if (vlc != null) {
      final ArrayList<Integer> ids = new ArrayList<Integer>();
      MediaPlayer.TrackDescription[] a = vlc.getAudioTracks();
      int ca = vlc.getAudioTrack();
      if (a != null) for (MediaPlayer.TrackDescription x : a) {
        if (x.id < 0) continue;
        if (x.id == ca) cur = ids.size();
        ids.add(Integer.valueOf(x.id));
        names.add(x.name == null ? "#" + ids.size() : x.name);
      }
      if (names.isEmpty()) { toast(ar ? "لا توجد مسارات صوت" : "No audio tracks", 1800); return; }
      pickList(ar ? "الصوت" : "Audio", names, cur, new Pick() { public void on(int i) { if (vlc != null && i >= 0 && i < ids.size()) vlc.setAudioTrack(ids.get(i).intValue()); } });
    }
  }

  private void subMenu() {
    final ArrayList<String> names = new ArrayList<String>();
    names.add(ar ? "بدون ترجمة" : "Off");
    int cur = 0;
    if (exo != null) {
      final ArrayList<Object[]> l = exoTracks(C.TRACK_TYPE_TEXT);
      boolean off = exo.getTrackSelectionParameters().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT);
      for (int i = 0; i < l.size(); i++) { names.add((String) l.get(i)[2]); if (!off && ((Boolean) l.get(i)[3]).booleanValue()) cur = i + 1; }
      if (names.size() == 1) { toast(ar ? "لا توجد ترجمة مدمجة بالملف" : "No embedded subtitles", 2000); return; }
      pickList(ar ? "الترجمة" : "Subtitles", names, cur, new Pick() { public void on(int i) { exoPickTrack(C.TRACK_TYPE_TEXT, l, i - 1); } });
    } else if (vlc != null) {
      final ArrayList<Integer> ids = new ArrayList<Integer>();
      MediaPlayer.TrackDescription[] s = vlc.getSpuTracks();
      int cs = vlc.getSpuTrack();
      if (s != null) for (MediaPlayer.TrackDescription x : s) {
        if (x.id < 0) continue;
        if (x.id == cs) cur = ids.size() + 1;
        ids.add(Integer.valueOf(x.id));
        names.add(x.name == null ? "#" + ids.size() : x.name);
      }
      if (names.size() == 1) { toast(ar ? "لا توجد ترجمة مدمجة بالملف" : "No embedded subtitles", 2000); return; }
      pickList(ar ? "الترجمة" : "Subtitles", names, cur, new Pick() { public void on(int i) { if (vlc != null) vlc.setSpuTrack(i <= 0 || i > ids.size() ? -1 : ids.get(i - 1).intValue()); } });
    }
  }

  private void openMenu() {
    if (dlgs > 0) return;
    final ArrayList<String> names = new ArrayList<String>();
    final ArrayList<Runnable> acts = new ArrayList<Runnable>();
    names.add(ar ? "الصوت" : "Audio");
    acts.add(new Runnable() { public void run() { audioMenu(); } });
    names.add(ar ? "الترجمة" : "Subtitles");
    acts.add(new Runnable() { public void run() { subMenu(); } });
    names.add((ar ? "ملاءمة الشاشة: " : "Aspect: ") + (fitMode == 0 ? (ar ? "ملاءمة" : "Fit") : fitMode == 1 ? (ar ? "تكبير" : "Zoom") : (ar ? "تمديد" : "Stretch")));
    acts.add(new Runnable() { public void run() { fitMode = (fitMode + 1) % 3; applyFit(); toast(ar ? "تم تغيير الملاءمة" : "Aspect changed", 1200); } });
    names.add((ar ? "تبديل المشغّل إلى " : "Switch player to ") + ("vlc".equals(eng) ? "ExoPlayer" : "VLC"));
    acts.add(new Runnable() { public void run() {
      sample();
      eng = "vlc".equals(eng) ? "exo" : "vlc";
      vlcHw = true; vlcRetried = false; triedOther = false;
      begin(lastT);
    } });
    names.add(ar ? "الرجوع للمشغّل الداخلي (داخل التطبيق)" : "Back to the in-app player");
    acts.add(new Runnable() { public void run() { switchInternal = true; finishOut(); } });
    names.add(ar ? "إغلاق" : "Close");
    acts.add(new Runnable() { public void run() {} });
    sheet(title.length() > 0 ? title : "Hala TV", names, -1, new Pick() {
      public void on(int w) { if (w >= 0 && w < acts.size()) acts.get(w).run(); }
    });
  }

  /* ----------------------------------------------------------------- keys */

  @Override
  public boolean onKeyDown(int kc, KeyEvent e) {
    boolean rep = e.getRepeatCount() > 0;
    switch (kc) {
      case KeyEvent.KEYCODE_DPAD_RIGHT: seekBy(1, rep, 10); return true;
      case KeyEvent.KEYCODE_DPAD_LEFT: seekBy(-1, rep, 10); return true;
      case KeyEvent.KEYCODE_MEDIA_FAST_FORWARD: seekBy(1, rep, 30); return true;
      case KeyEvent.KEYCODE_MEDIA_REWIND: seekBy(-1, rep, 30); return true;
      case KeyEvent.KEYCODE_DPAD_CENTER:
      case KeyEvent.KEYCODE_ENTER:
      case KeyEvent.KEYCODE_NUMPAD_ENTER:
      case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
      case KeyEvent.KEYCODE_SPACE:
        if (!rep) togglePause();
        return true;
      case KeyEvent.KEYCODE_MEDIA_PLAY:
        if (!rep && paused) togglePause();
        return true;
      case KeyEvent.KEYCODE_MEDIA_PAUSE:
        if (!rep && !paused) togglePause();
        return true;
      case KeyEvent.KEYCODE_DPAD_UP:
        if (!rep) { if (live) zap(-1); else openMenu(); }
        return true;
      case KeyEvent.KEYCODE_DPAD_DOWN:
        if (!rep) { if (live) zap(1); else showBar(); }
        return true;
      case KeyEvent.KEYCODE_CHANNEL_UP:
      case KeyEvent.KEYCODE_PAGE_UP:
        if (!rep && live) zap(-1);
        return true;
      case KeyEvent.KEYCODE_CHANNEL_DOWN:
      case KeyEvent.KEYCODE_PAGE_DOWN:
        if (!rep && live) zap(1);
        return true;
      case KeyEvent.KEYCODE_MENU:
      case 175:
      case 222:
        if (!rep) openMenu();
        return true;
      default:
        return super.onKeyDown(kc, e);
    }
  }

  @Override
  public void onBackPressed() {
    finishOut();
  }

  @Override
  protected void onPause() {
    sample();
    try { if (exo != null) exo.pause(); } catch (Throwable e) {}
    try { if (vlc != null) vlc.pause(); } catch (Throwable e) {}
    paused = true;
    super.onPause();
  }

  @Override
  protected void onDestroy() {
    hnd.removeCallbacksAndMessages(null);
    done = true;
    releaseAll();
    if (vlcLib != null) { try { vlcLib.release(); } catch (Throwable e) {} vlcLib = null; }
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
import os
os.makedirs('android/app/src/main/res/drawable-nodpi', exist_ok=True)
k = 324.0 / logo.height
sl = logo.resize((max(1, int(logo.width * k)), 324), Image.LANCZOS)
sl.save('android/app/src/main/res/drawable-nodpi/splash_logo.png')
EOF
python3 -c 'import PIL' 2>/dev/null || pip install pillow || pip install --break-system-packages pillow
python3 android/gen.py
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null || true
(cd android && gradle assembleDebug --no-daemon --console=plain --stacktrace)
cp android/app/build/outputs/apk/debug/app-debug.apk hala-tv.apk
