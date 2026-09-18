# ADR-0039: Prune ad scheduling where the player response is parsed

## Status

Accepted

## Context

Ad blocking pruned ad fields only from the inline `ytInitialPlayerResponse` of a
YouTube watch page. Measuring a live `music.youtube.com/watch` document showed
that page ships no inline player response at all: every track — the first one
included — arrives as `fetch` → `Response.text()` → `JSON.parse` of a
`youtubei/v1/player` payload carrying `adPlacements`, `playerAds`, `adSlots` and
`adBreakHeartbeatParams`. The inline trap therefore never fired on YouTube Music,
which played audio ads while the YouTube watch page stayed clean. The music
player also keeps one document for a whole session (ADR-0034), so a per-document
trap cannot cover later tracks either.

Rewriting the fetched `Response` was measured earlier to blank the player, and a
hook whose `Function.prototype.toString` does not report `[native code]` is what
YouTube's anti-adblock detects.

## Decision

Hook `JSON.parse`, and prune the known ad keys from the parsed object in place,
returning the object the parser produced. Nothing is re-serialized, no `Response`
is rebuilt, and no object identity changes. The hook is registered in the
existing toString mask, so it still reports as native. The inline
`ytInitialPlayerResponse` trap stays for the YouTube watch page, which reads it
before any fetch. The DOM skip/mute backstop stays for whatever still surfaces.

The hook is installed at document start, so a single installation covers every
later SPA navigation and every refetched track in that document.

## Consequences

YouTube Music ads are pruned at the same point YouTube Music reads them.
Verified against live pages: with the hook the fetched payload reaches the player
with no ad keys left and playback is unaffected, on both `music.youtube.com` and
`www.youtube.com`; without it the same page plays a sponsored pre-roll.

Every `JSON.parse` in the page now pays a five-key presence test; pruning itself
only runs on payloads that carry ad fields. Server-stitched (SSAI) ads remain out
of reach. If YouTube moves the player response onto `Response.json()`, which does
not route through `JSON.parse`, the hook must be extended to that path.
