# TTTTV

Windows Flutter client for VOD and live streaming.

## Current Status

- VOD: Flutter / Dart native
- Live: Flutter native
- Local persistence: Flutter side
- Rust backend: no longer required for build, run, or packaging

## Project Structure

```text
TTTTV-Flutter/
├── ttttv_flutter/                  # Flutter desktop client
├── build_windows_flutter_release.ps1
├── build_windows_installer.ps1
└── VOD_DART_MIGRATION_PLAN.md      # Migration completion notes
```

## Run

```powershell
cd TTTTV-Flutter\ttttv_flutter
flutter pub get
flutter run -d windows
```

No local Rust service is required.

## Build Release

```powershell
cd TTTTV-Flutter
.\build_windows_flutter_release.ps1
```

Release output:

```text
TTTTV-Flutter\ttttv_flutter\build\windows\x64\runner\Release
```

## Build Installer

```powershell
cd TTTTV-Flutter
.\build_windows_installer.ps1
```

Installer output:

```text
TTTTV-Flutter\build\installers
```

## Notes

- The repository no longer depends on the legacy Rust backend folder at runtime.
- If you do not need historical reference code, the old Rust backend directory can be removed after this cleanup branch is merged.

## License

MIT
