# Contributing to Saku

Thanks for helping! Saku is a small native app, so the bar is simple: it should feel calm, stay fast and never get in the way.

## Before you start

- **Bugs:** open an issue with the bug template. Your macOS version, Mac model and the steps that break it help the most.
- **Ideas:** open a feature request first, so we can talk about it before you spend time on code.
- **Questions:** use Discussions, or an issue if Discussions is off.

## Build it

You need macOS 26 and the Xcode Command Line Tools (`xcode-select --install`). No Xcode project, no third-party packages.

```bash
git clone https://github.com/GianneAngely/saku.git
cd saku
swift build
.build/debug/Saku --selftest      # logic checks: silent, no windows, scratch data
.build/debug/Saku --livetest      # a few seconds of the real notch panel with a simulated pointer
.build/debug/Saku --render out/   # every state as a 2x PNG, offscreen
./build.sh                        # build/Saku.app, signed ad hoc
```

`--selftest` must pass before a pull request. It never plays sound, never touches your real settings and cleans up after itself; please keep new checks that way.

## How the code is laid out

- `Sources/Saku/Notch/`: the notch panel, hover, the tab bar, live activities.
- `Sources/Saku/Features/<Feature>/`: one folder per feature, with its model, views, settings pane and `*Checks.swift` (self tests and render scenes).
- `Sources/Saku/Core/`: theme, settings, storage, the Indonesian strings.
- `docs/`: [features](docs/FEATURES.md), [design](docs/DESIGN.md) and [QA](docs/QA.md).

## Style

- Match the code around you: SwiftUI views, `@Observable` models, small files, comments that say *why*.
- Colours and fonts come from `Theme`. The notch stays pure black; colour lives in small accents.
- Every user-facing string goes through `tr("…")`. Add its Bahasa Indonesia line to `tools/id_strings.py` and run `python3 tools/make-indonesian.py` (it lists anything missing).
- Ask for a permission only when the user first uses the feature that needs it, never at launch.
- No analytics, no accounts, no network calls a user didn't ask for.

## Pull requests

- One change per pull request, with a short description and a screenshot or `--render` picture for anything visual.
- Commit messages in sentence case and the imperative: "Add water reminder snooze".
