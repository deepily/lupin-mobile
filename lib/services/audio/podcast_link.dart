import 'package:connectivity_plus/connectivity_plus.dart';

/// How the phone is connected, as far as podcast downloads care.
enum PodcastLink {
  /// Wi-Fi or Ethernet: a download costs no mobile data.
  unmetered,
  /// Mobile data, or any link that might be metered: a download needs the listener's say-so.
  metered,
  /// No connection at all.
  offline,
}

/// Maps a connectivity_plus [result] to a [PodcastLink].
///
/// Ensures:
///   - wifi and ethernet are unmetered; none is offline
///   - every other link (mobile, VPN, Bluetooth, other) is metered, so doubt never spends data
PodcastLink podcastLinkOf( ConnectivityResult result ) {
  switch ( result ) {
    case ConnectivityResult.wifi     :
    case ConnectivityResult.ethernet : return PodcastLink.unmetered;
    case ConnectivityResult.none     : return PodcastLink.offline;
    default                          : return PodcastLink.metered;
  }
}

/// The phone's current [PodcastLink], read from connectivity_plus.
Future<PodcastLink> currentPodcastLink() async =>
    podcastLinkOf( await Connectivity().checkConnectivity() );
