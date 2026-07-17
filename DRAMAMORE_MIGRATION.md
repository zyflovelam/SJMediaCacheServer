# DramaMore Fork Migration Notes

This Fork is the online HLS cache layer for DramaMore. It is not the member
offline-download implementation.

## Included changes

- Adds an iOS 16+ Swift Package and carries only the required SQLite3 source
  from the upstream `SJUIKit` dependency.
- Stores online media cache data under
  `Library/Caches/DramaMore/StreamingMediaCache` and marks the directory as
  non-backup data.
- Binds the proxy listener to `127.0.0.1` only. The upstream AirPlay switch is
  retained for source compatibility but is intentionally ignored.
- Disables third-party console logging by default. The host app owns all
  sanitized diagnostics.
- Uses the complete URL as the safe default cache identity. The host app must
  replace it with `episodeId + assetId + assetVersion + quality` before
  converting a playback URL to a proxy URL.
- Replaces the CocoaPods resource bundle MIME fallback with the media MIME
  types required by HLS playback, so the Objective-C SPM target has no resource
  bundle dependency.

## Host App integration contract

1. Call `/play` to obtain the current origin playback URL and authorization.
2. Register the stable cache identity before calling `proxyURLFromURL:`.
3. Build `AVPlayerItem` from the returned localhost proxy URL.
4. On a disk hit, start the player immediately and validate `/play` in
   parallel. Pause if the server denies entitlement.
5. On a cache miss, use the current origin URL and allow the proxy to write
   fetched HLS resources to disk.
6. Keep online cache capacity at 256 MB. Keep member offline `.movpkg`
   downloads in a separate 1 GB quota.

## Required validation before DramaMore integration

- Simple and multi-variant HLS playlists, including `EXT-X-MAP`, subtitle,
  audio-rendition, and encrypted-key resource requests.
- Playback while cache writes are active.
- Re-enter the same episode after 5 seconds of viewing: cached first segments
  should be served before network media requests.
- Token refresh: a new signed `/play` URL must continue cache misses without
  changing the stable cache identity.
- Entitlement failure after a disk hit pauses playback.
- Verify the proxy cannot be reached through the device LAN IP.
