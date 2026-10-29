package `in`.co.hux.hux_app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle

// Opened by Health Connect when the user taps HUX's privacy policy link
// (ACTION_SHOW_PERMISSIONS_RATIONALE, and VIEW_PERMISSION_USAGE via the
// manifest alias on Android 14+). Google requires this to show the same
// privacy policy as the Play listing. Keep the URL in step with
// LegalConfig.privacyPolicyUrl in lib/core/legal/privacy_notice.dart.
class HealthPrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_POLICY_URL)))
        } catch (_: ActivityNotFoundException) {
            // No browser installed: nothing else we can show here.
        }
        finish()
    }

    companion object {
        const val PRIVACY_POLICY_URL = "https://hux.co.in/privacy"
    }
}
