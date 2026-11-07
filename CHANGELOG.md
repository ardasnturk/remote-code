# Changelog

All notable changes to Remote Code are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.8.0] — 2026-11-07

### Added
- **Extensions:** Settings on the Mac and on the iPhone list Promo Studio, Vitrin, MRRadar and
  FunnelRadar: install them, see newer versions, and switch their tab and alerts off.
- **MRRadar:** subscription analytics and alerts in a tab on the phone, and alerts through ntfy.
- **FunnelRadar:** funnel leaks, retention and active users in a tab on the phone, and alerts through ntfy.

## [1.7.0] — 2026-11-04

### Added
- **App Review notifications:** with Vitrin on the Mac, Remote Code tells you when an app
  is waiting for review, in review, approved, on the App Store or rejected, on the Mac
  and through ntfy on your phone. Tapping one opens the app in the Vitrin tab. It checks
  every five minutes while the Mac is awake; Settings → Notifications → App Review status
  turns it off.

## [1.6.2] — 2026-11-04

### Added
- **Vitrin tab, search:** find apps, projects and team pages from the top of the tab,
  and filter long lists (builds, reviews, testers, users and more) in place.

### Changed
- **Vitrin tab opens from a cache:** what it reads from App Store Connect is kept on
  the phone, per account. Pages open at once and most need no request; results older
  than 15 minutes to 6 hours, depending on how often they change, show right away and
  update behind the page. Each page says how old it is, and pulling down or the refresh
  button reads it again. A change made from the phone marks the cache old. Clear Cached
  Transcripts in Settings and unpairing a Mac empty it too.

## [1.6.1] — 2026-11-04

### Added
- **Lid-closed mode on battery:** when the mode is paused on battery, the Mac menu
  now offers "Use on battery too", so it can be turned on where the pause shows.

### Changed
- Promo Studio tab on iPhone and iPad (build 24): it now wears Promo Studio's own
  colors, with the indigo, violet and pink background, purple controls and gradient
  buttons, the way the Vitrin tab wears Vitrin's.

## [1.6.0] — 2026-11-04

### Added
- **Plugins:** a tool on the Mac can now become a tab on the phone with no change
  to the protocol.
- **Vitrin is the first plugin:** a third tab that runs Vitrin from the phone. Add
  your app folders with the file browser, work through the whole flow in native
  screens (setup, metadata, screens, design, video, review, upload and Claude), and
  manage App Store Connect: apps, versions, TestFlight, reviews, prices, analytics,
  users, signing and every asc command. Needs Vitrin 2.1.0 on the Mac; Settings →
  Plugins installs it. The Vitrin Mac app doesn't need to be running.

## [1.5.3] — 2026-11-04 (iOS)

### Added
- Promo Studio: plan a post for later from the phone, with automatic approval
  and posting as options; change it or start it now until its time comes.
  Needs Promo Studio 1.6.0.

### Fixed
- The "Post at" label was not translated.

## [1.5.2] — 2026-11-03 (iOS)

### Added
- Promo Studio: share as a Reel, a story, a photo post or a carousel; swipe
  through a carousel and save or share all its slides; choose the number of
  slides for a new image post. Needs Promo Studio 1.5.0.

## [1.5.1] — 2026-11-03

### Added
- Promo Studio: failures explained with a fix button (Try Again, Let Claude
  Fix It, Produce Without Voiceover, Reconnect Account) and their details.
- Promo Studio: Mac Status, the Mac's setup checklist, with a notice when the
  Mac needs attention.
- Promo Studio: photos from the library for a new video, image posts with
  Save to Photos, and choosing or re-editing people's photos (Codex).
- An "Image ready" notification on the Mac for Promo Studio image posts.
  Needs Promo Studio 1.4.0 for these.

### Changed
- Promo Studio: clearer messages when Promo Studio isn't open on the Mac or is
  too old for a feature.

### Fixed
- Promo Studio: Save to Photos closed the app (iOS build 18). Share now opens
  the share sheet with one tap.

## [1.5.0] — 2026-11-01

### Added
- Power controls on the iPhone (Settings → Power): keep the Mac's display on
  for a chosen time, switch lid-closed mode and "pause while on battery".
- The built-in screen is darkened while the lid is closed in lid-closed mode,
  so it no longer stays lit behind the lid (on by default; adapted from Perch).
- "Keep the display on" in the Mac's settings.
- Storage on the iPhone (Settings → Storage): free space on the Mac and a
  cleanup of caches, logs, Xcode build data, package caches, downloaded
  installers and the Trash. Items go to the Trash unless you choose otherwise.
- A "Low disk space" notification when less than 10 GB is left on the Mac.
- Memory and CPU on the iPhone (Settings → Memory and CPU): memory pressure,
  CPU load and the apps using the most, with helpers grouped into their app,
  and a Quit / Force Quit button.
- A "Memory almost full" notification that names the app using the most memory.
- Promo Studio: free-form videos from the phone, next to the promo film and
  the quick template (needs Promo Studio 1.2.0).
- Promo Studio: choose a post's cover frame from the phone; it is also the
  Reel's cover on Instagram (needs Promo Studio 1.2.2).
- Promo Studio: a Templates section for the Mac's template libraries (Promo
  Templates): run a video template, research trend ideas and see the videos
  made from the library (needs Promo Studio 1.2.4).
- Promo Studio: New Video (+) makes a video from a prompt or a library
  template without a project; the project and the Instagram account are
  optional.
- Promo Studio: choose a post's Instagram account, and Save to Photos or
  Share any rendered video.
- Promo Studio: New Template… adds a video template to a library on the Mac.
  Needs Promo Studio 1.3.0 for these three.

## [1.4.2] — 2026-11-01

### Fixed
- An update could stay at "Installing…" forever: the updater asked the app to
  quit from inside a main-queue job, while quitting waits for main-actor work
  (stopping the agents) that cannot run until that job ends. It now quits from
  the run loop. Updating from 1.4.1 or earlier still hits the old code once:
  if it stays at "Installing…", force quit Remote Code (⌥⌘⎋) within two
  minutes and the update finishes by itself.

## [1.4.1] — 2026-11-01

### Fixed
- Installing an update from the Mac app failed with "The update's code
  signature is invalid". The designed DMG window set Finder's "hide extension"
  flag on the app, which `codesign --strict` rejects. The DMG no longer sets it,
  the updater ignores that Finder metadata on its own copy, and the release
  script now checks the app inside the DMG the way the updater does.

## [1.4.0] — 2026-11-01

### Added
- Promo Studio notifications (D-113): when Promo Studio runs on the Mac, Remote
  Code announces a finished video, a storyboard that waits for approval, a post
  that went out and a failed job — on the Mac and, through ntfy, on the phone,
  also while the phone app is closed. Tapping one opens the post in the Promo
  Studio tab (`pilothouse://promostudio/post/<id>`). New toggles in Settings →
  Notifications → Promo Studio, on by default.
- Remaining time for Promo Studio jobs on the phone ("About 3 min left").

## [1.3.0] — 2026-11-01

### Added
- A Promo Studio tab on iPhone and iPad (D-112): when Promo Studio runs on the
  Mac, its projects, prompt-to-video, storyboards, revisions, video playback,
  captions, posting, scheduling and Instagram sign-in can be used from the
  phone. The Mac app bridges the `promoStudio` capability to Promo Studio's
  local, token-protected API; the tab is hidden when Promo Studio is not
  running.

### Fixed
- Settings… in the menu now brings the Settings window to the front. Remote
  Code is a menu bar app, and the window used to open behind the frontmost app.

## [1.2.0] — 2026-10-25

### Changed
- First release as **Remote Code**: new name, new icon (a `>_` prompt with a
  signal), repository `ardasnturk/remote-code` and website
  rcode.ardasnturk.com. Pairings, settings, session logs and the keychain
  identity of earlier versions carry over. The Mac app is `Remote Code.app`
  and the Homebrew cask `remote-code`.

### Added
- "Allow everything in this chat" on the permission sheet, and a Permissions
  picker in the chat's menu: a chat's permission mode can now change at any
  time, even during a reply. "Bypass permissions" still has to be allowed in
  the Mac's settings first.

### Fixed
- "Open Remote Code at login" no longer looks switched off while it is on. The
  switch is read again whenever Settings opens or the app comes to the front,
  counts a login item that waits for approval as on and offers to open Login
  Items for it, and errors now show in Settings instead of the menu.
- The weekly summary is written in the language the iPhone app is shown in,
  not the Mac's, and no longer mixes languages.

[Unreleased]: https://github.com/ardasnturk/remote-code/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/ardasnturk/remote-code/releases/tag/v1.2.0
