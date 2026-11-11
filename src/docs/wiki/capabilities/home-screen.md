---
capability: home-screen
pin_algorithm: py3.13.x6a05a1/dart-analyzer-parseString/7.7.1
pins:
  - lupin-mobile:lib.features.home.home_screen.LupinHomeScreen@82d886f029
---
# Home screen

The signed-in user's home: a grid of cards that open the main features, and the app-bar actions. Login and logout are in [[mobile-auth]].

## What it does
- Cards run in this order: Lupin Focus, Agentic Jobs, Claude Code, Broadcast, Fleet Status, Finished Tasks, Task List, Holding Area, Job Queue, Podcasts.
- The order follows the web client, except that Lupin Focus is first. Reorder only to follow the web.
- The app bar has Settings, which opens the sound screen in [[notification-sound-and-settings]], and Logout, which sends `AuthLogoutRequested`.
- The Notifications inbox and the Trust Dashboard are hidden by two constants, each closing both its card and its app-bar icon. Their screens and tests are kept.

## Don't
- Don't hide a feature's card and leave its app-bar icon. Both doors close together, or the feature stays one tap away.
- Don't leave a spacer outside the guard of a hidden card. It would leave a visible gap.
