set -e
if [ ! -f logo.png ]; then for L in logo_png.JPG logo_png.jpg logo.JPG logo.jpg logo.jpeg; do [ -f "$L" ] && { cp "$L" logo.png; break; }; done; fi
[ -f logo.png ] || { echo 'ERROR: logo.png is missing next to build.sh - upload it to the repo root'; exit 1; }
mkdir -p android/app/src/main/res/xml android/app/src/main/java/com/hala/tv android/app/src/main/assets android/app/src/main/res/drawable android/app/src/main/res/mipmap-xxhdpi
cp index.html android/app/src/main/assets/index.html
BUILD_TS=$(date -u '+%Y-%m-%d %H:%M')
sed -i "s|__OS_KEY__|${OS_KEY:-}|g;s|__OS_USER__|${OS_USER:-}|g;s|__OS_PASS__|${OS_PASS:-}|g;s|__TMDB_KEY__|${TMDB_KEY:-}|g;s|__PAIR_URL__|${PAIR_URL:-https://meplatformteam-cmd.github.io/Hala-tv/index.html}|g;s|__APP_VER__|${APP_VER:-}|g;s|__BUILD__|${BUILD_TS}|g;s|__SUB_SRV__|${SUB_SRV:-}|g;s|__STT_KEY__|${STT_KEY:-}|g;s|__AI_KEY__|${AI_KEY:-}|g;s|__AI_PROV__|${AI_PROV:-}|g" android/app/src/main/assets/index.html
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
cat > android/app/src/main/java/com/hala/tv/NetWatch.java <<'EOF'
package com.hala.tv;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import java.util.HashMap;

/* Instant "internet lost / back" signal straight from Android (validated networks), debounced.
   It is only a trigger: the web layer confirms with a real multi-host probe before showing anything. */
public class NetWatch {
  public interface Cb { void on(boolean up); }

  private final ConnectivityManager cm;
  private final Handler h = new Handler(Looper.getMainLooper());
  private final HashMap<Network, Boolean> nets = new HashMap<Network, Boolean>();
  private final Cb cb;
  private ConnectivityManager.NetworkCallback cbk;
  private int last = -1;
  private final Runnable chk = new Runnable() { public void run() { push(); } };

  public NetWatch(Context c, Cb cb) {
    this.cb = cb;
    ConnectivityManager m = null;
    try { m = (ConnectivityManager) c.getSystemService(Context.CONNECTIVITY_SERVICE); } catch (Throwable e) {}
    cm = m;
  }

  private boolean anyUp() {
    synchronized (nets) {
      for (Boolean b : nets.values()) if (b.booleanValue()) return true;
    }
    return false;
  }

  private void eval() {
    h.removeCallbacks(chk);
    if (anyUp()) h.post(chk); else h.postDelayed(chk, 1500);
  }

  private void push() {
    int now = anyUp() ? 1 : 0;
    if (now == last) return;
    last = now;
    if (cb != null) { try { cb.on(now == 1); } catch (Throwable e) {} }
  }

  public void start() {
    if (cm == null || cbk != null) return;
    try {
      cbk = new ConnectivityManager.NetworkCallback() {
        @Override public void onAvailable(Network n) {
          synchronized (nets) { if (!nets.containsKey(n)) nets.put(n, Boolean.valueOf(Build.VERSION.SDK_INT < 23)); }
          eval();
        }
        @Override public void onCapabilitiesChanged(Network n, NetworkCapabilities nc) {
          boolean ok = Build.VERSION.SDK_INT < 23 || nc.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
          synchronized (nets) { nets.put(n, Boolean.valueOf(ok)); }
          eval();
        }
        @Override public void onLost(Network n) {
          synchronized (nets) { nets.remove(n); }
          eval();
        }
      };
      NetworkRequest rq = new NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build();
      cm.registerNetworkCallback(rq, cbk);
    } catch (Throwable e) { cbk = null; }
  }

  public void stop() {
    h.removeCallbacksAndMessages(null);
    try { if (cm != null && cbk != null) cm.unregisterNetworkCallback(cbk); } catch (Throwable e) {}
    cbk = null;
  }
}
EOF
cat > android/app/src/main/java/com/hala/tv/Perf.java <<'EOF'
package com.hala.tv;

import android.app.ActivityManager;
import android.app.UiModeManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.util.DisplayMetrics;
import android.view.InputDevice;
import androidx.media3.common.MediaItem;
import androidx.media3.exoplayer.DefaultLoadControl;
import org.json.JSONObject;

/** Device detection + adaptive buffering. One place, used by the WebView bridge and both players. */
public final class Perf {
  private Perf() {}

  private static int tierCache = -1;

  public static long ramMb(Context c) {
    try {
      ActivityManager am = (ActivityManager) c.getSystemService(Context.ACTIVITY_SERVICE);
      ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
      am.getMemoryInfo(mi);
      return mi.totalMem / (1024L * 1024L);
    } catch (Throwable e) { return 0; }
  }

  /** 0 = weak, 1 = middle, 2 = strong. Decided from RAM, cores and Android version. */
  public static int tier(Context c) {
    if (tierCache >= 0) return tierCache;
    int t = 1;
    try {
      long ram = ramMb(c);
      int cores = Runtime.getRuntime().availableProcessors();
      boolean lowRam = false;
      try { lowRam = ((ActivityManager) c.getSystemService(Context.ACTIVITY_SERVICE)).isLowRamDevice(); } catch (Throwable e) {}
      if (lowRam || (ram > 0 && ram <= 1800) || Build.VERSION.SDK_INT <= 22 || cores <= 2) t = 0;
      else if (ram >= 3500 && cores >= 6 && Build.VERSION.SDK_INT >= 28) t = 2;
      else t = 1;
    } catch (Throwable e) {}
    tierCache = t;
    return t;
  }

  private static String netType(Context c) {
    try {
      ConnectivityManager cm = (ConnectivityManager) c.getSystemService(Context.CONNECTIVITY_SERVICE);
      if (Build.VERSION.SDK_INT >= 23) {
        NetworkCapabilities nc = cm.getNetworkCapabilities(cm.getActiveNetwork());
        if (nc == null) return "none";
        if (nc.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) return "eth";
        if (nc.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return "wifi";
        if (nc.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return "cell";
        return "other";
      }
      android.net.NetworkInfo ni = cm.getActiveNetworkInfo();
      if (ni == null || !ni.isConnected()) return "none";
      int ty = ni.getType();
      return ty == ConnectivityManager.TYPE_WIFI ? "wifi" : ty == ConnectivityManager.TYPE_ETHERNET ? "eth" : ty == ConnectivityManager.TYPE_MOBILE ? "cell" : "other";
    } catch (Throwable e) { return "?"; }
  }

  private static boolean hasDpad() {
    try {
      for (int id : InputDevice.getDeviceIds()) {
        InputDevice d = InputDevice.getDevice(id);
        if (d != null && (d.getSources() & InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD && !d.isVirtual()) return true;
      }
    } catch (Throwable e) {}
    return false;
  }

  /** Everything the web layer needs to pick its UI. Cheap, safe to call at startup. */
  public static String deviceJson(Context c) {
    JSONObject o = new JSONObject();
    try {
      DisplayMetrics dm = c.getResources().getDisplayMetrics();
      float dens = dm.density > 0 ? dm.density : 1f;
      float wdp = dm.widthPixels / dens, hdp = dm.heightPixels / dens;
      float swdp = Math.min(wdp, hdp), lwdp = Math.max(wdp, hdp);
      PackageManager pm = c.getPackageManager();
      boolean leanback = pm.hasSystemFeature("android.software.leanback") || pm.hasSystemFeature("android.hardware.type.television");
      boolean touch = pm.hasSystemFeature("android.hardware.touchscreen");
      int ui = Configuration.UI_MODE_TYPE_NORMAL;
      try { ui = ((UiModeManager) c.getSystemService(Context.UI_MODE_SERVICE)).getCurrentModeType(); } catch (Throwable e) {}
      String uis = ui == Configuration.UI_MODE_TYPE_TELEVISION ? "tv" : ui == Configuration.UI_MODE_TYPE_WATCH ? "watch" : ui == Configuration.UI_MODE_TYPE_CAR ? "car" : ui == Configuration.UI_MODE_TYPE_DESK ? "desk" : "normal";
      boolean dpad = hasDpad();
      String cls;
      if ("tv".equals(uis) || leanback) cls = "tv";
      else if (!touch && lwdp >= 900f) cls = "tv";
      else if (swdp >= 600f) cls = "tablet";
      else cls = "phone";
      o.put("cls", cls);
      o.put("model", Build.MODEL == null ? "" : Build.MODEL);
      o.put("brand", Build.MANUFACTURER == null ? "" : Build.MANUFACTURER);
      o.put("device", Build.DEVICE == null ? "" : Build.DEVICE);
      o.put("sdk", Build.VERSION.SDK_INT);
      o.put("rel", Build.VERSION.RELEASE == null ? "" : Build.VERSION.RELEASE);
      o.put("ui", uis);
      o.put("leanback", leanback);
      o.put("touch", touch);
      o.put("dpad", dpad);
      o.put("wdp", Math.round(wdp));
      o.put("hdp", Math.round(hdp));
      o.put("dpi", dm.densityDpi);
      o.put("ram", ramMb(c));
      o.put("cores", Runtime.getRuntime().availableProcessors());
      o.put("tier", tier(c));
      o.put("net", netType(c));
      o.put("pen", penalty(c));
    } catch (Throwable e) {}
    return o.toString();
  }

  // ---------- adaptive buffering ----------
  private static SharedPreferences sp(Context c) { return c.getSharedPreferences("h", 0); }

  /** 0..3: raised when playback stalled a lot on this connection, lowered after clean sessions. */
  public static int penalty(Context c) {
    try { return Math.max(0, Math.min(3, sp(c).getInt("net_pen", 0))); } catch (Throwable e) { return 0; }
  }
  public static void bump(Context c) { try { sp(c).edit().putInt("net_pen", Math.min(3, penalty(c) + 1)).apply(); } catch (Throwable e) {} }
  public static void relax(Context c) { try { int p = penalty(c); if (p > 0) sp(c).edit().putInt("net_pen", p - 1).apply(); } catch (Throwable e) {} }
  public static long savedBps(Context c) { try { return sp(c).getLong("net_bps", 0L); } catch (Throwable e) { return 0L; } }
  public static void saveBps(Context c, long bps) { try { if (bps > 200000L) sp(c).edit().putLong("net_bps", bps).apply(); } catch (Throwable e) {} }

  public static boolean looksLive(String url) {
    if (url == null) return true;
    String u = url.toLowerCase();
    if (u.contains("/movie/") || u.contains("/series/")) return false;
    if (u.matches(".*\\.(mp4|mkv|avi|mov|wmv|webm|m4v|flv)(\\?.*)?$")) return false;
    return true;
  }

  public static DefaultLoadControl loadControl(Context c, boolean live) {
    int t = tier(c), p = penalty(c);
    int min, max, start, after, bytes;
    if (live) {
      min = t == 0 ? 12000 : t == 1 ? 20000 : 30000;
      max = t == 0 ? 25000 : t == 1 ? 40000 : 60000;
      start = 1500;
      after = 4000;
    } else {
      min = t == 0 ? 20000 : t == 1 ? 30000 : 45000;
      max = t == 0 ? 45000 : t == 1 ? 90000 : 150000;
      start = 2000;
      after = 6000;
    }
    min += p * 8000;
    max += p * 20000;
    after += p * 3000;
    bytes = t == 0 ? 24 * 1024 * 1024 : t == 1 ? 64 * 1024 * 1024 : 120 * 1024 * 1024;
    if (max < min) max = min;
    return new DefaultLoadControl.Builder()
      .setBufferDurationsMs(min, max, start, after)
      .setTargetBufferBytes(bytes)
      .setPrioritizeTimeOverSizeThresholds(t != 0)
      .setBackBuffer(t == 0 ? 0 : 20000, false)
      .build();
  }

  /** Live items sit a little behind the edge. A bigger cushion on shaky connections means fewer stalls. */
  public static MediaItem item(Context c, String url, boolean live) {
    MediaItem.Builder b = new MediaItem.Builder().setUri(url);
    if (live) {
      long target = 6000L + penalty(c) * 4000L;
      b.setLiveConfiguration(new MediaItem.LiveConfiguration.Builder()
        .setTargetOffsetMs(target)
        .setMinOffsetMs(3000L)
        .setMaxOffsetMs(target + 25000L)
        .build());
    }
    return b.build();
  }
}
EOF
cat > android/app/src/main/java/com/hala/tv/ImgCache.java <<'EOF'
package com.hala.tv;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Poster / logo cache for the WebView.
 * - Serves every http(s) image request from a disk cache (survives restarts, ignores the provider's no-cache headers).
 * - Downloads at most a few images at a time, so a weak line is not saturated and the stream is not starved.
 * - Shrinks oversized provider posters (often 1500+ px) before they reach the WebView: faster download of the next
 *   screen, much less decode time and memory on weak boxes.
 * - Any failure returns null so the WebView falls back to its own normal request. Nothing here can block playback.
 */
public final class ImgCache {
  private ImgCache() {}

  private static File dir;
  private static Semaphore gate;
  private static int maxPx = 900;
  private static final long MAX_BYTES = 220L * 1024 * 1024;
  private static final ConcurrentHashMap<String, Object> locks = new ConcurrentHashMap<String, Object>();
  private static final ConcurrentHashMap<String, long[]> fails = new ConcurrentHashMap<String, long[]>();
  private static final AtomicInteger writes = new AtomicInteger();
  private static volatile int hits, misses, bad;

  public static void init(Context c) {
    try {
      dir = new File(c.getCacheDir(), "img");
      dir.mkdirs();
      int tier = Perf.tier(c);
      gate = new Semaphore(tier == 0 ? 3 : 6, true);
      maxPx = tier == 0 ? 640 : 900;
      new Thread(new Runnable() { public void run() { trim(); } }).start();
    } catch (Throwable e) { dir = null; }
  }

  public static String stats() { return "hit=" + hits + " miss=" + misses + " bad=" + bad; }

  public static void clear() {
    try {
      File[] fs = dir == null ? null : dir.listFiles();
      if (fs != null) for (File f : fs) f.delete();
    } catch (Throwable e) {}
  }

  public static WebResourceResponse handle(WebResourceRequest r) {
    try {
      if (dir == null || r == null || !"GET".equalsIgnoreCase(r.getMethod())) return null;
      String url = r.getUrl().toString();
      if (!(url.startsWith("http://") || url.startsWith("https://"))) return null;
      Map<String, String> h = r.getRequestHeaders();
      if (h == null) return null;
      String acc = h.get("Accept");
      if (acc == null || acc.indexOf("image/") < 0 || h.get("Range") != null) return null;
      String key = sha1(url);
      File f = new File(dir, key);
      WebResourceResponse cached = fromDisk(f);
      if (cached != null) { hits++; return cached; }
      Object lock = new Object();
      Object old = locks.putIfAbsent(key, lock);
      if (old != null) lock = old;
      synchronized (lock) {
        try {
          cached = fromDisk(f);
          if (cached != null) { hits++; return cached; }
          long[] fl = fails.get(key);
          if (fl != null && fl[0] >= 2 && System.currentTimeMillis() - fl[1] < 30000) return quick404();
          gate.acquire();
          try {
            misses++;
            byte[] body = null;
            String[] mime = new String[1];
            try { body = download(url, h.get("User-Agent"), mime); } catch (Throwable e) { body = null; }
            if (body == null || body.length < 16) { markFail(key); return null; }
            fails.remove(key);
            String origMime = mime[0];
            try {
              byte[] sm = shrink(url, body, origMime, mime);
              if (sm != null) body = sm; else mime[0] = origMime;
            } catch (Throwable e) { mime[0] = origMime; }
            save(f, mime[0], body);
            return resp(mime[0], new ByteArrayInputStream(body));
          } finally { gate.release(); }
        } finally { locks.remove(key); }
      }
    } catch (Throwable e) { return null; }
  }

  private static void markFail(String key) {
    bad++;
    long[] fl = fails.get(key);
    if (fl == null) fl = new long[2];
    fl[0]++;
    fl[1] = System.currentTimeMillis();
    fails.put(key, fl);
    if (fails.size() > 2000) fails.clear();
  }

  private static WebResourceResponse quick404() {
    Map<String, String> hd = new HashMap<String, String>();
    hd.put("Access-Control-Allow-Origin", "*");
    return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found", hd, new ByteArrayInputStream(new byte[0]));
  }

  private static WebResourceResponse resp(String mime, InputStream in) {
    Map<String, String> hd = new HashMap<String, String>();
    hd.put("Access-Control-Allow-Origin", "*");
    hd.put("Cache-Control", "max-age=86400");
    return new WebResourceResponse(mime, null, 200, "OK", hd, in);
  }

  private static WebResourceResponse fromDisk(File f) {
    try {
      if (!f.exists() || f.length() < 18) return null;
      FileInputStream in = new FileInputStream(f);
      int n = in.read();
      if (n <= 0 || n > 60) { in.close(); f.delete(); return null; }
      byte[] m = new byte[n];
      int got = 0;
      while (got < n) { int k = in.read(m, got, n - got); if (k < 0) break; got += k; }
      if (got != n) { in.close(); f.delete(); return null; }
      f.setLastModified(System.currentTimeMillis());
      return resp(new String(m, "UTF-8"), in);
    } catch (Throwable e) { return null; }
  }

  private static void save(File f, String mime, byte[] body) {
    try {
      byte[] m = mime.getBytes("UTF-8");
      File t = new File(dir, f.getName() + ".tmp");
      FileOutputStream o = new FileOutputStream(t);
      o.write(m.length);
      o.write(m);
      o.write(body);
      o.close();
      if (!t.renameTo(f)) t.delete();
      if (writes.incrementAndGet() % 120 == 0) {
        new Thread(new Runnable() { public void run() { trim(); } }).start();
      }
    } catch (Throwable e) {}
  }

  private static byte[] download(String url0, String ua, String[] mimeOut) throws Exception {
    String url = url0;
    for (int hop = 0; hop < 5; hop++) {
      HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
      try {
        c.setConnectTimeout(7000);
        c.setReadTimeout(10000);
        c.setInstanceFollowRedirects(false);
        if (ua != null) c.setRequestProperty("User-Agent", ua);
        c.setRequestProperty("Accept", "image/*,*/*;q=0.8");
        int code = c.getResponseCode();
        if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
          String loc = c.getHeaderField("Location");
          if (loc == null) return null;
          url = new URL(new URL(url), loc).toString();
          continue;
        }
        if (code != 200) return null;
        String ct = c.getContentType();
        if (ct != null) { int i = ct.indexOf(';'); if (i > 0) ct = ct.substring(0, i); ct = ct.trim().toLowerCase(); }
        if (ct == null || !ct.startsWith("image/")) return null;
        InputStream in = c.getInputStream();
        ByteArrayOutputStream bo = new ByteArrayOutputStream(32768);
        byte[] buf = new byte[16384];
        int n;
        while ((n = in.read(buf)) > 0) {
          bo.write(buf, 0, n);
          if (bo.size() > 12 * 1024 * 1024) return null;
        }
        mimeOut[0] = ct;
        return bo.toByteArray();
      } finally { c.disconnect(); }
    }
    return null;
  }

  /** Returns smaller bytes (and sets mime[0]) or null to keep the original. */
  private static byte[] shrink(String url, byte[] data, String mime, String[] mimeOut) {
    if (data.length < 45 * 1024) return null;
    if (mime.indexOf("svg") >= 0 || mime.indexOf("gif") >= 0) return null;
    if (url.indexOf("image.tmdb.org") >= 0) return null;   /* already sized by thumb() */
    BitmapFactory.Options o = new BitmapFactory.Options();
    o.inJustDecodeBounds = true;
    BitmapFactory.decodeByteArray(data, 0, data.length, o);
    int w = o.outWidth, hh = o.outHeight, mx = Math.max(w, hh);
    if (w <= 0 || hh <= 0 || mx <= maxPx * 13 / 10) return null;
    int ss = 1;
    while (mx / (ss * 2) >= maxPx) ss *= 2;
    BitmapFactory.Options o2 = new BitmapFactory.Options();
    o2.inSampleSize = ss;
    Bitmap b = BitmapFactory.decodeByteArray(data, 0, data.length, o2);
    if (b == null) return null;
    try {
      int bw = b.getWidth(), bh = b.getHeight(), bm = Math.max(bw, bh);
      if (bm > maxPx) {
        float sc = (float) maxPx / bm;
        Bitmap s = Bitmap.createScaledBitmap(b, Math.max(1, Math.round(bw * sc)), Math.max(1, Math.round(bh * sc)), true);
        if (s != b) { b.recycle(); b = s; }
      }
      boolean png = b.hasAlpha() && (mime.indexOf("png") >= 0 || mime.indexOf("webp") >= 0);
      ByteArrayOutputStream bo = new ByteArrayOutputStream(64 * 1024);
      b.compress(png ? Bitmap.CompressFormat.PNG : Bitmap.CompressFormat.JPEG, png ? 100 : 82, bo);
      if (bo.size() < data.length * 9 / 10) {
        mimeOut[0] = png ? "image/png" : "image/jpeg";
        return bo.toByteArray();
      }
      return null;
    } finally { try { b.recycle(); } catch (Throwable e) {} }
  }

  private static void trim() {
    try {
      File[] fs = dir == null ? null : dir.listFiles();
      if (fs == null) return;
      long tot = 0;
      for (File f : fs) {
        if (f.getName().endsWith(".tmp")) { if (System.currentTimeMillis() - f.lastModified() > 600000) f.delete(); continue; }
        tot += f.length();
      }
      if (tot <= MAX_BYTES) return;
      java.util.Arrays.sort(fs, new java.util.Comparator<File>() {
        public int compare(File a, File b) { return Long.compare(a.lastModified(), b.lastModified()); }
      });
      long target = MAX_BYTES * 80 / 100;
      for (File f : fs) {
        if (tot <= target) break;
        long l = f.length();
        if (f.delete()) tot -= l;
      }
    } catch (Throwable e) {}
  }

  private static String sha1(String s) throws Exception {
    byte[] d = MessageDigest.getInstance("SHA-1").digest(s.getBytes("UTF-8"));
    StringBuilder sb = new StringBuilder(40);
    for (byte b : d) { sb.append(Character.forDigit((b >> 4) & 15, 16)); sb.append(Character.forDigit(b & 15, 16)); }
    return sb.toString();
  }
}
EOF

cat > android/app/src/main/java/com/hala/tv/PhoneServer.java <<'EOF'
package com.hala.tv;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Enumeration;

/** Tiny LAN-only HTTP server: serves the phone page and receives remote/keyboard commands. Token protected. */
public class PhoneServer {
  public interface Cb { void onMsg(String json); byte[] page(); }

  private ServerSocket ss;
  private Thread th;
  private volatile boolean run;
  private String token = "";
  private int port;
  private Cb cb;
  private volatile long lastSeen;

  public synchronized String start(Cb c) {
    stop();
    cb = c;
    String ip = System.getProperty("hala.ip");
    if (ip == null) ip = localIp();
    if (ip == null) return "";
    byte[] r = new byte[9];
    new SecureRandom().nextBytes(r);
    StringBuilder sb = new StringBuilder();
    for (byte b : r) sb.append(Character.forDigit((b >> 4) & 15, 16)).append(Character.forDigit(b & 15, 16));
    token = sb.toString();
    ss = null;
    for (int p = 8765; p < 8785; p++) {
      try { ss = new ServerSocket(p); port = p; break; } catch (Exception e) { ss = null; }
    }
    if (ss == null) return "";
    run = true;
    th = new Thread(new Runnable() { public void run() { loop(); } }, "hala-phone");
    th.setDaemon(true);
    th.start();
    return "http://" + ip + ":" + port + "/?t=" + token;
  }

  public synchronized void stop() {
    run = false;
    try { if (ss != null) ss.close(); } catch (Exception e) {}
    ss = null;
  }

  public boolean on() { return run; }
  public long lastSeen() { return lastSeen; }
  public int port() { return port; }
  public String token() { return token; }

  static String localIp() {
    try {
      String best = null;
      Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces();
      while (en != null && en.hasMoreElements()) {
        NetworkInterface ni = en.nextElement();
        if (!ni.isUp() || ni.isLoopback()) continue;
        String n = ni.getName() == null ? "" : ni.getName().toLowerCase();
        Enumeration<InetAddress> ad = ni.getInetAddresses();
        while (ad.hasMoreElements()) {
          InetAddress a = ad.nextElement();
          if (a instanceof Inet4Address && a.isSiteLocalAddress()) {
            if (n.startsWith("wlan") || n.startsWith("eth")) return a.getHostAddress();
            if (best == null) best = a.getHostAddress();
          }
        }
      }
      return best;
    } catch (Exception e) { return null; }
  }

  private void loop() {
    while (run && ss != null) {
      try {
        final Socket s = ss.accept();
        Thread t = new Thread(new Runnable() { public void run() { serve(s); } }, "hala-phone-c");
        t.setDaemon(true);
        t.start();
      } catch (Exception e) { if (!run) break; }
    }
  }

  private static String readLine(InputStream in) throws Exception {
    ByteArrayOutputStream b = new ByteArrayOutputStream();
    int c;
    while ((c = in.read()) != -1) {
      if (c == '\n') break;
      if (c != '\r') b.write(c);
      if (b.size() > 4096) break;
    }
    return new String(b.toByteArray(), StandardCharsets.ISO_8859_1);
  }

  private void serve(Socket s) {
    try {
      s.setSoTimeout(6000);
      InputStream in = s.getInputStream();
      OutputStream out = s.getOutputStream();
      String rl = readLine(in);
      if (rl.length() == 0) { s.close(); return; }
      String[] p = rl.split(" ");
      String method = p.length > 0 ? p[0] : "", path = p.length > 1 ? p[1] : "/";
      int len = 0;
      String h;
      while ((h = readLine(in)).length() > 0) {
        String lh = h.toLowerCase();
        if (lh.startsWith("content-length:")) { try { len = Integer.parseInt(lh.substring(15).trim()); } catch (Exception e) {} }
      }
      byte[] body = new byte[0];
      if (len > 0 && len <= 8192) {
        body = new byte[len];
        int got = 0;
        while (got < len) { int n = in.read(body, got, len - got); if (n < 0) break; got += n; }
      }
      String q = "";
      int qi = path.indexOf('?');
      String route = qi >= 0 ? path.substring(0, qi) : path;
      if (qi >= 0) q = path.substring(qi + 1);
      boolean ok = false;
      for (String kv : q.split("&")) if (kv.equals("t=" + token)) ok = true;
      if (!ok) { send(out, 403, "text/plain; charset=utf-8", "forbidden".getBytes(StandardCharsets.UTF_8)); s.close(); return; }
      lastSeen = System.currentTimeMillis();
      if (method.equals("POST") && route.equals("/m")) {
        String j = new String(body, StandardCharsets.UTF_8);
        try { cb.onMsg(j); } catch (Exception e) {}
        send(out, 200, "text/plain; charset=utf-8", "ok".getBytes(StandardCharsets.UTF_8));
      } else if (route.equals("/ping")) {
        send(out, 200, "text/plain; charset=utf-8", "ok".getBytes(StandardCharsets.UTF_8));
      } else if (route.equals("/")) {
        byte[] pg = cb.page();
        send(out, 200, "text/html; charset=utf-8", pg == null ? "page missing".getBytes(StandardCharsets.UTF_8) : pg);
      } else {
        send(out, 404, "text/plain; charset=utf-8", "not found".getBytes(StandardCharsets.UTF_8));
      }
      out.flush();
      s.close();
    } catch (Exception e) {
      try { s.close(); } catch (Exception x) {}
    }
  }

  private static void send(OutputStream out, int code, String type, byte[] b) throws Exception {
    String st = code == 200 ? "OK" : code == 403 ? "Forbidden" : "Not Found";
    String hd = "HTTP/1.1 " + code + " " + st + "\r\nContent-Type: " + type + "\r\nContent-Length: " + b.length + "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
    out.write(hd.getBytes(StandardCharsets.ISO_8859_1));
    out.write(b);
  }
}
EOF

cat > android/app/src/main/assets/phone.html <<'EOF'
<!doctype html>
<html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><title>Hala TV · ريموت</title>
<style>
:root{--bg:#0f1115;--pn:#1a1d24;--ln:#2a2f3a;--tx:#f2f4f8;--mt:#8b93a3;--ac:#e50914;--ok:#2fbf71}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;background:var(--bg);color:var(--tx);font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;touch-action:manipulation}
body{padding:14px 14px 40px;max-width:520px;margin:0 auto}
h1{font-size:18px;margin:4px 0 2px}
#st{font-size:13px;color:var(--mt);margin-bottom:12px}#st.ok{color:var(--ok)}#st.no{color:#ff6b6b}
.card{background:var(--pn);border:1px solid var(--ln);border-radius:18px;padding:12px;margin-bottom:14px}
textarea{width:100%;min-height:92px;border-radius:12px;border:1px solid var(--ln);background:#0c0e12;color:var(--tx);padding:12px;font-size:20px;resize:vertical;font-family:inherit}
textarea:focus{outline:2px solid var(--ac)}
.row{display:flex;gap:8px;margin-top:8px}
button{flex:1;min-height:52px;border-radius:14px;border:1px solid var(--ln);background:#242935;color:var(--tx);font-size:17px;font-family:inherit;font-weight:600}
button:active{background:var(--ac);border-color:var(--ac)}
button.pri{background:var(--ac);border-color:var(--ac)}
.pad{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
.pad button{min-height:64px;font-size:26px}
.pad .ok{background:var(--ac);border-color:var(--ac);font-size:20px}
.sm{font-size:15px!important;min-height:50px!important}
.lbl{font-size:13px;color:var(--mt);margin:2px 4px 8px}
.tip{font-size:12.5px;color:var(--mt);line-height:1.7;margin-top:6px}
</style></head><body>
<h1>📺 Hala TV — ريموت التلفون</h1>
<div id="st">عم نتصل…</div>
<div class="card">
<div class="lbl">⌨️ اكتب هون وبيطلع على التلفزيون بنفس الوقت (بتقدر تستخدم المايك تبع كيبورد التلفون للكتابة بالصوت)</div>
<textarea id="tx" placeholder="اكتب أو احكي…" autocomplete="off" autocapitalize="off"></textarea>
<div class="row"><button class="pri" id="bs">🔎 بحث</button><button id="be">↵ تأكيد</button><button id="bc">✕ مسح</button></div>
</div>
<div class="card">
<div class="pad">
<button data-k="home" class="sm">🏠</button><button data-k="38" class="rp">▲</button><button data-k="back" class="sm">↩ رجوع</button>
<button data-k="37" class="rp">◀</button><button data-k="13" class="ok">OK</button><button data-k="39" class="rp">▶</button>
<button data-a="seek-30" class="sm">⏪ 30</button><button data-k="40" class="rp">▼</button><button data-a="seek30" class="sm">30 ⏩</button>
</div>
<div class="row" style="margin-top:12px"><button data-a="pp" class="sm">⏯ تشغيل / إيقاف</button><button data-a="chn" class="sm">القناة ▲</button><button data-a="chp" class="sm">القناة ▼</button></div>
<div class="row"><button data-a="next" class="sm">⏭ الحلقة الجاية</button><button data-a="menu" class="sm">☰ قائمة المشغّل</button></div>
</div>
<div class="tip">الأسهم والـOK بتشتغل مثل ريموت التلفزيون بالضبط. إذا كنت على شاشة تسجيل الدخول: اضغط OK على الحقل بالتلفزيون، وبعدها اكتب هون.</div>
<script>
var T=new URLSearchParams(location.search).get('t')||'',stEl=document.getElementById('st'),tx=document.getElementById('tx'),ok=false,tm=0;
function send(o,cb){var x=new XMLHttpRequest();x.open('POST','/m?t='+encodeURIComponent(T));x.timeout=4000;x.onload=function(){setOk(x.status==200);cb&&cb()};x.onerror=x.ontimeout=function(){setOk(false)};x.send(JSON.stringify(o))}
function setOk(v){ok=v;stEl.className=v?'ok':'no';stEl.textContent=v?'✓ متصل بالتلفزيون':'✗ انقطع الاتصال — تأكد انك على نفس الواي فاي'}
function ping(){var x=new XMLHttpRequest();x.open('GET','/ping?t='+encodeURIComponent(T));x.timeout=3000;x.onload=function(){setOk(x.status==200)};x.onerror=x.ontimeout=function(){setOk(false)};x.send()}
ping();setInterval(ping,5000);
tx.addEventListener('input',function(){clearTimeout(tm);tm=setTimeout(function(){send({t:'fill',v:tx.value})},120)});
document.getElementById('bs').onclick=function(){send({t:'search',v:tx.value})};
document.getElementById('be').onclick=function(){send({t:'fill',v:tx.value},function(){send({t:'key',k:'enter'})})};
document.getElementById('bc').onclick=function(){tx.value='';send({t:'fill',v:''});tx.focus()};
document.querySelectorAll('button[data-k]').forEach(function(b){var k=b.getAttribute('data-k'),iv=0,to=0;var fire=function(){if(navigator.vibrate)navigator.vibrate(8);send({t:'key',k:k})};
 var st=function(e){e.preventDefault();fire();if(b.classList.contains('rp')){to=setTimeout(function(){iv=setInterval(fire,130)},420)}},en=function(){clearTimeout(to);clearInterval(iv)};
 b.addEventListener('touchstart',st,{passive:false});b.addEventListener('touchend',en);b.addEventListener('touchcancel',en);b.addEventListener('mousedown',st);b.addEventListener('mouseup',en);b.addEventListener('mouseleave',en)});
document.querySelectorAll('button[data-a]').forEach(function(b){b.onclick=function(){if(navigator.vibrate)navigator.vibrate(8);send({t:'act',a:b.getAttribute('data-a')})}});
</script></body></html>
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
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter;
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy;
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
  private NetWatch nw;
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
  // Aspect modes (same indexes as JS FIT): 0 Original, 1 Fit, 2 Fill(stretch), 3 Zoom(crop), 4 16:9, 5 4:3
  private int fitMode = 1;
  private int exoVw = 0, exoVh = 0;
  private float exoPar = 1f;

  private static MediaPlayer.ScaleType vlcScaleFor(int m) {
    switch (m) {
      case 0: return MediaPlayer.ScaleType.SURFACE_ORIGINAL;
      case 2: return MediaPlayer.ScaleType.SURFACE_FILL;
      case 3: return MediaPlayer.ScaleType.SURFACE_FIT_SCREEN;
      case 4: return MediaPlayer.ScaleType.SURFACE_16_9;
      case 5: return MediaPlayer.ScaleType.SURFACE_4_3;
      default: return MediaPlayer.ScaleType.SURFACE_BEST_FIT;
    }
  }

  private void exoApplyFit() {
    try {
      if (exoFrame == null) return;
      int m = fitMode;
      float vr = exoVh > 0 ? exoVw * exoPar / exoVh : 0f;
      int resize = AspectRatioFrameLayout.RESIZE_MODE_FIT;
      float ratio = vr;
      FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER);
      if (m == 0) {
        if (exoVh > 0 && exoVw > 0) {
          resize = AspectRatioFrameLayout.RESIZE_MODE_FILL;
          lp = new FrameLayout.LayoutParams(Math.max(1, Math.round(exoVw * exoPar)), exoVh, Gravity.CENTER);
        }
      } else if (m == 2) resize = AspectRatioFrameLayout.RESIZE_MODE_FILL;
      else if (m == 3) resize = AspectRatioFrameLayout.RESIZE_MODE_ZOOM;
      else if (m == 4) ratio = 16f / 9f;
      else if (m == 5) ratio = 4f / 3f;
      exoFrame.setResizeMode(resize);
      if (ratio > 0f) exoFrame.setAspectRatio(ratio);
      exoFrame.setLayoutParams(lp);
      exoFrame.requestLayout();
    } catch (Throwable e) {}
  }

  private void vlcApplyFit() {
    try {
      vlcScale = vlcScaleFor(fitMode);
      if (vlc != null) vlc.setVideoScale(vlcScale);
      if (vlcLayout != null) vlcLayout.requestLayout();
    } catch (Throwable e) {}
  }
  private String vlcUrl = "";
  private long vlcStartMs, vlcT0, vlcMoveAt, vlcLastT = -1, vlcPlayAt;
  private int vlcVout;
  private boolean vlcHw = true, vlcRetried, vlcErr, vlcPlayed, vlcBuf, vlcHasVideo, vlcBroken;
  private final java.util.ArrayList<Integer> vA = new java.util.ArrayList<Integer>();
  private final java.util.ArrayList<Integer> vT = new java.util.ArrayList<Integer>();
  private final Runnable vlcSoon = new Runnable() { public void run() { vlcTracks(); vlcInfo(); } };
  /* real-video verification (ExoPlayer): audio alone never counts as success */
  private long exoPlayAt, exoMoveAt;
  private int exoLastN;
  private boolean exoVerified, exoErrSent, exoTrKnown, exoVid = true, vlcFrameSent;
  // ---- adaptive stall handling (shared idea with PlayerActivity) ----
  private boolean exoLive = false, exoReady = false, exoBoosted = false, exoBoostRun = false;
  private String exoUrl = "";
  private long exoT0 = 0;
  private DefaultBandwidthMeter exoMeter;
  private final java.util.ArrayList<Long> exoStalls = new java.util.ArrayList<Long>();

  private void exoStallMark() {
    if (!exoReady || exo == null) return;
    long now = SystemClock.uptimeMillis();
    exoStalls.add(now);
    while (!exoStalls.isEmpty() && now - exoStalls.get(0) > 90000L) exoStalls.remove(0);
    js("stall", "{\"n\":" + exoStalls.size() + ",\"pen\":" + Perf.penalty(this) + "}");
    if (exoStalls.size() >= 3 && !exoBoosted) {
      exoBoosted = true;
      Perf.bump(this);
      final String u = exoUrl;
      final long pos = exoLive ? 0 : Math.max(0, exo.getCurrentPosition() - 2000);
      final int ss = sid;
      hnd.post(new Runnable() { public void run() { exoBoostRun = true; exoStart(u, pos, ss); } });
    }
  }

  private void exoResetWatch() { exoPlayAt = 0; exoMoveAt = SystemClock.uptimeMillis(); exoLastN = -1; exoVerified = false; exoErrSent = false; exoTrKnown = false; exoVid = true; }
  private void exoBad(String code) { if (exoErrSent) return; exoErrSent = true; js("err", JSONObject.quote(code)); }
  private void exoWatch() {
    long now = SystemClock.uptimeMillis();
    if (exoErrSent || exo.getPlaybackState() != Player.STATE_READY || !exo.getPlayWhenReady()) { exoPlayAt = 0; exoMoveAt = now; return; }
    if (exoPlayAt == 0) exoPlayAt = now;
    if (exoTrKnown && !exoVid) { if (!exoVerified && now - exoPlayAt > 1200) { exoVerified = true; js("frame", "0"); } return; }
    int n = 0;
    try { androidx.media3.exoplayer.DecoderCounters dc = exo.getVideoDecoderCounters(); if (dc != null) { dc.ensureUpdated(); n = dc.renderedOutputBufferCount; } } catch (Throwable e) {}
    if (!exoVerified) {
      if (n > 0) { exoVerified = true; exoLastN = n; exoMoveAt = now; js("frame", "1"); }
      else if (now - exoPlayAt > 3000) exoBad("NOFRAME");
      return;
    }
    if (n != exoLastN) { exoLastN = n; exoMoveAt = now; }
    else if (now - exoMoveAt > 6000) exoBad("FROZEN_VIDEO");
  }
  private final Runnable tick = new Runnable() {
    public void run() {
      if (vlcOn() && exoRoot.getVisibility() == View.VISIBLE) { vlcTick(); hnd.postDelayed(this, 250); return; }
      if (exo == null || exoRoot.getVisibility() != View.VISIBLE) return;
      exoWatch();
      long d = exo.getDuration();
      boolean live = exo.isCurrentMediaItemLive() || d == C.TIME_UNSET;
      js("time", "{\"t\":" + exo.getCurrentPosition() + ",\"d\":" + (live ? -1 : d) + "}");
      hnd.postDelayed(this, 250);
    }
  };

  private PhoneServer phone;

  public class Bridge {
    @JavascriptInterface
    public String phoneStart() {
      try {
        if (phone == null) phone = new PhoneServer();
        return phone.start(new PhoneServer.Cb() {
          public void onMsg(final String j) {
            runOnUiThread(new Runnable() { public void run() {
              if (web != null) web.evaluateJavascript("window.__phone&&window.__phone(" + org.json.JSONObject.quote(j) + ")", null);
            } });
          }
          public byte[] page() {
            try {
              java.io.InputStream in = getAssets().open("phone.html");
              java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
              byte[] buf = new byte[4096];
              int n;
              while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
              in.close();
              return bo.toByteArray();
            } catch (Exception e) { return null; }
          }
        });
      } catch (Throwable e) { return ""; }
    }

    @JavascriptInterface
    public void phoneStop() { try { if (phone != null) phone.stop(); } catch (Throwable e) {} }

    @JavascriptInterface
    public long phoneSeen() { try { return phone == null ? 0 : phone.lastSeen(); } catch (Throwable e) { return 0; } }

    @JavascriptInterface
    public void setSttKey(String k) { sttKey = k == null ? "" : k.trim(); }

    @JavascriptInterface
    public String deviceInfo() { return Perf.deviceJson(MainActivity.this); }

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
    public void exoInset(final int px) {
      runOnUiThread(new Runnable() { public void run() {
        try {
          int p = px < 0 ? 0 : px;
          if (exoRoot != null) { exoRoot.setPadding(p, p, p, p); exoRoot.requestLayout(); }
        } catch (Throwable e) {}
      } });
    }

    @JavascriptInterface
    public void exoFit(final int m) {
      runOnUiThread(new Runnable() { public void run() {
        fitMode = (m < 0 || m > 5) ? 1 : m;
        vlcApplyFit();
        exoApplyFit();
      } });
    }

    @JavascriptInterface
    public void exoSub(final String vtt, final String lang) { runOnUiThread(new Runnable() { public void run() { exoSetSub(vtt, lang); } }); }

    @JavascriptInterface
    public void exoSubClear() { runOnUiThread(new Runnable() { public void run() { exoClearSub(); } }); }

    @JavascriptInterface
    public void exoTrack(final int type, final int idx) { runOnUiThread(new Runnable() { public void run() { if (vlcOn()) vlcPick(type, idx); else exoPick(type, idx); } }); }

    int epP = 0, epN = 0;

    @JavascriptInterface
    public void extEp(final int p, final int n) { epP = p; epN = n; }

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
          i.putExtra("epP", epP);
          i.putExtra("epN", epN);
          epP = 0; epN = 0;
          i.putExtra("ua", web.getSettings().getUserAgentString());
          startActivityForResult(i, 8);
        } catch (Throwable e) {
          web.evaluateJavascript("window.__extDone&&window.__extDone({\"err\":\"LAUNCH\"})", null);
        }
      } });
    }

    @JavascriptInterface
    public void exitApp() { runOnUiThread(new Runnable() { public void run() { finish(); } }); }

    /* touch player: fullscreen button = flip between landscape and portrait; returns true when landscape is now requested */
    @JavascriptInterface
    public boolean rotate() {
      final boolean land = getResources().getConfiguration().orientation != android.content.res.Configuration.ORIENTATION_LANDSCAPE;
      runOnUiThread(new Runnable() { public void run() {
        try {
          setRequestedOrientation(land ? android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE : android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT);
          getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        } catch (Throwable e) {}
      } });
      return land;
    }

    @JavascriptInterface
    public void fsReset() {
      runOnUiThread(new Runnable() { public void run() {
        try { setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED); } catch (Throwable e) {}
      } });
    }

    @JavascriptInterface
    public void engine(String e) { eng = "vlc".equals(e) ? "vlc" : "exo"; }

    private String codecJson;
    @JavascriptInterface
    public String codecs() {
      if (codecJson != null) return codecJson;
      JSONObject o = new JSONObject();
      try {
        String[] ms = {"video/avc", "video/hevc", "video/x-vnd.on2.vp9", "video/av01"};
        String[] ks = {"avc", "hevc", "vp9", "av1"};
        int[] lv = new int[4];
        boolean h4k = false;
        android.media.MediaCodecInfo[] all = new android.media.MediaCodecList(android.media.MediaCodecList.ALL_CODECS).getCodecInfos();
        for (android.media.MediaCodecInfo ci : all) {
          if (ci.isEncoder()) continue;
          String nm = ci.getName().toLowerCase();
          boolean hw = Build.VERSION.SDK_INT >= 29 ? ci.isHardwareAccelerated() : !(nm.startsWith("omx.google.") || nm.startsWith("c2.android."));
          for (String t : ci.getSupportedTypes()) for (int k = 0; k < 4; k++) if (t.equalsIgnoreCase(ms[k])) {
            lv[k] = Math.max(lv[k], hw ? 2 : 1);
            if (k == 1 && hw) { try { if (ci.getCapabilitiesForType(t).getVideoCapabilities().isSizeSupported(3840, 2160)) h4k = true; } catch (Throwable e) {} }
          }
        }
        for (int k = 0; k < 4; k++) o.put(ks[k], lv[k]);
        o.put("h4k", h4k);
      } catch (Throwable e) {}
      return codecJson = o.toString();
    }

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
    public boolean openUrl(final String url) {
      try {
        Intent i = new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(i);
        return true;
      } catch (Exception e) { return false; }
    }

    @JavascriptInterface
    public void install(final String url) {
      new Thread(new Runnable() {
        public void run() {
          try {
            java.io.File dir = new java.io.File(getCacheDir(), "updates");
            dir.mkdirs();
            final java.io.File f = new java.io.File(dir, "app.apk");
            updJs("p", -2, 0, 0);
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(15000);
            c.setReadTimeout(60000);
            InputStream is = c.getInputStream();
            long total = 0;
            try { total = Long.parseLong(c.getHeaderField("Content-Length")); } catch (Exception e) {}
            java.io.FileOutputStream os = new java.io.FileOutputStream(f);
            byte[] buf = new byte[16384];
            int n, last = -3;
            long got = 0, lastMs = 0;
            while ((n = is.read(buf)) > 0) {
              os.write(buf, 0, n);
              got += n;
              int pct = total > 0 ? (int) Math.min(100, got * 100 / total) : -2;
              long now = SystemClock.uptimeMillis();
              if ((pct != last && now - lastMs > 120) || (total <= 0 && now - lastMs > 400)) { last = pct; lastMs = now; updJs("p", pct, got, total); }
            }
            os.close();
            is.close();
            if (got <= 0) throw new java.io.IOException("empty");
            updJs("p", total > 0 ? 100 : -2, got, total > 0 ? total : got);
            updJs("d", 100, got, total > 0 ? total : got);
            runOnUiThread(new Runnable() {
              public void run() {
                try {
                  android.net.Uri u = androidx.core.content.FileProvider.getUriForFile(MainActivity.this, "com.hala.tv.fp", f);
                  Intent i = new Intent(Intent.ACTION_VIEW);
                  i.setDataAndType(u, "application/vnd.android.package-archive");
                  i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                  startActivity(i);
                } catch (Exception e) { updJs("e", 0, 0, 0); }
              }
            });
          } catch (Exception e) {
            updJs("e", 0, 0, 0);
          }
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
              c.setReadTimeout(url.contains("/ai") ? 240000 : (raw ? 20000 : 30000));
              c.setRequestProperty("Accept-Charset", "utf-8");
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
            if (raw || url.contains("/subtitleserve/")) r.put("b64", Base64.encodeToString(bo.toByteArray(), Base64.NO_WRAP));
            else r.put("body", bo.toString("UTF-8"));
            out = r.toString();
          } catch (Exception e) {
            out = "{\"status\":0,\"body\":\"\",\"error\":" + JSONObject.quote(String.valueOf(e)) + "}";
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
      public android.graphics.Bitmap getDefaultVideoPoster() {
        android.graphics.Bitmap b = android.graphics.Bitmap.createBitmap(2, 2, android.graphics.Bitmap.Config.ARGB_8888);
        b.eraseColor(Color.TRANSPARENT);
        return b;
      }

      @Override
      public android.view.View getVideoLoadingProgressView() {
        return new android.view.View(MainActivity.this);
      }

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
    ImgCache.init(this);
    web.setWebViewClient(new WebViewClient() {
      @Override
      public android.webkit.WebResourceResponse shouldInterceptRequest(WebView view, android.webkit.WebResourceRequest req) {
        android.webkit.WebResourceResponse x = ImgCache.handle(req);
        return x != null ? x : super.shouldInterceptRequest(view, req);
      }

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
    nw = new NetWatch(this, new NetWatch.Cb() { public void on(boolean up) { if (web != null) web.evaluateJavascript("window.__net&&window.__net(" + up + ")", null); } });
    nw.start();
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
    Intent vi = new Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, tag);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, tag);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, true);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 5);
    vi.putExtra(android.speech.RecognizerIntent.EXTRA_CALLING_PACKAGE, getPackageName());
    return vi;
  }

  /* next Arabic variant to try when the recognizer reports the locale unsupported/unavailable; never switches language family */
  private String voiceLangNext(String tag) {
    if ("ar-JO".equals(tag)) return "ar-SA";
    if ("ar-SA".equals(tag)) return "ar-EG";
    if ("ar-EG".equals(tag)) return "ar";
    return null;
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
      if ("rec".equals(getSharedPreferences("h", 0).getString("vmode", ""))) return false;
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
        if (el < 300) floor = floor < 0 ? rms : floor * 0.7 + rms * 0.3;
        else if (rms > Math.max(floor * 3, 250)) { speech = true; lastLoud = el; }
        if (!probed && el >= 900) { probed = true; if (peak <= 6 && !last) { skip = true; break; } }
        if (speech && el - lastLoud > 800) break;
        if (!speech && el > 5000) break;
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
    int ls = getSharedPreferences("h", 0).getInt("vsrc", -1);
    for (int q = 1; q < srcs.length; q++) if (srcs[q] == ls) { srcs[q] = srcs[0]; srcs[0] = ls; break; }
    byte[] pcm = null;
    String used = "";
    int maxPeak = 0;
    recAny = false;
    for (int i = 0; i < srcs.length && recRun; i++) {
      byte[] p = voiceCapture(srcs[i], i == srcs.length - 1);
      if (recPeak > maxPeak) maxPeak = recPeak;
      if (p != null) { pcm = p; used = String.valueOf(srcs[i]); if (recSpeech) getSharedPreferences("h", 0).edit().putInt("vsrc", srcs[i]).apply(); break; }
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
    String[] one = null;
    String err0 = null;
    try { one = voiceStt(fp, tagA); } catch (Throwable e) { err0 = String.valueOf(e); }
    org.json.JSONArray ja = new org.json.JSONArray();
    java.util.HashSet<String> seen = new java.util.HashSet<String>();
    if (one != null) for (String s2 : one) { if (seen.add(s2)) ja.put(s2); }
    if (ja.length() == 0) {
      if (err0 != null) {
        if (err0.contains("HTTPERR")) {
          vjsU("__voiceState", "fallback");
          hnd.post(new Runnable() { public void run() { voiceViaIntent = false; voiceTry = 0; voiceListen(tagA); } });
        } else vjsU2("__voiceErr", "network", "stt:" + err0);
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
      hnd.postDelayed(voiceWd, 3500);
      me.startListening(voiceIntentFor(tag));
    } catch (Throwable e) {
      voiceKill();
      voiceIntent(tag, "create:" + e);
    }
  }

  private void voiceGot(java.util.ArrayList<String> l) {
    if (l == null || l.isEmpty()) { voiceFail(7); return; }
    voiceKill();
    if (nativeFirst) getSharedPreferences("h", 0).edit().putString("vmode", "native").apply();
    org.json.JSONArray ja = new org.json.JSONArray();
    for (String s : l) ja.put(s);
    vjs("__voice", ja.toString());
  }

  private void voiceFail(int e) {
    String tag = voiceCur;
    if (e == 12 || e == 13) {
      String nx = voiceLangNext(tag);
      voiceKill();
      if (nx != null && !voiceViaIntent) { voiceListen(nx); return; }
      vjs2("__voiceErr", "lang", tag + ";E" + e + ";" + voiceDiag());
      return;
    }
    if (nativeFirst && (e == 3 || e == 4 || e == 5 || e == 6 || e == 7 || e == 8)) {
      nativeFirst = false;
      getSharedPreferences("h", 0).edit().putString("vmode", "rec").apply();
      voiceKill();
      vjs("__voiceState", "fallback");
      voiceRecStart(pendingLang);
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

  private void updJs(final String st, final int pct, final long got, final long tot) {
    runOnUiThread(new Runnable() { public void run() {
      if (web != null) web.evaluateJavascript("window.__updProg&&window.__updProg(" + JSONObject.quote(st) + "," + pct + "," + got + "," + tot + ")", null);
    } });
  }

  private void js(String k, String json) {
    if (web == null) return;
    web.evaluateJavascript("window.__exo&&window.__exo('" + k + "'," + json + "," + sid + ")", null);
  }

  private void exoEnsure() {
    if (exo != null) return;
    DefaultLoadControl lc = Perf.loadControl(this, exoLive);
    DefaultHttpDataSource.Factory hf = new DefaultHttpDataSource.Factory()
      .setAllowCrossProtocolRedirects(true)
      .setConnectTimeoutMs(12000)
      .setReadTimeoutMs(25000)
      .setUserAgent(web.getSettings().getUserAgentString());
    long sbps = Perf.savedBps(this);
    exoMeter = new DefaultBandwidthMeter.Builder(this).setInitialBitrateEstimate(sbps > 0 ? sbps : 3000000L).build();
    exo = new ExoPlayer.Builder(this, new DefaultRenderersFactory(this).setEnableDecoderFallback(true))
      .setMediaSourceFactory(new DefaultMediaSourceFactory(new DefaultDataSource.Factory(this, hf)).setLoadErrorHandlingPolicy(new DefaultLoadErrorHandlingPolicy(6)))
      .setLoadControl(lc)
      .setBandwidthMeter(exoMeter)
      .build();
    exo.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true);
    exo.setVideoTextureView(exoSurface);
    exoListener = new Player.Listener() {
      @Override public void onPlaybackStateChanged(int st) {
        if (st == Player.STATE_BUFFERING) { js("buf", "1"); exoStallMark(); }
        else if (st == Player.STATE_READY) {
          exoReady = true;
          long d = exo.getDuration();
          js("ready", "{\"d\":" + ((d == C.TIME_UNSET || exo.isCurrentMediaItemLive()) ? -1 : d) + "}");
        } else if (st == Player.STATE_ENDED) js("end", "1");
      }
      @Override public void onIsPlayingChanged(boolean p) { if (p) js("play", "1"); }
      @Override public void onPlayWhenReadyChanged(boolean pw, int reason) { js("pw", pw ? "true" : "false"); }
      @Override public void onVideoSizeChanged(VideoSize vs) {
        if (vs.height > 0) {
          exoVw = vs.width; exoVh = vs.height;
          exoPar = vs.pixelWidthHeightRatio > 0f ? vs.pixelWidthHeightRatio : 1f;
          exoApplyFit();
        }
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
        case MediaPlayer.Event.Vout: vlcVout = e.getVoutCount(); if (vlcVout > 0 && !vlcFrameSent) { vlcFrameSent = true; js("frame", "1"); } if (vlcVout > 0) hnd.post(new Runnable() { public void run() { vlcApplyFit(); } }); break;
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
    vlcErr = false; vlcRetried = false; vlcHw = true; vlcUrl = url; vlcStartMs = startMs; vlcArTried = false;
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
    vlcScale = vlcScaleFor(fitMode);
    vlc.setVideoScale(vlcScale);
    vlc.setEventListener(vlcEv);
    Media m = new Media(vlcLib, Uri.parse(vlcUrl));
    m.setHWDecoderEnabled(vlcHw, false);
    boolean vod = vlcUrl.matches("(?i).*\\.(mp4|mkv|avi|mov|wmv|webm|m4v)(\\?.*)?$") || vlcUrl.contains("/movie/") || vlcUrl.contains("/series/");
    m.addOption(":network-caching=" + ((vod ? 3000 : 1500) + Perf.penalty(this) * 1500 + (Perf.tier(this) == 0 ? 1000 : 0)));
    m.addOption(":sub-language=ara,ar,en");
    m.addOption(":subsdec-encoding=UTF-8");
    m.addOption(":http-user-agent=" + web.getSettings().getUserAgentString());
    if (startMs > 0) m.addOption(":start-time=" + (startMs / 1000));
    vlc.setMedia(m);
    m.release();
    long now = SystemClock.uptimeMillis();
    vlcT0 = now; vlcMoveAt = now; vlcLastT = -1; vlcPlayAt = now;
    vlcPlayed = false; vlcBuf = false; vlcVout = 0; vlcHasVideo = false; vlcFrameSent = false;
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
    if (vlcPlayed && vlcHasVideo && vlcVout == 0 && now - vlcPlayAt > 3500) vlcFail("NOVIDEO");
    else if (vlcPlayed && !vlcHasVideo && !vlcFrameSent && vlcLastT > 0 && now - vlcPlayAt > 2000) { vlcFrameSent = true; js("frame", "0"); }
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

  private boolean vlcArTried = false;

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
        if (!vlcArTried && cs < 0 && x.name != null && x.name.toLowerCase().matches(".*(arab|\\bara\\b|\\bar\\b|\u0639\u0631\u0628).*")) { vlcArTried = true; vlc.setSpuTrack(x.id); cs = x.id; }
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
      try { if (exoMeter != null) Perf.saveBps(this, exoMeter.getBitrateEstimate()); } catch (Throwable e) {}
      try { if (exoT0 > 0 && exoStalls.isEmpty() && !exoBoosted && SystemClock.uptimeMillis() - exoT0 > 600000L) Perf.relax(this); } catch (Throwable e) {}
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
    if (!exoBoostRun) exoBoosted = false;
    exoBoostRun = false;
    exoUrl = url;
    exoLive = Perf.looksLive(url);
    exoReady = false;
    exoStalls.clear();
    exoT0 = SystemClock.uptimeMillis();
    exoEnsure();
    exoVw = 0; exoVh = 0; exoPar = 1f;
    exoApplyFit();
    exoResetWatch();
    exo.setTrackSelectionParameters(exo.getTrackSelectionParameters().buildUpon().clearOverrides().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false).setPreferredTextLanguage("ar").build());
    exoRoot.setVisibility(View.VISIBLE);
    web.setBackgroundColor(Color.TRANSPARENT);
    exo.setMediaItem(Perf.item(this, url, exoLive), startMs > 0 ? startMs : C.TIME_UNSET);
    exo.prepare();
    exo.setPlayWhenReady(true);
    hnd.removeCallbacks(tick);
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
    org.json.JSONArray jaa = new org.json.JSONArray();
    try {
      for (Tracks.Group g : tr.getGroups()) {
        int ty = g.getType();
        if (ty != C.TRACK_TYPE_AUDIO && ty != C.TRACK_TYPE_TEXT) continue;
        for (int i = 0; i < g.length; i++) {
          if (ty == C.TRACK_TYPE_AUDIO) { audAll++; if (g.isTrackSupported(i)) audOk++; }
          Format f = g.getTrackFormat(i);
          if (ty == C.TRACK_TYPE_AUDIO) {
            JSONObject au = new JSONObject();
            au.put("m", f.sampleMimeType == null ? "" : f.sampleMimeType);
            au.put("ch", f.channelCount);
            au.put("u", g.isTrackSupported(i));
            au.put("s", g.isTrackSelected(i));
            jaa.put(au);
          }
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
    exoTrKnown = tr.getGroups().size() > 0;
    exoVid = tr.containsType(C.TRACK_TYPE_VIDEO);
    if (exoVid && !tr.isTypeSupported(C.TRACK_TYPE_VIDEO)) exoBad("NO_VIDEO_DECODER");
    boolean td = exo != null && exo.getTrackSelectionParameters().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT);
    js("tracks", "{\"a\":" + ja.toString() + ",\"t\":" + jt.toString() + ",\"na\":" + (audAll > 0 && audOk == 0 ? 1 : 0) + ",\"nu\":" + txtBad + ",\"all\":" + jall.toString() + ",\"aa\":" + jaa.toString() + ",\"td\":" + (td ? 1 : 0) + "}");
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
    if (nw != null) { nw.stop(); nw = null; }
    try { if (phone != null) phone.stop(); } catch (Throwable e) {}
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
import android.view.MotionEvent;
import android.widget.HorizontalScrollView;
import android.graphics.drawable.StateListDrawable;
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
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter;
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy;
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
      if (kind == 4) {
        p.setStyle(Paint.Style.STROKE);
        p.setStrokeWidth(h * 0.085f);
        p.setStrokeCap(Paint.Cap.ROUND);
        p.setStrokeJoin(Paint.Join.ROUND);
        path.moveTo(cx + s * 0.45f, cy - a * 1.05f); path.lineTo(cx - s * 0.55f, cy); path.lineTo(cx + s * 0.45f, cy + a * 1.05f);
        cv.drawPath(path, p);
        p.setStyle(Paint.Style.FILL);
        return;
      }
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

  interface SeekCb { void on(float f, int phase); }

  static class Seek extends View {
    float pos = 0f;
    SeekCb cb;
    final Paint q = new Paint(Paint.ANTI_ALIAS_FLAG);
    final RectF r = new RectF();
    Seek(Context c) { super(c); }
    @Override public boolean onTouchEvent(MotionEvent e) {
      if (cb == null || getVisibility() != View.VISIBLE) return false;
      int w = Math.max(1, getWidth());
      float f = Math.max(0f, Math.min(1f, e.getX() / w));
      switch (e.getActionMasked()) {
        case MotionEvent.ACTION_DOWN:
          if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(true);
          cb.on(f, 0); return true;
        case MotionEvent.ACTION_MOVE: cb.on(f, 1); return true;
        case MotionEvent.ACTION_UP: cb.on(f, 2); return true;
        case MotionEvent.ACTION_CANCEL: cb.on(f, 3); return true;
      }
      return true;
    }
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
  private int epP = 0, epN = 0;
  private long startMs;

  private FrameLayout root;
  private AspectRatioFrameLayout frame;
  private SurfaceView surface;
  private SubtitleView subs;
  private VLCVideoLayout vlcLayout;
  private ProgressBar spin;
  private TextView tvMsg, tvTitle, tvBadge, tvT, tvD, tvHint;
  private LinearLayout bar;
  private Ico icRw, icPp, icFf, icBack;
  private boolean touch, fsLand = true;
  private FrameLayout topBar;
  private TextView tbAs, tbPl;
  private Seek seek;

  private ExoPlayer exo;
  private Player.Listener exoL;
  private LibVLC vlcLib;
  private MediaPlayer vlc;
  private boolean vlcHw = true, vlcRetried, vlcPlayed, vlcBuf;
  private long vlcMoveAt, vlcLastT = -1;

  private boolean playing, paused, ended, failing, triedOther, done, netDown;
  private NetWatch nw;
  private int dlgs = 0;
  private boolean switchInternal = false;
  private String errCode = "";
  private int zapDir = 0, fitMode = 1, vh = 0, pVw = 0, pVh = 0;
  private float pPar = 1f;
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
      hideBarNow();
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
    try {
      android.app.UiModeManager um = (android.app.UiModeManager) getSystemService(Context.UI_MODE_SERVICE);
      boolean tvMode = um != null && um.getCurrentModeType() == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION;
      touch = !tvMode && getPackageManager().hasSystemFeature("android.hardware.touchscreen");
    } catch (Throwable e) { touch = false; }
    if (touch) { try { setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE); } catch (Throwable e) {} }
    Intent in = getIntent();
    String u = in.getStringExtra("url");
    url = u == null ? "" : u;
    String tt = in.getStringExtra("title");
    title = tt == null ? "" : tt;
    eng = "vlc".equals(in.getStringExtra("eng")) ? "vlc" : "exo";
    ua = in.getStringExtra("ua");
    live = in.getBooleanExtra("live", false);
    ar = in.getBooleanExtra("ar", true);
    epP = in.getIntExtra("epP", 0);
    epN = in.getIntExtra("epN", 0);
    startMs = in.getLongExtra("start", 0);
    build();
    nw = new NetWatch(this, new NetWatch.Cb() { public void on(boolean up) {
      if (done || tvMsg == null) return;
      if (up) { if (netDown) toast(ar ? "\u2713 \u0631\u062c\u0639 \u0627\u0644\u0625\u0646\u062a\u0631\u0646\u062a" : "\u2713 Internet is back", 2500); netDown = false; }
      else { netDown = true; toast(ar ? "\u26a0 \u0627\u0646\u0641\u0635\u0644 \u0627\u0644\u0625\u0646\u062a\u0631\u0646\u062a" : "\u26a0 Internet disconnected", 3600000); }
    } });
    nw.start();
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
    int ih = touch ? 48 : 38;
    LinearLayout.LayoutParams il = new LinearLayout.LayoutParams(dp(72), dp(ih));
    il.setMargins(dp(10), dp(4), dp(10), dp(4));
    LinearLayout.LayoutParams il2 = new LinearLayout.LayoutParams(dp(84), dp(ih));
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
    tr.addView(seek, new LinearLayout.LayoutParams(0, dp(touch ? 40 : 20), 1f));
    tr.addView(tvD, new LinearLayout.LayoutParams(-2, -2));
    if (live) seek.setVisibility(View.INVISIBLE);
    bar.addView(tr, new LinearLayout.LayoutParams(-1, -2));

    if (touch) {
      seek.cb = new SeekCb() {
        public void on(float f, int ph) {
          if (live || lastD <= 0) return;
          hnd.removeCallbacks(hideBar);
          hnd.removeCallbacks(commitSeek);
          if (ph == 3) { seekTgt = -1; updateUi(); hnd.postDelayed(hideBar, 4000); return; }
          seekTgt = (long) (f * lastD);
          if (ph == 2) {
            long tg = Math.min(seekTgt, Math.max(0, lastD - 1000));
            seekTgt = -1;
            lastT = tg;
            doSeek(tg);
            updateUi();
            hnd.postDelayed(hideBar, 4000);
          } else updateUi();
        }
      };
      icPp.setClickable(true);
      icPp.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { togglePause(); } });
      icRw.setClickable(true);
      icRw.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { seekBy(-1, false, 10); } });
      icFf.setClickable(true);
      icFf.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { seekBy(1, false, 10); } });

      LinearLayout tl = new LinearLayout(this);
      tl.setOrientation(LinearLayout.HORIZONTAL);
      tl.setGravity(Gravity.CENTER);
      tbSubs(tl, ar ? "ترجمة" : "Subtitles", new Runnable() { public void run() { if (dlgs == 0) subMenu(); } });
      tbSubs(tl, ar ? "صوت" : "Audio", new Runnable() { public void run() { if (dlgs == 0) audioMenu(); } });
      tbPl = tbSubs(tl, "", new Runnable() { public void run() { playerMenu(); } });
      tbAs = tbSubs(tl, "", new Runnable() { public void run() { fitMode = (fitMode + 1) % 6; applyFit(); updateTools(); } });
      tbSubs(tl, ar ? "ملء الشاشة" : "Fullscreen", new Runnable() { public void run() {
        fsLand = !fsLand;
        try { setRequestedOrientation(fsLand ? android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE : android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT); } catch (Throwable e) {}
        hideSystem();
      } });
      tbSubs(tl, ar ? "المزيد" : "More", new Runnable() { public void run() { openMenu(); } });
      HorizontalScrollView hs = new HorizontalScrollView(this);
      hs.setHorizontalScrollBarEnabled(false);
      hs.setFillViewport(true);
      hs.addView(tl, new FrameLayout.LayoutParams(-1, -2));
      LinearLayout.LayoutParams hl = new LinearLayout.LayoutParams(-1, -2);
      hl.topMargin = dp(4);
      bar.addView(hs, hl);
      bar.setClickable(true);
      updateTools();
    }

    tvHint = tv(11, 0x80FFFFFF, false);
    tvHint.setGravity(Gravity.CENTER);
    tvHint.setPadding(0, dp(2), 0, 0);
    if (live) tvHint.setText(ar ? "↑ ↓  تغيير القناة    •    OK  إيقاف / تشغيل    •    رجوع  خروج" : "↑ ↓  Change channel    •    OK  Pause / Play    •    Back  Exit");
    else tvHint.setText(ar ? "← →  ترجيع / تقديم    •    OK  إيقاف / تشغيل    •    ↑  صوت وترجمة    •    رجوع  خروج" : "← →  Rewind / Forward    •    OK  Pause / Play    •    ↑  Audio & subtitles    •    Back  Exit");
    if (touch) tvHint.setVisibility(View.GONE);
    bar.addView(tvHint, new LinearLayout.LayoutParams(-1, -2));

    FrameLayout.LayoutParams bl = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
    int sw = getResources().getDisplayMetrics().widthPixels;
    if (touch) bl.setMargins(dp(12), 0, dp(12), dp(10)); else bl.setMargins(sw / 6, 0, sw / 6, dp(22));
    root.addView(bar, bl);

    if (touch) {
      topBar = new FrameLayout(this);
      icBack = new Ico(this, 4);
      icBack.setClickable(true);
      icBack.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { finishOut(); } });
      topBar.addView(icBack, new FrameLayout.LayoutParams(dp(46), dp(46)));
      FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.LEFT);
      tp.setMargins(dp(14), dp(12), 0, 0);
      root.addView(topBar, tp);
      root.setClickable(true);
      root.setOnClickListener(new View.OnClickListener() {
        public void onClick(View v) {
          if (bar.getVisibility() == View.VISIBLE) hideBarNow(); else showBar();
        }
      });
    }

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
    boolean lv = live || Perf.looksLive(url);
    DefaultLoadControl lc = Perf.loadControl(this, lv);
    DefaultHttpDataSource.Factory hf = new DefaultHttpDataSource.Factory()
      .setAllowCrossProtocolRedirects(true)
      .setConnectTimeoutMs(12000)
      .setReadTimeoutMs(25000);
    if (ua != null && ua.length() > 0) hf.setUserAgent(ua);
    long sbps = Perf.savedBps(this);
    pMeter = new DefaultBandwidthMeter.Builder(this).setInitialBitrateEstimate(sbps > 0 ? sbps : 3000000L).build();
    pLive = lv;
    pReady = false;
    pT0 = SystemClock.uptimeMillis();
    exo = new ExoPlayer.Builder(this, new DefaultRenderersFactory(this).setEnableDecoderFallback(true))
      .setMediaSourceFactory(new DefaultMediaSourceFactory(new DefaultDataSource.Factory(this, hf)).setLoadErrorHandlingPolicy(new DefaultLoadErrorHandlingPolicy(6)))
      .setLoadControl(lc)
      .setBandwidthMeter(pMeter)
      .build();
    exo.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true);
    exo.setVideoSurfaceView(surface);
    exo.setTrackSelectionParameters(exo.getTrackSelectionParameters().buildUpon().setPreferredTextLanguage("ar").build());
    applyFit();
    exoL = new Player.Listener() {
      @Override public void onPlaybackStateChanged(int st) {
        if (exo == null) return;
        if (st == Player.STATE_BUFFERING) { setSpin(true); stallMark(); }
        else if (st == Player.STATE_READY) { setSpin(false); playing = true; pReady = true; }
        else if (st == Player.STATE_ENDED) {
          if (live) { postFail("ENDED"); return; }
          sample();
          ended = true;
          finishOut();
        }
      }
      @Override public void onPlayWhenReadyChanged(boolean pw, int reason) { paused = !pw; updateUi(); }
      @Override public void onVideoSizeChanged(VideoSize vs) {
        if (vs.height > 0) {
          pVw = vs.width; pVh = vs.height;
          pPar = vs.pixelWidthHeightRatio > 0f ? vs.pixelWidthHeightRatio : 1f;
          applyFit();
        }
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
    exo.setMediaItem(Perf.item(this, url, pLive), pos > 0 ? pos : C.TIME_UNSET);
    exo.prepare();
    exo.setPlayWhenReady(true);
  }

  private boolean pLive = false, pReady = false, pBoosted = false;
  private long pT0 = 0;
  private DefaultBandwidthMeter pMeter;
  private final java.util.ArrayList<Long> pStalls = new java.util.ArrayList<Long>();

  private void stallMark() {
    if (!pReady || exo == null) return;
    long now = SystemClock.uptimeMillis();
    pStalls.add(now);
    while (!pStalls.isEmpty() && now - pStalls.get(0) > 90000L) pStalls.remove(0);
    if (pStalls.size() >= 3 && !pBoosted) {
      pBoosted = true;
      Perf.bump(this);
      final long p = pLive ? 0 : Math.max(0, exo.getCurrentPosition() - 2000);
      hnd.post(new Runnable() { public void run() { pStalls.clear(); begin(p); } });
    }
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
          playing = true; paused = false; vlcBuf = false; setSpin(false); updateUi(); applyFit();
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
    switch (fitMode) {
      case 0: return MediaPlayer.ScaleType.SURFACE_ORIGINAL;
      case 2: return MediaPlayer.ScaleType.SURFACE_FILL;
      case 3: return MediaPlayer.ScaleType.SURFACE_FIT_SCREEN;
      case 4: return MediaPlayer.ScaleType.SURFACE_16_9;
      case 5: return MediaPlayer.ScaleType.SURFACE_4_3;
      default: return MediaPlayer.ScaleType.SURFACE_BEST_FIT;
    }
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
    m.addOption(":network-caching=" + ((live ? 1500 : 3000) + Perf.penalty(this) * 1500 + (Perf.tier(this) == 0 ? 1000 : 0)));
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
      try { if (pMeter != null) Perf.saveBps(this, pMeter.getBitrateEstimate()); } catch (Throwable e) {}
      try { if (pT0 > 0 && pStalls.isEmpty() && !pBoosted && SystemClock.uptimeMillis() - pT0 > 600000L) Perf.relax(this); } catch (Throwable e) {}
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
      int m = fitMode;
      float vr = pVh > 0 ? pVw * pPar / pVh : 0f;
      int resize = AspectRatioFrameLayout.RESIZE_MODE_FIT;
      float ratio = vr;
      FrameLayout.LayoutParams flp = new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER);
      if (m == 0) {
        if (pVh > 0 && pVw > 0) {
          resize = AspectRatioFrameLayout.RESIZE_MODE_FILL;
          flp = new FrameLayout.LayoutParams(Math.max(1, Math.round(pVw * pPar)), pVh, Gravity.CENTER);
        }
      } else if (m == 2) resize = AspectRatioFrameLayout.RESIZE_MODE_FILL;
      else if (m == 3) resize = AspectRatioFrameLayout.RESIZE_MODE_ZOOM;
      else if (m == 4) ratio = 16f / 9f;
      else if (m == 5) ratio = 4f / 3f;
      frame.setResizeMode(resize);
      if (ratio > 0f) frame.setAspectRatio(ratio);
      frame.setLayoutParams(flp);
      frame.requestLayout();
      if (vlc != null) { vlc.setVideoScale(vlcScale()); vlcLayout.requestLayout(); }
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

  private TextView tbSubs(LinearLayout row, String label, final Runnable act) {
    TextView t = tv(13, Color.WHITE, true);
    t.setText(label);
    t.setGravity(Gravity.CENTER);
    t.setSingleLine(true);
    t.setMinHeight(dp(44));
    t.setMinWidth(dp(44));
    t.setPadding(dp(14), 0, dp(14), 0);
    GradientDrawable n = new GradientDrawable();
    n.setColor(0x33FFFFFF);
    n.setCornerRadius(dp(22));
    GradientDrawable pr = new GradientDrawable();
    pr.setColor(0xAAFFFFFF);
    pr.setCornerRadius(dp(22));
    StateListDrawable sl = new StateListDrawable();
    sl.addState(new int[]{android.R.attr.state_pressed}, pr);
    sl.addState(new int[]{}, n);
    t.setBackground(sl);
    t.setClickable(true);
    t.setFocusable(false);
    t.setOnClickListener(new View.OnClickListener() {
      public void onClick(View v) { act.run(); if (bar.getVisibility() == View.VISIBLE) { hnd.removeCallbacks(hideBar); hnd.postDelayed(hideBar, 4000); } }
    });
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
    lp.setMargins(dp(4), dp(2), dp(4), dp(2));
    row.addView(t, lp);
    return t;
  }

  private String fitName() {
    switch (fitMode) {
      case 0: return ar ? "الأصلي" : "Original";
      case 2: return ar ? "ملء الشاشة" : "Fill";
      case 3: return ar ? "تكبير" : "Zoom";
      case 4: return "16:9";
      case 5: return "4:3";
      default: return ar ? "مناسب" : "Fit";
    }
  }

  private void updateTools() {
    if (tbAs != null) tbAs.setText((ar ? "الأبعاد: " : "Aspect: ") + fitName());
    if (tbPl != null) tbPl.setText((ar ? "المشغّل: " : "Player: ") + ("vlc".equals(eng) ? "VLC" : "ExoPlayer"));
  }

  private void hideBarNow() {
    bar.setVisibility(View.GONE);
    if (topBar != null) topBar.setVisibility(View.GONE);
    subs.setBottomPaddingFraction(0.08f);
  }

  private void playerMenu() {
    if (dlgs > 0) return;
    final ArrayList<String> names = new ArrayList<String>();
    names.add("ExoPlayer");
    names.add("VLC");
    names.add(ar ? "المشغّل الداخلي (داخل التطبيق)" : "In-app player");
    sheet(ar ? "اختر المشغّل" : "Choose player", names, "vlc".equals(eng) ? 1 : 0, new Pick() {
      public void on(int i) {
        if (i == 2) { switchInternal = true; finishOut(); return; }
        String ne = i == 1 ? "vlc" : "exo";
        if (ne.equals(eng)) return;
        sample();
        eng = ne;
        vlcHw = true; vlcRetried = false; triedOther = false;
        begin(lastT);
        updateTools();
      }
    });
  }

  private void showBar() {
    updateUi();
    updateTools();
    bar.setVisibility(View.VISIBLE);
    if (topBar != null) topBar.setVisibility(View.VISIBLE);
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
    d.setCanceledOnTouchOutside(true);
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
      row.setPadding(dp(16), dp(13), dp(16), dp(13));
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
      w.setLayout(Math.min(dp(520), (int) (sw * 0.9f)), WindowManager.LayoutParams.WRAP_CONTENT);
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
    if (!live && epN > 0) {
      names.add(ar ? "الحلقة القادمة ▶" : "Next episode ▶");
      acts.add(new Runnable() { public void run() { zap(1); } });
    }
    if (!live && epP > 0) {
      names.add(ar ? "◀ الحلقة السابقة" : "◀ Previous episode");
      acts.add(new Runnable() { public void run() { zap(-1); } });
    }
    names.add(ar ? "الصوت" : "Audio");
    acts.add(new Runnable() { public void run() { audioMenu(); } });
    names.add(ar ? "الترجمة" : "Subtitles");
    acts.add(new Runnable() { public void run() { subMenu(); } });
    names.add((ar ? "ملاءمة الشاشة: " : "Aspect: ") + fitName());
    acts.add(new Runnable() { public void run() { fitMode = (fitMode + 1) % 6; applyFit(); updateTools(); toast(ar ? "تم تغيير الملاءمة" : "Aspect changed", 1200); } });
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
    if (nw != null) { nw.stop(); nw = null; }
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
import os
raw = Image.open('logo.png').convert('RGBA')
px = raw.load()
W, H = raw.size
opaque = raw.getchannel('A').getextrema()[0] > 250
if opaque:
    # photo/JPG logo (white on dark): brightness becomes the alpha, so the logo is clean and uncropped on any background
    lum = raw.convert('RGB').convert('L')
    lut = [max(0, min(255, int((v - 44) * 255 / 206))) for v in range(256)]
    al = lum.point(lut)
    logo = Image.new('RGBA', raw.size, (255, 255, 255, 0))
    logo.putalpha(al)
else:
    logo = raw
bb = logo.getchannel('A').point(lambda v: 255 if v > 90 else 0).getbbox()
if bb:
    pad = int(0.05 * max(bb[2] - bb[0], bb[3] - bb[1]))
    box = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(logo.width, bb[2] + pad), min(logo.height, bb[3] + pad))
    logo = logo.crop(box)
def make(w, h, path, scale):
    im = Image.new('RGB', (w, h), (0, 0, 0))
    k = min(w * scale / logo.width, h * scale / logo.height)
    l = logo.resize((max(1, int(logo.width * k)), max(1, int(logo.height * k))), Image.LANCZOS)
    im.paste(l, ((w - l.width) // 2, (h - l.height) // 2), l)
    im.save(path)
make(320, 180, 'android/app/src/main/res/drawable/banner.png', 0.78)
make(192, 192, 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', 0.62)
os.makedirs('android/app/src/main/res/drawable-nodpi', exist_ok=True)
k = 440.0 / logo.height
sl = logo.resize((max(1, int(logo.width * k)), 440), Image.LANCZOS)
sl.save('android/app/src/main/res/drawable-nodpi/splash_logo.png')
EOF
python3 -c 'import PIL' 2>/dev/null || pip install pillow || pip install --break-system-packages pillow
python3 android/gen.py
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null || true
(cd android && gradle assembleDebug --no-daemon --console=plain --stacktrace)
cp android/app/build/outputs/apk/debug/app-debug.apk hala-tv.apk
