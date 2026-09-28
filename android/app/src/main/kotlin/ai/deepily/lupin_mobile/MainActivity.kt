package ai.deepily.lupin_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FragmentActivity, not FlutterActivity: local_auth shows the fingerprint
// prompt through a FragmentActivity and throws without one (row 8ff78c69).
class MainActivity : FlutterFragmentActivity()
