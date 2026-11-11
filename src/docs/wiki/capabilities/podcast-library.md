---
capability: podcast-library
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.services.audio.podcast_catalog.PodcastCatalog@b54f656b6e
  - lupin-mobile:lib.services.audio.podcast_catalog.PodcastListEntry@c890512e47
  - lupin-mobile:lib.features.podcasts.podcast_list_screen.PodcastListScreen@be7efa4e7c
  - lupin-mobile:lib.features.podcasts.data.podcast_drive_repository.PodcastDriveRepository@5a0bbedea0
  - lupin-mobile:lib.features.podcasts.data.podcast_drive_repository.DrivePodcastFolder@13aa11c552
  - lupin-mobile:lib.features.podcasts.data.podcast_drive_repository.DrivePodcastFile@a95e6e0dfd
  - lupin-mobile:lib.features.podcasts.data.podcast_drive_repository.PodcastDriveException@f5158cf80a
  - lupin-mobile:lib.features.notifications.presentation.podcast_done_actions.PodcastDoneActions@dca4a553e8
  - lupin-mobile:lib.features.notifications.presentation.podcast_done_actions.PodcastAudio@99563d363a
  - lupin-mobile:lib.features.notifications.presentation.podcast_done_actions.parsePodcastAudio@469bbabd6f
---
# Podcast library

The Podcasts screen and the Play buttons on a finished podcast's card. Playback is in [[podcast-playback]] and downloads are in [[podcast-downloads]].

## What it does
- `PodcastListScreen` lists the phone's podcasts first, then every podcast kept in Google Drive. The phone's rows come from the catalog and the download folder, so they play with no network.
- `PodcastCatalog` holds finished podcasts the app has heard of, plus downloads. Each title is saved beside its file, so a restart still shows real titles.
- `PodcastDriveRepository` lists the Drive folders through the Lupin server, newest first. The phone never signs in to Google. A failure is a `PodcastDriveException` in words the screen can show.
- A `DrivePodcastFolder` is one job's folder, titled by its `title` or else the folder name. A `DrivePodcastFile` has a stream path, and `isAudio` says whether the player can play it.
- Each Drive row has one button. Download keeps a copy on the phone. Once downloaded it is Delete, which removes only the phone's copy, never the Drive file, with a snackbar Undo.
- If the Drive list fails, the phone's rows still show and the Drive section says why.
- `parsePodcastAudio` reads a done abstract, one audio link per line. It accepts `/app/audio?path=` and `/api/io/file?path=` links. The label is the line's leading bold text, else "Podcast".
- `PodcastDoneActions` draws a Play button for each entry and nothing when there is none, so any card can carry it. A downloaded entry has a check mark.

## Don't
- Don't ask before Delete. It shows Undo, and the copy goes when the snackbar ends.
- Don't delete a podcast that is playing. Its copy goes when the player stops or moves on.
