# ADR-0038: Native Discord Rich Presence over the local IPC socket

## Status

Accepted

## Context

Issue #34 asked for Discord Rich Presence. The reporter had tried the PreMiD
browser extension through Kaset's WebExtension support: it loaded, but its
options page could not sign in to Discord, so it never worked. That is not a
bug we can fix — PreMiD is a browser extension paired with a separate native
companion app, and its options page expects a full browser OAuth environment.

Discord's own Rich Presence transport does not need any of that. The desktop
client listens on a Unix domain socket at `discord-ipc-0` … `discord-ipc-9` in
the user's temporary directory and speaks length-prefixed JSON: an 8-byte
little-endian header (opcode, byte count) followed by the payload. No OAuth, no
network access, no account credentials.

Two things had to be verified before committing to this:

1. **Sandboxing.** `AGENTS.md` states the app is sandboxed, which would put
   Discord's socket outside the container and make this approach unworkable.
   The shipped entitlements disagree: `Kaset.entitlements` sets
   `com.apple.security.app-sandbox` to `false`, and `codesign -d --entitlements`
   on the built bundle confirms it. `NSTemporaryDirectory()` therefore resolves
   to the real user temporary directory, where Discord's socket lives. (A stale
   `~/Library/Containers/com.sertacozercan.Kaset` directory exists from an
   earlier sandboxed build and misleads; it is not in use.)
2. **The transport.** A probe against a running Discord connected, sent a
   handshake and received `{"code":4000,"message":"Invalid Client ID"}` — the
   expected rejection for a bogus Application ID, which proves the socket,
   framing and response parsing all work.

## Decision

1. Implement the IPC client natively in `DiscordIPCClient`, with **no third-party
   dependency**: the wire format is ~40 lines of framing over `Darwin` sockets.
   It is an `actor`, so socket I/O stays off the main actor.
2. **Poll, do not observe.** Discord rate-limits presence updates to roughly 5
   per 20 seconds. `DiscordRichPresenceService` samples the players every 5
   seconds and transmits only when an `Equatable` snapshot changes. Nothing in
   the playback path needs to know the feature exists, which keeps it clear of
   the queue and identity machinery.
3. **Elapsed time is not part of the snapshot.** It advances every second and
   would defeat the change-detection above. Discord draws the progress bar from
   a start timestamp instead, derived as `now - elapsed` and rounded to a
   second so poll jitter is not mistaken for a seek.
4. **One built-in Application ID, and no way to change it.** An earlier draft
   argued for no default at all, on the grounds that a shared ID puts one
   application's name on everybody's profile. That is backwards: the ID is a
   public identifier rather than a credential (comparable to a bundle ID), and
   the application's name showing on every profile is precisely the branding
   the feature exists to provide — "Listening to KasetPlus". Every comparable
   client ships exactly one: th-ch/youtube-music, the closest analogue, has
   `export const clientId = '1177081335727267940'` — itself an unverified
   application merely *named* "YouTube Music", since no official Google one
   exists. KasetPlus's is `1550196014063943710`.

   A per-user override field was built and then removed: it was a text box
   that every user had to understand and almost none would ever change, and a
   wrong value there produces a feature that silently fails to connect. The
   setting is now one toggle. Discord accepts any existing application ID
   regardless of who owns it, so an override was never a security boundary
   either — only an invitation to misconfigure.
5. Music publishes as activity type 2 ("Listening to"), video as type 3
   ("Watching"), matching what each source actually is.
6. **Drain the socket before every command.** Discord answers each command with
   a frame, and the client sends without reading. Measured against a running
   Discord: unread answers queue in the receive buffer, saturate it at ~8 KB —
   roughly fifty commands, or a dozen with a real activity echoed back — and
   from then on Discord stops reading our frames while `write` keeps reporting
   success, so the presence silently freezes on whatever it last showed. A
   non-blocking drain before each command keeps the queue at one answer, and a
   closed peer found there fails the write so the service reconnects.
7. **A paused track says so on the state line.** Dropping the timestamps only
   removes the progress bar, and `small_text` is the tooltip of a `small_image`
   this application does not ship, so neither is visible as a pause.

## Consequences

- The feature is off by default; enabling the toggle is the whole setup, and
  nobody's presence changes without that explicit opt-in.
- A rejected handshake fails identically on every retry, so the service stops
  and reports `rejected` rather than reconnecting forever. With the ID fixed at
  build time this should now be unreachable; a test pins the constant so a typo
  fails the suite instead of shipping as a presence that never appears. Discord not running
  is retried every 30 seconds instead of every 5.
- Field clamping matters more than it looks: Discord silently drops an entire
  activity when `details` or `state` falls outside 2–128 **bytes**. A unit test
  caught the ellipsis budget being computed in characters, which pushed a
  truncated title to 130 bytes.
- If the app is ever sandboxed again, this feature breaks and would need a
  temporary-exception entitlement for the socket path. The `socketPaths()` test
  pins the assumption to `NSTemporaryDirectory()` so the reason stays visible.
- Artwork is passed as a plain URL in `assets.large_image`. Discord's support
  for external URLs there is inconsistent; when ignored the presence simply
  shows no image, so it degrades rather than failing.
