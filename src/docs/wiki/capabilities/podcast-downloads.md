---
capability: podcast-downloads
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.audio.podcast_cache.PodcastCache@419f40877e
  - lupin-mobile:lib.services.audio.podcast_cache.CachedPodcast@6041994846
  - lupin-mobile:lib.services.audio.podcast_cache.podcastCacheDirectory@e8f022a85d
  - lupin-mobile:lib.services.audio.podcast_cache.preparePodcastCache@de46f7afda
  - lupin-mobile:lib.services.audio.podcast_link.PodcastLink@b6df6056a0
  - lupin-mobile:lib.services.audio.podcast_link.currentPodcastLink@b4e824561c
  - lupin-mobile:lib.services.audio.podcast_link.podcastLinkOf@deedfcf050
  - lupin-mobile:lib.features.artifacts.podcast_play.podcastPlayFor@7ed68134b0
  - lupin-mobile:lib.features.artifacts.podcast_play.podcastCacheName@34c76c9f93
  - lupin-mobile:lib.features.artifacts.podcast_play.audioPathOf@4f41dc6590
  - lupin-mobile:lib.features.artifacts.podcast_prefetch.PodcastPrefetcher@9948bb4cc3
  - lupin-mobile:lib.features.artifacts.podcast_download_sheet.showPodcastDataSheet@e7c3dfc17b
---
# Podcast downloads

Podcasts are downloaded to the phone, so they play again with no network. The player is in [[podcast-playback]]; the list that shows downloads is in [[podcast-library]].

## What it does
- `PodcastCache` keeps downloads in `podcasts` under the app's support directory, which the system does not clear when space runs low. A download goes to a `.part` file and counts only once renamed to `<name>.mp3`.
- `preparePodcastCache` runs at startup. It deletes downloads older than 30 days, then learns what is left, and never throws. Titles are saved beside the files.
- `podcastCacheName` is the percent-encoded server path, one name per path, with no slash. `audioPathOf` reads the server path from a link, whether bare or in a `path` query.
- `podcastPlayFor` is the one place a card's Play goes. Playing the same path again resumes it; a different path replaces it.
- `PodcastLink` says how the phone is connected. Wi-Fi and Ethernet are unmetered, none is offline, and every other link counts as metered.
- A metered link needs the listener's say-so. `showPodcastDataSheet` asks "Download over mobile data?" in an in-app sheet, never a system dialog.
- `PodcastPrefetcher` downloads the audio a done card names, but only on an unmetered link. On a metered or missing link it does nothing.

## Don't
- Don't spend mobile data without asking. Doubt about the link counts as metered.
- Don't derive a cache name from a label. A label is not unique.

## Invariants
- Two different server paths never share a cache name.
