# TTTTV Flutter Client

This workspace is being prepared before the local Flutter toolchain is fully available.

## Current scope

- Windows first
- VOD first
- Rust backend over `http://127.0.0.1:5007`

## Bootstrap after Flutter is installed

1. `cd ttttv_flutter`
2. `flutter create . --platforms=windows`
3. `flutter pub get`
4. `flutter run -d windows`

## Notes

- The generated Windows runner files are intentionally not committed yet because the local Flutter SDK was not available during this step.
- The `lib/` structure is already prepared for search, detail, player, history, favorites, and source-management migration.
