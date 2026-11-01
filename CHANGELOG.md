# Changelog

All notable changes to Remote Code are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
