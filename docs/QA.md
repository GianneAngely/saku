# QA

Everything here runs from the real binary, silently: no sound, no music playback, no permission prompts, no change to system settings. Self tests and renders use a scratch data folder, a separate settings domain and a private pasteboard, then delete them.

- `Saku --selftest`: 422 logic checks (below, per suite). The Intel slice of the universal build passes them too, under Rosetta.
- `Saku --livetest`: 48 checks against the real notch panel on screen for a few seconds, pointer simulated (the real mouse never moves).
- `Saku --render DIR`: 54 states drawn offscreen at 2x, in English and Bahasa Indonesia, reviewed by eye against `docs/DESIGN.md`. HD copies are in `previews/`.
- `Saku --soak SECONDS`: CPU and memory while idle. Release build in /Applications, 2026-11-05: **0.02% CPU idle, 0.02% CPU with the music bars animating, about 28 MB of memory**.

| Feature | Self-test checks | Live run | Picture | Not verifiable here |
| --- | --- | --- | --- | --- |
| Notch shell: hover, close delay, pin, click-through, alerts, HUD, tab bar overflow, tab names on hover | 27 (core) | 26 checks: panel level and position, hover delay, quick passes, leave to close, pin, alert size and auto-dismiss | closed, open, alert | Glass panel look (offscreen pictures can't draw glass) |
| Keyboard shortcuts | 15 | 6 checks: opens on a tab, stays while the pointer is away, toggles closed, takes and returns the keyboard | — | — |
| Music: Spotify, Music, live activity, covers, seek | 24 (demo player, real Spotify and Music payloads) | — | closed bars, home card, paused, cover background | Real Spotify/Music control needs your Automation OK and playback; AppleScript terms checked against both apps' scripting dictionaries |
| Browser music | parsing, scripts | 5 checks: the page script reads Media Session metadata, picks the largest cover, presses Next, skips pages without media (in WebKit) | — | Chrome/Safari need "Allow JavaScript from Apple Events", left untouched |
| Pomodoro, countdown, stopwatch | 37 | — | ring in the notch, three tabs, alert | Chime is never played in QA (file checked) |
| Tray, AirDrop, text from image | 20 + 7 + 4 | — | tray, empty tray, drop targets | A real drag gesture and the AirDrop sheet (sender faked) |
| Clipboard and snippets | 24 (private pasteboard) | — | history, snippets | — |
| Notes | 9 | — | notes | — |
| Teleprompter, voice follow | 32 (layout, speech matching, speed, end, language) | 5 checks: opens, hidden from screen sharing, prompter size, stays open, sharing restored | editor, reading, countdown, mirror | Voice follow with a real microphone (needs your permission) |
| Calendar and reminders | 19 (demo calendar) | — | month view, reminders, Home events, meeting countdown, access prompt | Real events need Calendar permission |
| Google Calendar, new events, reminders as events | 26 (demo Mac with a Google account: spotting Google accounts, the Internet Accounts link, typed times, saving into the picked calendar with its alert, read-only calendars, ✓ and alert on ticking off) | — | new event, Google reminders, connect hint, Calendar settings | A real Google account (signing in is yours to do) |
| All features | 35 (every feature listed and reachable, search in English and Indonesian, jumps to the right tab, mode and card) | 3 checks: the bigger page, landing on the tab with the card lit, closing clears both | All features, search, spotlit card | — |
| Battery, network, CPU, memory | 11 + 11 (real counters) | — | charging flash, System tab | — |
| Days left, counters, water | 24 | — | Trackers tab | — |
| Web and bookmarks | 16 | 3 checks: renders a page, snapshot, taller Web tab | start page | — |
| Translate | 11 (real on-device English to Japanese) | — | Translate tab | English to Indonesian needs a one-time language download (button in Settings) |
| AI assistant | 14 (real on-device Apple Intelligence reply, Claude stream and body, Gemini) | — | AI tab | Claude and Gemini need your keys |
| Mirror | 4 | — | Mirror tab | Camera needs permission |
| Apps and Shortcuts, focus hooks | 12 + 1 (fake `shortcuts` tool) | — | Apps tab | — |
| Calculator, colour picker, weather, eye breaks | 27 + 6 + 6 | — | Tools tab, Home weather | The screen colour loupe (system UI) |
| Bahasa Indonesia | 3 (coverage, no sentence starts with "Yang") | — | key tabs rendered in Indonesian | — |
| Settings, welcome tour | — | — | welcome, appearance, keyboard, music, calendar | — |

## How the pictures are made

`NSView.cacheDisplay` draws the real SwiftUI views offscreen. It ignores a few layer effects, so renders skip the notch clip (content already sits inside the shape at rest), draw pre-blurred covers, and show still music bars. The live app uses the clip, a Core Image blur and Core Animation bars.
