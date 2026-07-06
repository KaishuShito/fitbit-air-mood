# Fitbit Air Mood
A tiny macOS menu bar app for quick mood and energy check-ins :)

<img width="1578" height="1128" alt="CleanShot 2026-07-05 at 17 59 43@2x" src="https://github.com/user-attachments/assets/532ee491-467e-4532-81c7-8a6ab7ff65d0" />

Fitbit Air Mood records lightweight 1-5 mood and energy snapshots, appends them to a daily Markdown journal, stores structured history in SQLite, and can generate compact weekly insights. It is built with SwiftPM and AppKit.

This project is not affiliated with or endorsed by Fitbit, Google, or Apple.

## Features

- Menu bar status item with the latest same-day check-in.
- Quick Check-In HUD with keyboard-first controls.
- Mood and energy scales, optional notes, and daily Markdown journal append.
- Local SQLite history at `~/Library/Application Support/FitbitAirMoodBar/checkins.sqlite3`.
- Weekly insight generation from recent check-ins.
- Optional hourly reminders and launch-at-login support.
- Optional Fitbit snapshot sync when used beside a `fitbit-air-cli` workspace.

## Requirements

- macOS 14 or newer.
- Xcode command line tools with Swift 6 support.

## Install

Download the latest `FitbitAirMood.zip` from [Releases](https://github.com/KaishuShito/fitbit-air-mood/releases/latest), unzip it, and move the app wherever you like.

On first launch, macOS may ask for an extra confirmation because the app is not notarized yet. Right-click the app and choose Open, or run:

```bash
xattr -d com.apple.quarantine "/path/to/FitbitAirMoodBar.app"
```

## Updates

The app checks for updates automatically with Sparkle. You can also choose `Check for Updates…` from the menu bar menu.

## Build

```bash
swift test
swift build -c release
```

To build a `.app` bundle and launch it:

```bash
bash scripts/build_and_run.sh
```

To install the app into `/Applications` when writable, or `~/Applications` otherwise:

```bash
bash scripts/install_to_applications.sh
```

## Journal Setup

The app needs a journal folder before it can save check-ins. You can choose the folder in the app, or create a local `.env`:

```bash
cp .env.example .env
```

Then edit:

```dotenv
JOURNAL_DIR=/Users/you/Documents/Journal
```

Daily entries are appended to `YYYY-MM-DD.md` files in that folder.

## Optional Fitbit Sync

The app can call an optional sibling CLI named `fitbit-air-cli` and store the returned daily JSON snapshot in SQLite. This is not required for mood check-ins.

If you have a compatible CLI workspace, set:

```bash
export FITBIT_AIR_JOURNAL_PROJECT_DIR=/path/to/fitbit-air-journal
```

That workspace should contain:

```text
dist/fitbit-air-cli
```

The menu item `Sync Fitbit Now` will report an error if the CLI is not configured.

## Data

The app stores only local files:

- Daily Markdown journal files in your chosen journal directory.
- `checkins.sqlite3` in Application Support.
- UserDefaults for UI preferences such as reminders and launch-at-login state.

No server is included, and the app does not upload check-ins.

## License

MIT License. See [LICENSE](LICENSE).
