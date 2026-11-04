package ai.deepily.lupin_mobile

import android.content.Context
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FragmentActivity, not FlutterActivity: local_auth shows the fingerprint
// prompt through a FragmentActivity and throws without one (row 8ff78c69).
//
// The engine is shared with the podcast media session (audio_service), so the lock screen and
// earbuds keep working after the activity is destroyed and reopened (row 3469e9db, P3).
class MainActivity : FlutterFragmentActivity() {
    override fun provideFlutterEngine( context: Context ): FlutterEngine {
        return AudioServicePlugin.getFlutterEngine( context )
    }
}
