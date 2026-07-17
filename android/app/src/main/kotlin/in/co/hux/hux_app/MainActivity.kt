package `in`.co.hux.hux_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: the `health` package's
// dev-only Health-Store adapter (HUX_SOURCE=health) needs
// registerForActivityResult when requesting Health Connect permissions
// on Android 14+, which requires casting this Activity to
// ComponentActivity.
class MainActivity : FlutterFragmentActivity()
