# Migration Status

Last updated: 2026-03-26

## Current target

- First deliverable: Windows
- Business priority: VOD usable end-to-end
- Deferred area: live, danmaku, auth
- Integration mode: Rust localhost HTTP first

## Completed

- `Moovie` was refactored to library-first startup shape.
- `Moovie/src/main.rs` was reduced to a thin runner.
- Windows-first migration scope was frozen.
- VOD HTTP contracts were frozen for Flutter integration.
- Duplicate backend path `moovie-front/src-tauri/src_backend` was marked deprecated in migration docs.
- `ttttv_flutter` workspace skeleton was created.
- VOD HTTP adapter interfaces and repository implementation were created.
- Search/detail/player/history/favorites/source-management page skeletons were created.
- Flutter SDK and Rust toolchain were confirmed available in the local environment.
- `cargo check` passed for `Moovie`.
- `flutter analyze` passed for `ttttv_flutter`.
- `flutter test` passed for `ttttv_flutter`.
- `flutter build windows` produced a Windows runner successfully.
- `Moovie` local HTTP server responded successfully on `/health`.
- Flutter app shell now performs startup backend health checks and shows an unavailable banner when Rust is down.
- Flutter source management now supports scanning a remote repository and batch-importing sources into the Rust backend.
- `Moovie` remote source endpoint returned the default GitHub index successfully.

## In progress

- End-to-end Windows smoke test for search -> detail -> play -> history/favorites
- Closing remaining runtime UX gaps in the Flutter VOD flow

## Blocked by environment

- No current toolchain blockers confirmed

## Next execution steps

1. Run the Windows app against `Moovie` and verify search -> detail -> play -> history/favorites.
2. Fix runtime issues discovered during the first real VOD smoke test.
3. Harden source-management interactions and backend-unavailable states.
4. Update the migration docs after the first end-to-end VOD verification.

## Session log

### 2026-03-26 14:00

- Audited repository structure and confirmed `Moovie` is the only backend to keep.
- Chose `Windows only` plus `HTTP first` for the first migration cut.
- Extracted reusable Rust startup functions into `Moovie/src/lib.rs`.
- Added migration scope and VOD contract documents.

### 2026-03-26 14:10

- Started building Flutter-side workspace skeleton without depending on local toolchains.
- Began moving VOD flow assumptions out of page-level parsing and into repository/controller boundaries.

### 2026-03-26 14:25

- Added `ttttv_flutter/pubspec.yaml`, app shell, theme, backend client, and model layer.
- Wired VOD repositories for search, detail, play parsing, history, favorites, and source management.
- Added Flutter pages for search, detail, player, history, favorites, and sources.
- Left compile verification pending because Flutter and Rust toolchains are still not available in the current shell.

### 2026-03-26 14:35

- Normalized Flutter `lib/` files back to ASCII-safe source text to avoid shell encoding corruption.
- Added `bootstrap_flutter_windows.ps1` so the workspace can be materialized into a Windows Flutter project as soon as the SDK is installed.

### 2026-03-26 19:20

- Confirmed local Flutter and Rust toolchains are installed and usable.
- Verified `cargo check` for `Moovie`.
- Fixed Flutter static validation gaps by replacing deprecated back handling and updating the default widget test.
- Verified `flutter analyze`, `flutter test`, and `flutter build windows`.
- Verified `Moovie` responds on `http://127.0.0.1:5007/health`.
- Added startup backend health feedback to the Flutter shell for Windows-first VOD flows.
- Added Flutter-side remote source scanning and batch import for the VOD migration flow.
- Verified `/api/sources/remote` returns the default remote index successfully.
