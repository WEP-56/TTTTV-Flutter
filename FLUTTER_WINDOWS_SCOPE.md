# Flutter Windows Migration Scope

Date: 2026-03-26

## Fixed decisions

- First migration release target: `Windows` only.
- Initial Rust integration mode: `HTTP first`.
- Surviving Rust backend: `Moovie` only.
- Deprecated backend path: `moovie-front/src-tauri/src_backend`.

## In-scope for the first Windows cut

- Backend health/startup wiring
- Source loading and source management
- VOD search
- VOD detail
- VOD play parse
- Favorites
- History
- Basic desktop shell and settings needed to support the VOD flow

## Out of scope for this cut

- Live home page parity
- Live room playback parity
- Danmaku
- Live auth
- Android, iOS, macOS packaging

## Rules during migration

- Do not add new business logic to `moovie-front/src-tauri/src_backend`.
- Keep existing localhost HTTP contracts stable while Flutter VOD pages are being built.
- Keep crawler, parse, live-provider, danmaku, cookie, and storage logic in Rust.
- Only move presentation, navigation, state orchestration, and player UI into Flutter.

## Immediate execution order

1. Make `Moovie` library-first while preserving `cargo run` behavior.
2. Freeze DTOs used by search, detail, play, sources, history, and favorites.
3. Create the Flutter Windows shell and call the Rust localhost backend.
4. Rebuild the VOD search -> detail -> play path before touching live features.
