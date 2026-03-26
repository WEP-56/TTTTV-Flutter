# TTTTV Flutter + Rust Core Migration TODO

## 1. Objective

- Replace the current `Vue 3 + Tauri` frontend with `Flutter`.
- Keep `Moovie` as the only business core in Rust.
- Avoid rewriting source crawling, play parsing, live platform handling, danmaku bridging, and storage in Dart.
- Reach one frontend codebase for:
  - Windows
  - Android
  - iOS
  - macOS

## 2. Current State Summary

### Migration freeze for current execution

- Date: `2026-03-26`
- First release target: `Windows only`
- Initial integration mode: `HTTP first`
- Scope: `VOD usable first, live delayed`
- Scope doc: `FLUTTER_WINDOWS_SCOPE.md`
- VOD contract doc: `VOD_HTTP_CONTRACT.md`
- Status log: `MIGRATION_STATUS.md`

### Current frontend

- Stack:
  - `Vue 3`
  - `Pinia`
  - `Element Plus`
  - `hls.js`
  - `flv.js`
  - `Tauri`
- Important behavior:
  - frontend talks to Rust over local HTTP `127.0.0.1:5007`
  - frontend only lightly uses Tauri APIs for desktop window control

### Current backend

- Main backend path in use: `Moovie`
- Backend responsibilities already implemented:
  - source configuration
  - local storage
  - search
  - detail
  - play parse
  - favorites/history
  - live platforms
  - danmaku bridge
  - live proxy helpers

### Important repo note

- `moovie-front/src-tauri/src_backend` looks like an older duplicate backend path.
- Long-term architecture should keep only one Rust backend implementation.

## 3. Target Architecture

### Final target

- UI shell: `Flutter`
- Business engine: `Rust`
- Integration mode:
  - Preferred final mode: `flutter_rust_bridge`
  - Transitional mode allowed: Rust starts an in-process local HTTP server and Flutter calls localhost APIs

### Why this architecture is correct

- Existing frontend is already API-driven, so migration is mostly replacing UI/state/view code.
- The high-risk logic is already in Rust, especially live source handling and danmaku protocols.
- Flutter is the right fit for desktop + mobile UI reuse.

## 4. Core Decisions

### Decision A: Rust bridge mode

- Recommended:
  - Stage 1: keep HTTP contracts to move fast
  - Stage 2: replace HTTP boundary with `flutter_rust_bridge` for core APIs if needed
- Reason:
  - current API surface is already stable enough to migrate UI quickly
  - direct bridge is better long-term, but it should not block the first usable Flutter build

### Decision B: state management

- Recommended: `Riverpod`
- Requirements:
  - feature-scoped providers
  - async loading states
  - testable controller layer
  - no global singleton sprawl

### Decision C: player baseline

- Primary Flutter plugin: `video_player`
- Rule:
  - treat `mp4` and `m3u8` as baseline portable formats
  - treat `flv` as conditional, not guaranteed

## 5. Player Constraint and Format Policy

### What can be assumed

- `mp4`: safe baseline
- `m3u8`: safe baseline

### What cannot be assumed

- Raw `flv` should not be treated as a cross-platform default

### Practical policy

- Rust should return candidate streams in this preference order:
  - `m3u8`
  - `mp4`
  - `flv`
- Flutter player layer should:
  - prefer `m3u8`
  - fall back to `mp4`
  - only use `flv` on platforms explicitly verified

### Required outcome

- The portability problem must be solved by Rust-side normalization or platform gating.
- The Flutter player should not contain source-specific parsing logic.

## 6. Current Code Mapping

### Frontend feature mapping

- `moovie-front/src/App.vue`
  - target:
    - `lib/app/app_shell.dart`
    - `lib/app/navigation/app_navigation.dart`
    - `lib/features/settings/presentation/settings_sheet.dart`
- `moovie-front/src/components/VideoDetail.vue`
  - target:
    - `lib/features/detail/presentation/detail_page.dart`
- `moovie-front/src/components/VideoPlayer.vue`
  - target:
    - `lib/features/player/presentation/widgets/vod_player.dart`
    - `lib/features/player/application/vod_player_controller.dart`
- `moovie-front/src/components/FullscreenPlayer.vue`
  - target:
    - `lib/features/player/presentation/pages/fullscreen_player_page.dart`
- `moovie-front/src/components/LivePage.vue`
  - target:
    - `lib/features/live/presentation/live_home_page.dart`
- `moovie-front/src/components/live/LiveRoomDialog.vue`
  - target:
    - `lib/features/live/presentation/live_room_page.dart`
- `moovie-front/src/components/live/LiveVideoPlayer.vue`
  - target:
    - `lib/features/live/presentation/widgets/live_player.dart`
- `moovie-front/src/components/live/DanmakuCanvas.vue`
  - target:
    - `lib/features/live/presentation/widgets/danmaku_layer.dart`

### Frontend store mapping

- `moovie-front/src/stores/search.ts`
  - target: `search_controller.dart`
- `moovie-front/src/stores/history.ts`
  - target: `history_controller.dart`
- `moovie-front/src/stores/favorites.ts`
  - target: `favorites_controller.dart`
- `moovie-front/src/stores/settings.ts`
  - target: `sources_controller.dart`
- `moovie-front/src/stores/live.ts`
  - target: `live_controller.dart`
- `moovie-front/src/stores/liveHistory.ts`
  - target: `live_history_controller.dart`
- `moovie-front/src/stores/liveFavorites.ts`
  - target: `live_favorites_controller.dart`
- `moovie-front/src/stores/theme.ts`
  - target: `theme_controller.dart`
- `moovie-front/src/stores/appSettings.ts`
  - target: `app_settings_controller.dart`

### Rust API/domain mapping

- `Moovie/src/api/search.rs`
  - target bridge/domain:
    - `search_api.dart`
    - `detail_api.dart`
- `Moovie/src/api/play.rs`
  - target bridge/domain:
    - `play_api.dart`
- `Moovie/src/api/sources.rs`
  - target bridge/domain:
    - `sources_api.dart`
- `Moovie/src/api/history.rs`
  - target bridge/domain:
    - `history_api.dart`
- `Moovie/src/api/favorites.rs`
  - target bridge/domain:
    - `favorites_api.dart`
- `Moovie/src/api/live.rs`
  - target bridge/domain:
    - `live_api.dart`
    - `danmaku_api.dart`
- `Moovie/src/api/live_auth.rs`
  - target bridge/domain:
    - `live_auth_api.dart`

## 7. Delivery Strategy

### Recommended order

- Milestone 1: Rust becomes library-ready without breaking current desktop build
- Milestone 2: Flutter shell can launch and read backend health/sources/search
- Milestone 3: Flutter VOD path is usable end-to-end
- Milestone 4: Flutter settings/history/favorites/source management reach parity
- Milestone 5: Flutter live path is usable
- Milestone 6: danmaku and auth are finished
- Milestone 7: package and cut over

### Why this order

- It delivers user-visible value early.
- It postpones live/danmaku complexity until the basic migration path is stable.
- It keeps the highest-risk work isolated instead of mixing it with foundation work.

## 8. Detailed TODO

## Phase 0. Audit and freeze

### Goal

- Lock current scope and remove ambiguity before code moves.

### TODO

- [x] Confirm `Moovie` is the only backend to be kept.
- [x] Mark `moovie-front/src-tauri/src_backend` as deprecated in docs.
- [ ] List all current frontend features and tag them:
  - must keep
  - can defer
  - can drop
- [ ] Freeze API contract changes during initial Flutter migration.
- [x] Decide target platforms for first release:
  - Windows only
  - Windows + Android
  - all four platforms
- [ ] Decide whether web support is out of scope.
- [ ] Create a migration branch strategy:
  - `main`
  - `flutter-migration`
  - optional feature branches

### Deliverables

- [ ] feature parity list
- [ ] migration scope document
- [ ] deprecated path note for duplicate backend

### Exit criteria

- [ ] no uncertainty remains about which backend code survives
- [ ] first release platform scope is fixed

## Phase 1. Make Rust library-first

### Goal

- Convert `Moovie` from executable-first layout into reusable backend core.

### TODO

- [ ] Introduce `src/lib.rs` in `Moovie`.
- [ ] Move reusable modules behind library exports:
  - [ ] `api`
  - [ ] `core`
  - [ ] `live`
  - [ ] `models`
  - [ ] `services`
  - [ ] `utils`
  - [ ] `proxy`
- [ ] Refactor startup code out of `main.rs` into reusable functions:
  - [ ] config path resolution
  - [ ] storage path resolution
  - [ ] app state initialization
  - [ ] router creation
  - [ ] server startup
- [ ] Add an API like:
  - [ ] `build_app(config)`
  - [ ] `build_router(state)`
  - [ ] `start_local_server(options)`
- [ ] Make config path injectable.
- [ ] Make storage path injectable.
- [ ] Remove hard dependency on executable-relative resource layout inside business logic.
- [ ] Keep `main.rs` as a thin runner only.
- [ ] Preserve current `cargo run` behavior for desktop debugging.

### Rust crate structure target

- [ ] Option A:
  - `Moovie/`
  - `Moovie/src/lib.rs`
  - `Moovie/src/main.rs`
- [ ] Option B:
  - `crates/moovie_core`
  - `crates/moovie_runner`
  - `crates/moovie_ffi`

### Deliverables

- [ ] Rust core builds as library
- [ ] Rust desktop runner still works
- [ ] config/storage startup can be called from another host application

### Exit criteria

- [ ] no business logic requires Tauri
- [ ] runner and library boundaries are explicit

## Phase 2. Define bridge-facing contracts

### Goal

- Freeze the data contracts before writing Flutter models.

### TODO

- [ ] Inventory all API DTOs from current TS types.
- [ ] Create Rust-side bridge contract list for:
  - [ ] `VodItem`
  - [ ] `SiteWithStatus`
  - [ ] `RemoteSource`
  - [ ] `RemoteSourcesResponse`
  - [ ] `AddSourcesBatchResult`
  - [ ] `LivePlatformInfo`
  - [ ] `LiveRoomItem`
  - [ ] `LiveRoomDetail`
  - [ ] `LivePlayQuality`
  - [ ] `LivePlayUrl`
  - [ ] `LiveFavoriteItem`
  - [ ] `LiveHistoryItem`
  - [ ] `LiveMessage`
  - [ ] auth DTOs
- [ ] Decide whether Flutter model names stay close to current TS names.
- [ ] Standardize success/error response style:
  - [ ] keep HTTP-style `ApiResponse<T>`
  - [ ] or map into typed Result objects in bridge layer
- [ ] Define a single error taxonomy:
  - [ ] network
  - [ ] parse
  - [ ] unsupported source
  - [ ] playback unavailable
  - [ ] auth required
  - [ ] internal backend error
- [ ] Decide date/time representation:
  - [ ] epoch millis
  - [ ] ISO string

### Deliverables

- [ ] DTO inventory table
- [ ] bridge contract spec
- [ ] error mapping spec

### Exit criteria

- [ ] Flutter models can be generated or written once without churn

## Phase 3. Choose integration mode

### Goal

- Decide how Flutter talks to Rust for the first working version.

### Option 1: local HTTP inside app

- Pros:
  - current backend code can be reused fastest
  - migration risk is lower
  - frontend work starts immediately
- Cons:
  - localhost lifecycle management remains
  - two-layer call model remains inside app

### Option 2: `flutter_rust_bridge`

- Pros:
  - cleaner long-term architecture
  - less transport overhead
  - easier typed bindings
- Cons:
  - requires FFI-friendly API design
  - async/streaming APIs need more up-front shaping

### Recommended execution

- [ ] Build Phase 1 and Phase 2 so both options stay possible.
- [ ] Start Flutter feature work using local HTTP if speed is the priority.
- [ ] Move high-value sync APIs to FRB after UI parity if needed.

### Decision TODO

- [x] Pick initial mode
- [x] Document why
- [ ] Do not mix both modes randomly at feature level

## Phase 4. Bootstrap Flutter app

### Goal

- Create a production-shaped Flutter workspace, not a demo shell.

### TODO

- [ ] Create Flutter app root.
- [ ] Enable target platforms:
  - [ ] `windows`
  - [ ] `android`
  - [ ] `ios`
  - [ ] `macos`
- [ ] Add dependencies:
  - [ ] `video_player`
  - [ ] `flutter_riverpod` or chosen state package
  - [ ] `dio` or `http`
  - [ ] `shared_preferences`
  - [ ] `web_socket_channel`
  - [ ] desktop window package if needed
- [ ] Define folder structure:
  - [ ] `lib/app`
  - [ ] `lib/core`
  - [ ] `lib/core/theme`
  - [ ] `lib/core/network`
  - [ ] `lib/core/errors`
  - [ ] `lib/core/models`
  - [ ] `lib/features/home`
  - [ ] `lib/features/search`
  - [ ] `lib/features/detail`
  - [ ] `lib/features/player`
  - [ ] `lib/features/history`
  - [ ] `lib/features/favorites`
  - [ ] `lib/features/settings`
  - [ ] `lib/features/live`
  - [ ] `lib/features/live_auth`
  - [ ] `lib/rust`
- [ ] Define navigation approach:
  - [ ] `go_router`
  - [ ] Navigator 2 custom
- [ ] Create design tokens:
  - [ ] color system
  - [ ] spacing
  - [ ] typography
  - [ ] radius
  - [ ] motion
  - [ ] dark/light theme
- [ ] Add adaptive layout rules for:
  - [ ] phone
  - [ ] tablet
  - [ ] desktop

### Deliverables

- [ ] Flutter app runs on desktop
- [ ] theme and navigation skeleton exists
- [ ] state management baseline chosen and wired

## Phase 5. Build backend adapter layer in Flutter

### Goal

- Keep Flutter feature code independent from transport details.

### TODO

- [ ] Create adapter interfaces:
  - [ ] `SearchRepository`
  - [ ] `PlayRepository`
  - [ ] `SourcesRepository`
  - [ ] `HistoryRepository`
  - [ ] `FavoritesRepository`
  - [ ] `LiveRepository`
  - [ ] `LiveAuthRepository`
- [ ] Implement adapter backing:
  - [ ] HTTP implementation
  - [ ] optional FRB implementation later
- [ ] Create one backend config source:
  - [ ] base URL for HTTP mode
  - [ ] no scattered hardcoded localhost strings
- [ ] Map backend DTOs to Flutter domain models.
- [ ] Centralize retries, timeout, and error conversion.
- [ ] Add logging interceptor.

### Deliverables

- [ ] Flutter feature layer does not know whether transport is HTTP or FRB

## Phase 6. App shell and navigation

### Goal

- Recreate the global app structure before feature pages.

### TODO

- [ ] Build left sidebar or bottom nav depending on platform width.
- [ ] Define desktop layout:
  - [ ] sidebar
  - [ ] page content
  - [ ] settings panel/dialog
- [ ] Define mobile layout:
  - [ ] bottom nav or rail
  - [ ] push navigation to detail/player/live room
- [ ] Replace Tauri window controls on desktop:
  - [ ] minimize
  - [ ] maximize
  - [ ] close
- [ ] Do not emulate desktop drag-region behavior on mobile.
- [ ] Add startup health check and backend unavailable state.

### Deliverables

- [ ] app shell is usable on desktop and mobile
- [ ] navigation structure is fixed early

## Phase 7. Migrate VOD search flow

### Goal

- Get the main search-to-detail-to-play path running first.

### TODO

- [ ] Implement search page state:
  - [ ] input
  - [ ] loading
  - [ ] empty
  - [ ] error
  - [ ] result list
- [ ] Implement search history:
  - [ ] local persistence
  - [ ] tap to reuse
  - [ ] delete one
  - [ ] clear all
- [ ] Implement result card UI.
- [ ] Support source label and poster fallback.
- [ ] Handle filtered result counts.
- [ ] Support retry path.

### Deliverables

- [ ] user can search and open a detail page

## Phase 8. Migrate detail page

### Goal

- Rebuild detail/episode selection and playback entry.

### TODO

- [ ] Implement detail fetch by `source_key + vod_id`.
- [ ] Parse and display episode lists.
- [ ] Rebuild poster, metadata, summary, and episode sections.
- [ ] Add favorite toggle.
- [ ] Add continue watching behavior.
- [ ] Preserve current episode and progress.
- [ ] Handle content with missing poster/remarks/metadata.

### Deliverables

- [ ] detail page reaches parity with current usable subset

## Phase 9. Build VOD player layer

### Goal

- Make a reusable player system above `video_player`.

### TODO

- [ ] Create `TTTTVPlayerSource` model:
  - [ ] url
  - [ ] format hint
  - [ ] headers
  - [ ] title
  - [ ] episode info
- [ ] Create `TTTTVPlayerController` abstraction:
  - [ ] initialize
  - [ ] play
  - [ ] pause
  - [ ] seek
  - [ ] set volume
  - [ ] dispose
  - [ ] state stream/notifier
- [ ] Build custom controls:
  - [ ] play/pause
  - [ ] progress bar
  - [ ] time text
  - [ ] fullscreen
  - [ ] episode switching
  - [ ] lock controls for fullscreen mode if still needed
- [ ] Add resume-from-history support.
- [ ] Add player error surfaces:
  - [ ] unsupported format
  - [ ] expired URL
  - [ ] network unavailable
- [ ] Add platform behavior rules:
  - [ ] desktop fullscreen
  - [ ] mobile orientation
  - [ ] back button behavior

### Test TODO

- [ ] Verify `mp4` on all target platforms
- [ ] Verify `m3u8` on all target platforms
- [ ] Verify header-sensitive playback cases
- [ ] Verify resume playback persistence

### Deliverables

- [ ] VOD playback path is complete

## Phase 10. Migrate favorites, history, and settings

### Goal

- Restore the secondary but core product workflows.

### TODO

- [ ] Favorites:
  - [ ] list
  - [ ] add
  - [ ] remove
  - [ ] open detail from favorite
- [ ] History:
  - [ ] list
  - [ ] remove item
  - [ ] clear all
  - [ ] resume playback
- [ ] Settings:
  - [ ] theme mode
  - [ ] show R18 toggle
  - [ ] source management
  - [ ] clear cache
  - [ ] clear all data
- [ ] Split storage ownership:
  - [ ] Flutter: theme, local presentation prefs
  - [ ] Rust: business state, site state, histories, favorites, cookies

### Deliverables

- [ ] non-player core flows reach parity

## Phase 11. Rebuild source management

### Goal

- Preserve source operations without keeping Vue admin code.

### TODO

- [ ] Load grouped sources.
- [ ] Toggle source enabled state.
- [ ] Add custom source.
- [ ] Delete custom source.
- [ ] Import remote source list.
- [ ] Batch-add remote sources.
- [ ] Show per-source status, health, R18 tag, group.
- [ ] Define validation rules for custom source form.
- [ ] Add optimistic UI or explicit reload policy.

### Deliverables

- [ ] source management reaches daily-usable parity

## Phase 12. Rebuild live list and live room flow

### Goal

- Restore four-platform live browsing and room playback.

### TODO

- [ ] Platform tabs/list:
  - [ ] Bilibili
  - [ ] Douyu
  - [ ] Huya
  - [ ] Douyin
- [ ] Live home page:
  - [ ] recommend list
  - [ ] search
  - [ ] pagination or load more
- [ ] Live room page:
  - [ ] room detail
  - [ ] online count
  - [ ] streamer info
  - [ ] quality list
  - [ ] play action
- [ ] Live favorites:
  - [ ] add/remove/check
  - [ ] list
  - [ ] clear
- [ ] Live history:
  - [ ] add/list/delete/clear

### Deliverables

- [ ] live browsing and room entry work without danmaku

## Phase 13. Live stream normalization

### Goal

- Make live playback portable across platforms despite source format differences.

### TODO

- [ ] Audit each provider output:
  - [ ] which qualities return `m3u8`
  - [ ] which return `flv`
  - [ ] which require proxy rewriting
- [ ] Define Rust-side output contract for live playback:
  - [ ] `urls`
  - [ ] `headers`
  - [ ] `url_type`
  - [ ] `expires_at`
- [ ] Add normalization rules in Rust:
  - [ ] prefer portable URLs
  - [ ] rewrite through proxy if needed
  - [ ] strip provider differences away from Flutter
- [ ] Add platform capability switch in Flutter:
  - [ ] if `flv` unsupported, reject or request alternate candidate
- [ ] Create platform/source compatibility matrix.

### Compatibility matrix TODO

- [ ] Windows x Bilibili
- [ ] Windows x Douyu
- [ ] Windows x Huya
- [ ] Windows x Douyin
- [ ] Android x Bilibili
- [ ] Android x Douyu
- [ ] Android x Huya
- [ ] Android x Douyin
- [ ] iOS x Bilibili
- [ ] iOS x Douyu
- [ ] iOS x Huya
- [ ] iOS x Douyin
- [ ] macOS x Bilibili
- [ ] macOS x Douyu
- [ ] macOS x Huya
- [ ] macOS x Douyin

### Deliverables

- [ ] live playback strategy is explicit, not ad hoc

## Phase 14. Rebuild danmaku

### Goal

- Keep provider protocol complexity in Rust and only render messages in Flutter.

### TODO

- [ ] Keep current Rust danmaku bridge per platform.
- [ ] Decide transport from Rust to Flutter:
  - [ ] WebSocket stream in HTTP mode
  - [ ] FRB stream in bridge mode
- [ ] Define Flutter danmaku model:
  - [ ] type
  - [ ] user_name
  - [ ] message
  - [ ] color
- [ ] Build `DanmakuController`.
- [ ] Build `danmaku_layer.dart` using:
  - [ ] `CustomPainter`
  - [ ] ticker/animation controller
  - [ ] track allocation
  - [ ] cap on queued bullets
- [ ] Add settings:
  - [ ] opacity
  - [ ] speed
  - [ ] font size
  - [ ] enable/disable
- [ ] Add reconnect behavior.
- [ ] Add performance protections:
  - [ ] queue cap
  - [ ] FPS observation
  - [ ] auto drop under load if needed

### Deliverables

- [ ] danmaku works on live room page

## Phase 15. Rebuild live auth

### Goal

- Preserve Bilibili QR login and stored cookie flow.

### TODO

- [ ] Expose auth status endpoint/bridge.
- [ ] Expose QR create endpoint/bridge.
- [ ] Expose QR polling endpoint/bridge.
- [ ] Render QR in Flutter:
  - [ ] from Rust-returned SVG
  - [ ] or from raw URL
- [ ] Rebuild auth status states:
  - [ ] not logged in
  - [ ] QR waiting
  - [ ] scanned
  - [ ] confirmed
  - [ ] expired
  - [ ] logged in
- [ ] Keep cookie persistence in Rust storage.

### Deliverables

- [ ] Bilibili auth flow works in Flutter

## Phase 16. Packaging and platform integration

### Goal

- Make the app shippable outside development machines.

### Windows

- [ ] Package Flutter app with Rust runtime/library.
- [ ] Ensure config/resource paths resolve in packaged mode.
- [ ] Verify media playback in packaged build, not only debug.

### Android

- [ ] Integrate Rust libs into Android build.
- [ ] Verify TLS/network behavior on real devices.
- [ ] Verify HLS playback on real devices.
- [ ] Verify whether any `flv` path is acceptable in practice.
- [ ] Document unsupported live sources if needed.

### iOS

- [ ] Integrate Rust static libraries.
- [ ] Verify ATS/network configuration.
- [ ] Verify HLS playback on real devices.
- [ ] Assume `flv` is unsupported until proven otherwise.

### macOS

- [ ] Integrate Rust library packaging.
- [ ] Verify entitlements and network access.
- [ ] Verify HLS playback and fullscreen.

### Deliverables

- [ ] packaged builds run on each release target

## Phase 17. Test plan

### Smoke tests

- [ ] app starts
- [ ] backend initializes
- [ ] source list loads
- [ ] search works
- [ ] detail works
- [ ] play parse works
- [ ] favorites/history work
- [ ] live platform list works
- [ ] live recommend works
- [ ] live room detail works

### Player tests

- [ ] `mp4` playback
- [ ] `m3u8` playback
- [ ] playback with custom headers
- [ ] resume from saved progress
- [ ] episode switching
- [ ] fullscreen enter/exit

### Live tests

- [ ] each platform recommend page
- [ ] each platform search
- [ ] each platform room detail
- [ ] quality switching
- [ ] history/favorite update

### Danmaku tests

- [ ] connect
- [ ] reconnect
- [ ] sustained run for 30+ minutes
- [ ] UI setting changes while streaming

### Regression comparison

- [ ] compare Flutter output with current Tauri app for all major flows

## 9. Suggested Sprint Breakdown

### Sprint 1

- [ ] Phase 0 complete
- [ ] Phase 1 mostly complete
- [ ] Phase 2 complete

### Sprint 2

- [ ] Phase 3 decision complete
- [ ] Phase 4 complete
- [ ] Phase 5 complete
- [ ] app shell usable

### Sprint 3

- [ ] Phase 7 complete
- [ ] Phase 8 complete
- [ ] VOD search/detail usable

### Sprint 4

- [ ] Phase 9 complete
- [ ] VOD playback usable
- [ ] Phase 10 partially complete

### Sprint 5

- [ ] Phase 10 complete
- [ ] Phase 11 complete

### Sprint 6

- [ ] Phase 12 complete
- [ ] Phase 13 partially complete

### Sprint 7

- [ ] Phase 13 complete
- [ ] Phase 14 complete
- [ ] Phase 15 complete

### Sprint 8

- [ ] Phase 16 complete
- [ ] Phase 17 complete
- [ ] cutover decision

## 10. Risks

### High risk

- [ ] live playback portability across platforms
- [ ] `flv` support assumptions
- [ ] Rust packaging on iOS/Android
- [ ] danmaku performance under long sessions

### Medium risk

- [ ] config/storage path changes during package mode
- [ ] auth flow edge cases
- [ ] desktop/mobile UI divergence

### Low risk

- [ ] search/detail migration
- [ ] favorites/history migration
- [ ] source management migration

## 11. Done Definition

- [ ] Rust is still the only source of truth for crawler/parse/live logic.
- [ ] Flutter is the only frontend codebase used for supported releases.
- [ ] VOD search-detail-play flow is feature complete.
- [ ] favorites/history/settings/source management reach parity.
- [ ] live room flow is usable on all target release platforms.
- [ ] danmaku works with acceptable performance.
- [ ] `flv` is either normalized by Rust or explicitly platform-gated.
- [ ] duplicate Tauri-only backend path is removed from long-term architecture.
- [ ] release packaging is documented and repeatable.

## 12. Immediate Next Steps

- [x] Confirm whether first migration release target is:
  - Windows only
  - Windows + Android
  - all four platforms
- [x] Confirm initial Rust integration mode:
  - HTTP first
  - FRB first
- [x] Start Phase 1 by extracting `Moovie/src/lib.rs`
- [ ] Start Phase 2 by freezing DTO contracts from current TS types
- [ ] Create Flutter workspace and app shell skeleton

## References

- `video_player`: https://pub.dev/packages/video_player
- Android ExoPlayer supported formats: https://developer.android.com/media/media3/exoplayer/supported-formats
- Apple AVFoundation overview: https://developer-mdn.apple.com/av-foundation/
