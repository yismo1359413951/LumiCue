# Development

Set up Snapzy for local development and run it from source.

## Prerequisites

- macOS 13.0+
- Xcode 15.0+
- Command Line Tools: `xcode-select --install`

## Clone the repository

```bash
git clone https://github.com/duongductrong/Snapzy.git
cd Snapzy
```

## Open in Xcode

```bash
open Snapzy.xcodeproj
```

Build and run with `Cmd+R`.

## Build from the terminal

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug build
```

Output: `~/Library/Developer/Xcode/DerivedData/Snapzy-*/Build/Products/Debug/Snapzy.app`

## Run the local debug app

```bash
./scripts/build_and_run.sh
```

The script builds the Debug app at
`.build/xcode-derived-data/Build/Products/Debug/Snapzy Debug.app`. This local
build uses app name `Snapzy Debug` and bundle ID `com.trongduong.snapzy.debug`
so macOS Privacy permissions stay separate from the published `Snapzy` app.

Reset local Debug permissions with:

```bash
tccutil reset ScreenCapture com.trongduong.snapzy.debug
tccutil reset Microphone com.trongduong.snapzy.debug
tccutil reset Accessibility com.trongduong.snapzy.debug
```

If System Settings still shows the old `Snapzy` label for the debug bundle,
quit System Settings, run the reset commands above, launch `Snapzy Debug` again,
then grant permissions from the fresh prompt/list entry.

## Run tests

Unit tests live in `SnapzyTests/`, a peer folder of `Snapzy/`. Keep XCTest files
there so they belong to the `SnapzyTests` target instead of the app target.

```bash
xcodebuild test -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug
```

The shared `Snapzy` scheme uses `Snapzy.xctestplan`, which includes the
`SnapzyTests` target for command-line runs and Xcode editor gutter test runs.

Tests that require real macOS privacy permissions or hardware devices are kept
out of the default flow. To run the real microphone smoke test locally, grant
Microphone access first, then run:

```bash
SNAPZY_RUN_MICROPHONE_INTEGRATION=1 xcodebuild test -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug -only-testing:SnapzyTests/MicrophoneAudioCapturerTests/testMicrophoneAudioCapturerStartStopRealMicrophoneIntegration
```

## Related docs

- For archive, export, and DMG packaging commands, see [BUILD.md](BUILD.md).
- For release and appcast workflow, see [RELEASES.md](RELEASES.md).
