# Offloadly

A lightweight macOS app for downloading YouTube videos and playlists. Paste a
link and it starts downloading — no YouTube login, no ads. A native SwiftUI
front-end over [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) + `ffmpeg`.

## Features

- Paste a video **or** playlist URL → download starts immediately
- **Playlists & channels** expand into a **row per video**, each with its own
  progress / pause / retry; large batches ask before downloading everything
- **Drag a link** from your browser onto the window, or use the **menu-bar
  icon** to paste-and-download without switching apps
- **Clipboard auto-grab**: offers to add a YouTube link when you switch to the app
- Video **thumbnails**, live progress (%, speed, ETA), **pause/resume**, and
  a **Dock badge** with the active count; a **notification** when a video finishes
- Settings: download folder, quality (Best / 1080p / 720p / Audio-only MP3),
  simultaneous-download limit, optional SponsorBlock, per-playlist subfolders
- Queue with concurrency limit; cancel / retry / reveal-in-Finder per item
- Friendly error messages (age-restricted, private, region-locked, …)
- Uses your local `yt-dlp` and `ffmpeg`, with clear missing-dependency guidance
  when either tool is not installed
- No YouTube login required; ads are never part of the downloaded stream

## Requirements

- macOS 14+ (Apple Silicon)
- **Full Xcode** (not just Command Line Tools). SwiftUI's `@State` etc. are
  compiler macros whose plugin ships only inside Xcode.app.
- Homebrew packages: `yt-dlp`, `ffmpeg`, and `deno`

This public source distribution does not bundle `yt-dlp` or `ffmpeg`. Install
them locally before running the app:

```sh
brew install yt-dlp ffmpeg deno
```

## Using Terminal

Terminal is the app on your Mac that lets you run typed commands. Open it with
Spotlight: press `Command-Space`, type `Terminal`, then press `Return`.

To run the commands below, first move Terminal into this project folder:

1. Type `cd `, including the space after `cd`.
2. Drag the `Offloadly` folder from Finder into the Terminal window. Terminal
   will paste the folder path for you.
3. Press `Return`.

After that, copy each command exactly as shown, paste it into Terminal, and
press `Return`. If a command asks for your Mac password, type it and press
`Return`; the password will not visibly appear while you type, which is normal.
If a command finishes without printing much, that usually means it worked.

## Build & run

1. Install Xcode from the App Store.
2. Install the command-line tools Offloadly uses:
   ```sh
   brew install yt-dlp ffmpeg deno
   ```
3. Point Terminal at the full Xcode app:
   ```sh
   sudo xcode-select --switch /Applications/Xcode.app
   ```
4. Build the app:
   ```sh
   ./build_app.sh
   ```
5. Launch it:
   ```sh
   open dist/Offloadly.app
   ```

The build script compiles the sources with `swiftc`, assembles
`dist/Offloadly.app`, copies the app icon, and ad-hoc-signs it (needed to run
on Apple Silicon). No Xcode project file is required.

## Uploading to GitHub

This repo is set up to be uploaded as source code. Do not upload generated
build outputs or local dependency binaries.

Safe to upload:

- `Sources/`
- `packaging/`
- `Resources/README.md`
- `Package.swift`
- `README.md`
- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- `build_app.sh`
- `.gitignore`

Do not upload:

- `dist/`
- `.build/`
- `.build-app/`
- `Resources/ffmpeg`
- `Resources/yt-dlp`

Those paths are ignored by `.gitignore`. The app will find Homebrew-installed
copies of `yt-dlp` and `ffmpeg` at runtime.

## Project layout

```
Sources/Offloadly/
  OffloadlyApp.swift        App entry, menu commands, Settings scene
  Models/
    DownloadItem.swift        Per-download observable state + lifecycle
    AppSettings.swift         Persisted preferences (UserDefaults)
  Core/
    BinaryLocator.swift       Finds local, bundled, or system yt-dlp + ffmpeg
    ProgressParser.swift      yt-dlp output line -> structured event
    YTDLPRunner.swift         Spawns/supervises one yt-dlp process
    DownloadManager.swift     Queue, concurrency, event handling
  Views/
    ContentView.swift         Main window (paste bar + list)
    PasteBar.swift            URL input
    DownloadRow.swift         One download's row
    SettingsView.swift        Preferences UI
Resources/README.md           Optional local binary instructions
packaging/AppIcon.icns        macOS app icon
packaging/Info.plist          Bundle metadata
build_app.sh                  Compile + assemble + sign
```

## How requirements are met

- **Playlists vs videos** — any URL carrying a real `list=` (a playlist URL, or
  a watch URL opened from a playlist) downloads the whole playlist; only
  auto-generated radio/"Mix" lists (`RD…`, effectively endless) fall back to the
  single video.
- **No ads** — `yt-dlp` fetches the raw media file; YouTube ads are injected by
  the web player at playback and are never downloaded. In-video sponsor segments
  can optionally be removed via SponsorBlock.
- **No login** — public videos need no auth; cookies are never passed.

## License

Offloadly's own source code is licensed under the MIT License. Third-party
tools used by Offloadly have their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Notes / TODO (later)

- **JavaScript runtime**: recent yt-dlp warns that full YouTube extraction now
  wants a JS runtime (`deno` or `node`); without one "some formats may be
  missing." `brew install deno` fixes it (yt-dlp auto-detects it on PATH).
- Done: source-build dependency lookup, per-video playlist rows,
  channel/large-playlist confirm guard.
