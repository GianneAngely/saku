# 🌸 Saku

Saku turns the MacBook camera notch into **a little pocket of tools**. Hover over the notch and it blooms open with your music, timers, files, clipboard, notes, calendar, an AI assistant and a teleprompter that scrolls right under the camera. It runs natively on macOS, needs no account, and every feature is free.

![Saku: the open notch with music and today's events, a Pomodoro timer, the teleprompter under the camera, the file tray, clipboard history and the on-device AI assistant](screenshot.png)

## Install

You need macOS 26 and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/GianneAngely/saku.git
cd saku
./build.sh --install
```

This builds **Saku.app** with SwiftPM and puts it in `/Applications`. Open it, follow the short welcome tour, and hover the notch. If another notch app is running, quit it first so the two don't overlap.

## What's inside

- **Live activity** — music covers and bars, timers, charging and your next meeting sit beside the camera while the notch is closed
- **Music** — Spotify, Apple Music and browser tabs (YouTube, SoundCloud and more), with covers, a seek bar and album colours
- **Tray and AirDrop** — drop files, links, text or images on the notch to keep them, drag them out later, or send them with AirDrop
- **Clipboard** — searchable history with images, files and rich text, pins, and snippet collections
- **Timers** — Pomodoro with long breaks and focus hooks, countdowns with presets, a stopwatch with laps
- **Teleprompter** — your script scrolls under the camera at your pace or follows your voice, mirrored if you need it, hidden from screen sharing
- **Calendar** — today's events, a month view, reminders you can tick off, and one-click Join for Meet, Zoom and Teams
- **Notes** — several notes that save as you type
- **Trackers** — days left until a date, habit counters and a water tracker with reminders
- **Web** — a small browser with bookmarks and your favourite search engine
- **Translate** — Apple's on-device translation, or DeepL and Google with your own key
- **AI assistant** — Apple Intelligence on device, or Claude and Gemini with your own key
- **Mirror** — a camera mirror with a ring light
- **Apps and Shortcuts** — launch pinned apps and run your Apple Shortcuts
- **System** — battery health, network speed, Wi-Fi signal, CPU and memory
- **Tools** — a calculator that converts units, a colour picker, text from images, weather and 20-20-20 eye breaks

The whole app also speaks Bahasa Indonesia (Settings > General > Language).

## Shortcuts

| Keys | Action |
| --- | --- |
| `⌃⌥Space` | Open or close Saku |
| `⌃⌥V` | Clipboard, with the cursor in the search field |
| `⌃⌥B` | Tray |
| `⌃⌥A` | AI assistant |
| `⌃⌥L` | Apps |
| `⌃⌥O` | Start or pause the Pomodoro |
| `⌃⌥P` | Teleprompter: start, play or pause |
| `⌃⌥]` `⌃⌥[` `⌃⌥;` | Teleprompter faster, slower, back 5 seconds (while reading) |

Every action can get its own keys in Settings > Keyboard.

## Permissions

Saku asks only when you first use a feature that needs it:

- **Automation (Spotify, Music, Chrome, Safari)** — read the current song and play, pause or skip
- **Calendars and Reminders** — today's events, the meeting countdown and your reminder lists
- **Camera** — the mirror
- **Microphone and Speech Recognition** — the teleprompter's voice follow
- **Accessibility** (optional) — paste a clipboard item straight into the app you are using

## Develop

```bash
swift build
.build/debug/Saku --selftest      # 361 logic checks: silent, no windows, scratch data
.build/debug/Saku --livetest      # a few seconds of the real notch panel with a simulated pointer
.build/debug/Saku --render out/   # every state as a 2x PNG, offscreen
python3 tools/make-previews.py out/
```

`docs/FEATURES.md` lists every feature and where the idea came from, `docs/DESIGN.md` the colours, sizes and motion, and `docs/QA.md` what was tested and how. HD pictures of every state are in `previews/`.

## Built with

Swift · SwiftUI · AppKit · Core Animation · EventKit · Translation · Foundation Models · Vision · Speech

No third-party packages and no Xcode project: it builds with SwiftPM and the Command Line Tools. Weather comes from [Open-Meteo](https://open-meteo.com) and album covers from Spotify's public oEmbed and the iTunes Search API, so nothing needs a login.
