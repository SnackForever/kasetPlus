# Upstream sync ledger

Tracks the fork's sync state against `sozercan/kaset`: what's **pending**, what's
**already taken**, and what we **deliberately skip** — so a future sync can tell a
skipped commit from a missed one, and doesn't re-take something already ported.

Check what's pending with:

```bash
git fetch upstream
git log --oneline --no-merges main..upstream/main   # commits we don't have as ancestors
git cherry main upstream/main                        # '+' = not applied even as a patch
```

Cross-check every `+` by **PR number** against the "Already synced" table below
before re-taking it: `git cherry` still shows `+` for adapted picks because the
patch-ids differ once the fork's code has diverged.

**Convention:** upstream fixes are **cherry-picked onto `main`**, adapted where
the fork diverged, keeping the original author and message (the `(#NNN)` suffix is
sometimes dropped, but the subject is preserved). Add a row to the relevant table
on every pick or skip.

**Baseline / ancestry:** everything up to upstream `50685c9` came in via the
wholesale merge `f180d2e` (2026-07-13). Since then, upstream PRs are
**cherry-picked** (adapted), so their original SHAs are not in our ancestry —
which is why GitHub showed the fork "N commits behind" even after syncing.
On 2026-07-21, after cherry-picking through upstream `c1dae03`, a
`git merge -s ours upstream/main` recorded that main is caught up **without
changing any code** (we already had the content): the fork now reads **0
behind**, and `git log main..upstream/main` starts empty from `c1dae03`.
Repeat that `-s ours` merge after each cherry-pick batch to keep the baseline
clean. (The fork stays permanently "ahead" — that's its own features, expected.)

## Pending (to sync)

None outstanding as of upstream `df34d17` (#488, last sync). Re-check with the
commands above; cross-check any new `+` result by PR number against the tables
below before taking it.

Upstream `712f19c` (#384 Sign Out) and `5f73f4a` (#415 Float-on-top) were both
**already ported independently** by the fork (`5a5f526`, `ad5dd6d`) before the
upstream commits existed, so they are skipped — see the note below.

## Already synced

Individually cherry-picked/adapted since the `f180d2e` baseline (newest first).

| PR | Upstream | Our commit | What it is |
|----|----------|-----------|-----------|
| [#488](https://github.com/sozercan/kaset/pull/488) | `df34d17` | `4f833fa` | perf(home): skip re-evaluating unchanged shelf cards while scrolling — applied clean. |
| [#486](https://github.com/sozercan/kaset/pull/486) | `8818804` | `441858f` | fix(homebrew): replace deprecated `postflight` with `postflight_steps` — applied clean to both the (deprecated) `Casks/kaset.rb` and the release workflow's generated cask. |
| [#487](https://github.com/sozercan/kaset/pull/487) | `5363436` | `ac7004a` | fix(home): restore infinite scroll and stop the startup reload — applied clean. |
| [#485](https://github.com/sozercan/kaset/pull/485) | `26714e9` | `3d9d479` | feat(parser): resolve the audio recording behind music-video album rows — applied clean. |
| [#482](https://github.com/sozercan/kaset/pull/482) | `2bc73a7` | `566f1c5` | chore: remove obsolete code and restore test coverage (−830 lines: `AppleMusicScrubber`, dead parser/LibraryViewModel paths, root-level scratch scripts) — applied clean. |
| [#476](https://github.com/sozercan/kaset/pull/476) | `ec94df9` | `56bc0a3` | fix(auth): preserve live WebKit login when archive is unavailable + ADR 0037 (deferred cookie restoration) — only the localization files conflicted (fork catalog formatting); 2 new keys merged into the catalog and mirrors regenerated. Swift applied clean. |
| [#474](https://github.com/sozercan/kaset/pull/474) | `0061720` | `59bdf7f` | fix(airplay): preserve routes and anchor device pickers — one conflict in `YouTubePlayerBar.swift`: kept the fork's `Mode`-based init and `OptionsTier` overflow layout, added `airPlayAnchor` state and re-applied `showAirPlayPicker(at:)` + `AirPlayPickerAnchorView` to **both** fork call sites (icon button and overflow-menu item; upstream only has the first). |
| [#473](https://github.com/sozercan/kaset/pull/473) | `7f8dbfe` | `8c0f078` | fix(ui): correct sidebar highlight spacing — applied clean. |
| [#248](https://github.com/sozercan/kaset/pull/248) | `c3134a3` | `12e9e2d` | feat(player): gapless queue handoff and SPA navigation (**63 files, +13.7k**) — YouTube Music native Up-Next mirroring, `SingletonPlayerWebView+QueueInjection`, observer epochs/media generations, ADRs 0035/0036. Applied **clean** (it lands almost entirely in the music singleton player, which the fork barely touched). Its new tests pass in isolation; see the cross-suite flake note below. |
| [#472](https://github.com/sozercan/kaset/pull/472) | `6473b58` | `28c43cc` | feat(api-explorer): add read-only API discovery (`DiscoveryAudit`) — applied clean on top of the fork's `--hl` flag. |
| [#470](https://github.com/sozercan/kaset/pull/470) | `a928944` | `b1c07aa` | fix(playback): detect and label YouTube and YouTube Music ads — shared `PlaybackAdDetectionScript` replaces the fork's inline `isAdShowing()` in the watch script (the fork's `isAdSkippable()` / `liveState()` / `__kasetSeekToLive` helpers kept). `YouTubePlayerBar` progress lane wrapped in the ad-indicator switch **around the fork's full lane** (heatmap, segments, hover preview, live edge). 2 catalog keys (`Ad`, `Advertisement`) merged, mirrors regenerated. |
| [#471](https://github.com/sozercan/kaset/pull/471) | `b6c2b28` | `1afec53` | fix(player): expand mini player drag area — applied clean. |
| [#464](https://github.com/sozercan/kaset/pull/464) | `d8d71a6` | `e237073` | fix(player): make mini player window draggable — upstream extracts `WindowDragHandle` into its own file; the fork already had an equivalent `private` copy inside `YouTubeVideoWindowController`. Deleted the private copy in favour of the shared one (fork's double-click rationale comment carried over) and kept the fork-only `AccessibilityID.YouTubeContent.videoWindow` extension, which upstream keeps in `AccessibilityIdentifiers.swift`. |
| [#442](https://github.com/sozercan/kaset/pull/442) | `b2649f1` | `b53907d` | feat(ui): make artist names clickable in track list rows (`HoverUnderlineNavigationLink`, `PlaylistTrackRow`) — four view conflicts were purely the incidental `.aspectRatio(contentMode: .fill)` → `.scaledToFill()` normalization; resolved to the fork's layout and the rename applied mechanically. `unused_import` moved to `analyzer_rules` in `.swiftlint.yml`. |
| [#423](https://github.com/sozercan/kaset/pull/423) | `6e4a643` | `944ec72` | fix(api): send YouTube's `utcOffsetMinutes` sign, fixing `YTMusicClient` — applied clean. |
| [#469](https://github.com/sozercan/kaset/pull/469) | `90a0e71` | `fbdd584` | fix(ui): align sidebar item indentation — applied clean. |
| [#468](https://github.com/sozercan/kaset/pull/468) | `1e185bf` | `7253386` | fix: keep YouTube audio playing after closing window (`MainWindowRegistrationView`) — applied clean. Overlaps the fork's own "keep playing in the bar" navigate-away work (`4cf603a`); both coexist but the combination is **not runtime-verified**. |
| [#463](https://github.com/sozercan/kaset/pull/463) | `0ecccf0` | `0dea1ff` | perf: reduce authenticated startup latency (podcasts availability moved off the startup path) — applied clean. |
| [#465](https://github.com/sozercan/kaset/pull/465) | `eb6aa73` | `337c48a` | fix(dev): default `compile_and_run.sh` to debug — applied clean. |
| [#460](https://github.com/sozercan/kaset/pull/460) | `299e3b0` | `9ec1c02` | fix(player): restore volume slider interaction (`PlayerBarVolumeOverlayHost`) — three conflicts. Upstream's `YouTubeVideoWindowLevelPolicy` enum was **dropped**: it belongs to upstream's #415 float-on-top, which the fork ported independently (`ad5dd6d`), so `shouldShowChrome` is inline as `showsWindowChrome` in the window content instead. The fork's `Mode` enum replaces upstream's `isDetachedWindow` init, so `onVolumeOverlayChange` became a memberwise property. The volume overlay also had to be added to the fork's **idle-hide** guard (`hideControls`) so the slider doesn't dismiss itself after the 3 s countdown (#33). Upstream's three float-on-top `YouTubePlayerBarTests` were dropped with the enum. |
| [#459](https://github.com/sozercan/kaset/pull/459) | `99368a1` | `baa4fec` | fix(playback): bound WebKit memory growth + ADR 0034 — track changes navigate via `window.location.replace` instead of `WKWebView.load`, so WebKit stops accumulating back-forward entries and their retained media state; teardown removes script handlers/delegates and closes the matching WebExtension tab. |
| [#453](https://github.com/sozercan/kaset/pull/453) | `edfec10` | `a5d4171` + `c0526a7` | fix(auth): route Google passkey sign-in to a working fallback (#291) — adapted in `c0526a7`. |
| [#448](https://github.com/sozercan/kaset/pull/448) | `83e3797` | `b9e3ae9` | fix(tests): eliminate the two cross-suite unit test flakes. |
| [#447](https://github.com/sozercan/kaset/pull/447) | `53763c1` | `ec03008` | fix(player): stop the page URL being stored as track artwork. |
| [#425](https://github.com/sozercan/kaset/pull/425) | `f7e6b61` | `ec95e87` | feat: refresh Home suggestions on demand. |
| [#426](https://github.com/sozercan/kaset/pull/426) | `be0eae7` | `6d0d8e9` | fix(lyrics): prevent Bengali romanizer crash on mixed-script text. |
| [#416](https://github.com/sozercan/kaset/pull/416) | `bb3a555` | `3459039` | feat(youtube): add Ask Gemini video conversations — the large feature port (**112 files, +24k**): additive `YouTubeAskCore` module, Ask models/views/view models, cookie-backup subsystem, tests, ADR 0032; auth/webkit/login mods auto-merged. Conflicts resolved against the fork's watch-page work: kept both `getPlayability` (members gate) and the new `getWatchPage` (extended with optional `playlistId` so Mix context survives); merged `load` to keep collaborators/notifications/live-chat/members-gate alongside Ask bootstrap seeding + account-scope reset; kept inline player wiring (`upNextQueue` + heatmap) over the new lifecycle helper, and the promoted non-DEBUG ambient picker; re-ported the fork's `--hl` flag into APIExplorer's unified switch. 23 new loc keys injected + mirrors regenerated. **Builds clean but NOT runtime-verified** — Ask touches auto-merged auth/webkit and the test target is pre-existing broken (`MockYouTubeWatchPlaybackController` lacks `availableAudioTracks`). Needs manual QA before release. |
| [#419](https://github.com/sozercan/kaset/pull/419) | `0576fd5` | `61edfd6` | feat(l10n): add Simplified & Traditional Chinese — the catalog already carried zh (Crowdin) but mirrors were unregistered, no `ContentLanguage` case existed to select Chinese, and no `apiRegionCode` mapping. Added Package.swift mirror registration, `.simplifiedChinese`/`.traditionalChinese` cases (region CN/TW), regenerated zh mirrors from the catalog, and ported the APIExplorer `--hl` probe flag. README language-count line skipped (fork uses Crowdin badges). |
| [#383](https://github.com/sozercan/kaset/pull/383) | `e0bb015` | `7a7ca1e` | fix: scope favorites per account — the account-scoped-favorites rework (**+4398 lines**): `FavoritesManager` (+947), `AccountService` (+663), `AuthService` (+184), `YTMusicClient`/`YouTubeClient`, `LoginSheet`, a legacy-migration claim system, ADR 0030, plus a +740-line `FavoritesManagerLegacyMigrationClaimTests`. Nearly all auto-merged; one conflict in `MainWindow.swift` resolved to HEAD — kept the fork's onboarding/What's-New auto-present `.task` AND the login-check `.task` (idempotent; KasetApp's root task already drives startup login/account fetch). New test's import renamed `Kaset`→`KasetPlus`. Fork behaviours confirmed intact: guest mode, brand accounts (`brandId`/`onBehalfOfUser`), Community hub, sidebar pinned favorites. #383's favorites/account/auth suites all pass. |
| [#387](https://github.com/sozercan/kaset/pull/387) | `c1dae03` | `0ef8bbb` | fix(player): claim Now Playing slot so media keys control Kaset when paused — applied clean on top of #374's `NowPlayingManager`. New test file's import renamed `Kaset`→`KasetPlus`. |
| [#398](https://github.com/sozercan/kaset/pull/398) | `e44cbb1` | `38a5523` | feat(youtube): segment video chapter seek bar — applied clean on top of #368's `PlayerBarProgressLane`. New test file's import renamed. |
| [#368](https://github.com/sozercan/kaset/pull/368) | `c8e15f9` | `2b1fa21` | feat: YouTube-style segmented seek bar for mixes — new `NowPlayingTracklistProvider`, extended `MixTracklistParser`, rewritten `PlayerBarProgressLane`/`PlayerBar`. Two conflicts resolved (`KasetApp.swift`, `PlayerBarProgressLane.swift`): kept the fork's heatmap "most replayed" curve and `onHoverFractionChange` on-video overlay callback alongside the incoming segmented track + hovered-segment handling. Landed after #374. |
| [#389](https://github.com/sozercan/kaset/pull/389) | `0eadb78` | `80ff911` | fix(player): de-flake Smart Shuffle tests by reading config per-instance (applied clean once #374 restored the test target). |
| [#391](https://github.com/sozercan/kaset/pull/391) | `a527853` | `53cda79` | fix(ai): restore discovery commands and macOS 27 compatibility — applied clean (the `musicIntent` `originalQuery` cascade and queue-ownership symbols resolved thanks to #374). New AI test files renamed `@testable import Kaset` → `KasetPlus`. |
| [#392](https://github.com/sozercan/kaset/pull/392) | `7e1cbb4` | `a89fd9d` | fix(library): reconcile liked music rating races — one conflict in `PlayerService+Library.swift` resolved to the instance-injected `self.songLikeStatusManager.cacheGeneration` (#374's injected manager). Rating-revision reconciliation on #374's machinery. |
| [#374](https://github.com/sozercan/kaset/pull/374) | `356ff92` | `4ee7d62` | fix(player): harden playback reliability and queue ownership — the foundation port (account session generations, queue-ownership/undo, `SongLikeStatusManager.invalidateSession`, account-scoped playback metadata clearing). Unblocked #392/#391/#389/#368 above. Port plan/conflict map: `docs/upstream-374-port.md`. |
| [#379](https://github.com/sozercan/kaset/pull/379) | `9fc8c34` | `97c99cc` | fix: defer playback shortcuts while editing text (applied clean) |
| [#396](https://github.com/sozercan/kaset/pull/396) | `9a42bf6` | `9a8dba9` | fix(search): preserve semantic results and pagination — app source applied clean; conflicts only in the api-explorer tool, a test helper, and the ADR index (all resolved to incoming). ADR rows for `0026`/`0027` dropped: those ADRs belong to the skipped #374 and aren't in the fork. |
| [#388](https://github.com/sozercan/kaset/pull/388) | `fefd318` | `13cf2c4` | fix(player): keep now-playing like status in sync with the like cache — its `invalidateSession(clearsActiveCache:)` hunk was dropped (method absent here; see #374 skip) |
| [#386](https://github.com/sozercan/kaset/pull/386) | `c917dc6` | `3e17c4d` | fix(l10n): correct Italian subscribe terminology and other strings |
| [#385](https://github.com/sozercan/kaset/pull/385) | `25a4b86` | `a3362b1` | fix: deliver kaset:// deep links via AppDelegate |
| [#380](https://github.com/sozercan/kaset/pull/380) | `879a7fb` | `3b000d6` | fix: pop nested navigation on sidebar re-select |
| [#378](https://github.com/sozercan/kaset/pull/378) | `47a7d4f` | `1e3f231` | feat: expand UI localizations to 15 languages |
| [#370](https://github.com/sozercan/kaset/pull/370) | `c1eedff` | `51515c6` | feat: create playlists from the sidebar |

Anything not listed here and older than the baseline came in wholesale via `f180d2e`.

## Deliberately skipped

What we deliberately do **not** take, so a future sync doesn't mistake a skipped
commit for a missed one.

| Upstream | What it is | Why skipped | If we ever need it |
|----------|-----------|-------------|--------------------|
| #479 (`466065b`) | fix(youtube): remove the ambient style toolbar picker | The fork **deliberately promoted** that picker out of `#if DEBUG` (see the #416 row) — it is a shipped KasetPlus control, not leftover scaffolding. Taking #479 would delete a fork feature. | Re-run the cherry-pick; it only touches `AmbientBackdropStyle.swift`, `YouTubeWatchView.swift`, `StoryboardSheetTests.swift`. |
| #478 (`dc1a4b9`) | fix(player): show live status for YouTube streams | **Superseded by the fork.** Upstream's fix replaces the timeline with a static "LIVE" label and hides the seek buttons. The fork already ships a richer live UI (`088fa8f`): a LIVE button that jumps to the live edge, red only when *at* the edge, plus a seekable DVR-window progress bar. Taking #478 would regress DVR seeking. | Only if the fork ever drops its DVR-window handling. |
| #462 (`ae0817a`) | Update appcast to v0.14.0 | The fork ships its own Sparkle appcast on its own `kp.N` version line. | n/a — never applicable. |
| #461 (`21b31ee`) | docs: add ADOPTERS.md with Droppy integration | Upstream-project document about who adopts *Kaset*. | n/a. |
| #384 (`712f19c`) | fix: add Sign Out to account switcher popover | Already ported independently as `5a5f526` before the upstream PR existed. | n/a — content present. |
| #415 (`5f73f4a`) | feat: Float on Top video window control | Already ported independently as `ad5dd6d` (see `docs/upstream-374-port.md`). | n/a — content present. |

_#374 (`356ff92` → `4ee7d62`) and its four dependents #392/#391/#389/#368 all landed — see "Already synced" above._

## Known post-sync test state

`swift test --skip KasetUITests` on the sync branch: **3416 tests, 32 unique
failing** vs **3013 tests, 33 unique failing** on the pre-sync `main`. The
localization-bundle suites (`AppLocalizationTests`, `LocalizationCatalogParityTests`)
fail identically before and after — pre-existing, and the catalog was verified to
be a strict superset of `main`'s (no key lost, no entry changed).

Two failures present on `main` were **fixed** by this sync (`a435628`): the
kevlar pause override bound `video.pause` unconditionally, so a media element
without a callable `pause` threw
`TypeError: undefined is not an object (evaluating 'video.pause.bind')` and
aborted the whole document-start attach.

One failure is new to the fork but **not ours**:
`PlayerServiceEndedIdentityCoordinatorTests` /
"The same-generation identity deadline resolves a pending handoff once" fails
only in a full-suite run, passes in isolation, and **fails identically on a
clean `upstream/main` checkout** (3390 tests, 22 issues, that one test) — it is
upstream's own flake, shipped with #248.

Instrumentation at the failure point showed every precondition correct
(`repeat=.off`, `shuffle=off`, `canAdvance=true`, `injected="v2"`,
`expectedNext=1`) with `injectedWebQueueVideoId` still set — i.e.
`handleTrackEnded` returned before the handoff branch. The suite is
`.serialized`, but **15 other suites** mutate the process-global
`SingletonPlayerWebView.shared` (coordinator, `currentVideoId`,
`documentGeneration`) and run in parallel with it. Fixing that needs a
serialization group across those suites — a test-infrastructure change, and
one to raise upstream rather than carry here.

Add a row **whenever a cherry-pick drops a hunk or an upstream commit is skipped
on purpose** — the cost of a stale entry is one line; the cost of a mystery gap
is an afternoon of archaeology.
