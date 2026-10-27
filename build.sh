set -e
[ -f logo.png ] || { echo 'ERROR: logo.png is missing next to build.sh - upload it to the repo root'; exit 1; }
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
  compileSdk 35
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
  private SurfaceView exoSurface;
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
    exoSurface = new SurfaceView(this);
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
    exo.setVideoSurfaceView(exoSurface);
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
    vlc.attachViews(vlcLayout, null, true, false);
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
    if (exo != null) exo.pause();
    if (vlc != null) vlc.pause();
    super.onPause();
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
    exoRelease();
    vlcRelease();
    if (vlcLib != null) { try { vlcLib.release(); } catch (Throwable e) {} }
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
