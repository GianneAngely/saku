# Saku feature list

Saku is a notch app for macOS. This file lists every feature it ships with and where each idea came from.

## Sources

- NotchBox listing on the Mac App Store (description, in-app purchase, version history 1.1.47 to 1.1.71).
- Reviews and round-ups of notch apps (BGR, Desktop Insights).
- The settings window of the installed NotchBox 1.1.71 (section names and option names only, used as a checklist).

Without the paid upgrade, NotchBox only keeps the file tray useful. Music control, the timers and most tools need Pro.
Saku has no paywall. Everything below works out of the box, except the few items that need Angel's own login, API key or a macOS permission. Those are marked.

## 1. Pro features (parity checklist)

| Area | Feature | Saku |
| --- | --- | --- |
| Notch | Opens on hover, with a minimum hover time and a close delay | Hover opens, leaving closes. Both timings live in Appearance |
| Notch | Closed-notch styles: waveform, date, pomodoro, countdown, stopwatch | **Live activity** wings beside the notch. "Auto" picks the most useful one. Each style can also be pinned |
| Notch | Notch size fine-tuning, open size, corner radius | Appearance: width, height, corner radius, plus notch offsets for screens where detection is off |
| Notch | Liquid glass effect | Appearance: "Glass" panel style (macOS 26 glass) |
| Notch | Screens without a notch | Fake notch on the main screen, invisible until hover. It can also be hidden on those screens |
| Notch | Hide in full screen, hide while mirroring | Both are options in General |
| Notch | Haptic feedback | Trackpad tap when the notch opens |
| Notch | App logo in the closed notch | Optional idle mark: blossom or Mascot |
| Notch | Choose which tabs show, remember last tab | Tabs settings: show, hide and reorder |
| General | Launch at login, Dock icon, menu bar icon | General settings (login item via ServiceManagement) |
| General | App language | English and Bahasa Indonesia |
| General | Tutorial, restore defaults | First-run tour, "Restore defaults" button |
| Music | Spotify and Apple Music controller | Play, pause, next, previous, scrub. Uses AppleScript (Automation permission) |
| Music | Album art, title, artist, progress | Music card on Home |
| Music | Music live activity in the closed notch | Album art on the left wing, animated bars on the right |
| Music | Dynamic music effect, album cover as background | Bars and glow take the album's colour. Optional blurred cover behind the card |
| Music | Auto-hide when music stops | Option: the live activity tucks away a few seconds after pause |
| Music | Browser music (YouTube, YouTube Music, SoundCloud, Spotify web...) | Chrome and Safari through "Allow JavaScript from Apple Events" (off by default, Angel turns it on) |
| Files | Tray: drop files into the notch, drag them out later | Tray tab. Quick Look, open, show in Finder, copy, remove |
| Files | AirDrop by dropping on the notch | AirDrop drop zone next to the tray drop zone |
| Files | Pinned folders | Tray keeps a row of folders (security-scoped bookmarks not needed, app is not sandboxed) |
| Clipboard | History (text, links, images, files, rich text), search, preview, size limit, clear on quit | Clipboard tab |
| Clipboard | Snippets with collections | Snippets inside the Clipboard tab |
| Tools | Notes with autosave | Notes tab, several notes |
| Tools | Calendar: today, upcoming, month view, choose calendars, hide finished events | Calendar tab (EventKit, Calendar permission) |
| Tools | Reminders: choose lists, check items off | Calendar tab, Reminders side (Reminders permission) |
| Timers | Pomodoro: focus, short break, long break, auto-start, sound, alert | Timers tab + closed-notch ring |
| Timers | Countdown with sound and alert | Timers tab, presets and custom time |
| Timers | Stopwatch | Timers tab with laps |
| Trackers | Days left / days since | Trackers tab |
| Trackers | Counter (habits, workouts) | Trackers tab, with daily reset option |
| Trackers | Water intake: daily target, amount per drink, unit | Trackers tab + optional reminder |
| Tools | Bookmarks | Web tab bookmarks, open in the notch or in Chrome |
| Tools | Web view with a choice of search engine | Web tab (WebKit) |
| Tools | Translate (Google, DeepL or AI) | Apple Translation on-device by default. DeepL and Google keys are optional fields |
| Tools | AI assistant (Gemini key, model, system prompt) | Apple Intelligence on-device by default. Gemini and Claude keys are optional fields |
| System | Battery: level, charging, time to full, low power mode, health | Battery card + charging live activity |
| System | Network speed and Wi-Fi signal charts | System tab |
| System | System monitor | CPU and memory in the System tab |
| System | Camera mirror | Camera tab (Camera permission) |
| Launch | App shortcuts | Apps tab: pinned apps + search |
| Launch | Apple Shortcuts | Apps tab: run any shortcut |
| Keyboard | Global shortcuts: open notch, tray, clipboard, web, translate | Keyboard settings, every tab can get its own shortcut |

## 2. Teleprompter

Video calls and recordings look better when your eyes stay on the camera. The camera sits in the notch, so Saku puts the script right under it.

- Script library with an editor (paste, type, rename, delete).
- Scrolls under the camera with a reading line at lens height and soft fades above and below.
- Speed in words per minute, text size, width, line spacing, mirror (flip) mode.
- 3-2-1 countdown, play, pause, restart, jump back. Scroll by hand with the trackpad at any time.
- **Voice follow**: on-device speech recognition finds where you are in the script and scrolls with you. It pauses when you stop talking. Needs Microphone and Speech Recognition permission.
- Elapsed and remaining reading time.
- Hidden from screen sharing and screenshots, so people in a meeting never see the script.
- Shortcuts: play/pause, faster, slower, restart, from anywhere.

## 3. Extras (brainstorm and decisions)

| Idea | Decision | Why |
| --- | --- | --- |
| Next meeting countdown in the closed notch, one-click Join for Meet, Zoom and Teams links | **In** | Saves hunting for the link every time |
| Charging animation when the cable goes in | **In** | Small, pretty, and the battery data is already there |
| Calculator and unit converter (type `12% of 80`, `5 km to mi`, `3h20m in min`) | **In** | Quick maths without opening an app |
| Colour picker (pick any pixel, copy HEX/RGB, keep recent colours) | **In** | Daily need for UI and game work. NSColorSampler needs no permission |
| Text from image (OCR with Vision) on clipboard and tray images | **In** | Copy text out of screenshots in one click, fully on-device |
| Weather (Open-Meteo, no account) for a city you pick | **In** | Useful glance, no key needed |
| Eye-break reminder (20-20-20) | **In** | Gentle notch nudge, pairs with the water reminder |
| Focus hooks: run a chosen Shortcut when a focus session starts or ends | **In** | Lets Pomodoro turn on Do Not Disturb without extra apps |
| Hide Saku from screen sharing and screenshots | **In** | Privacy for clipboard, notes and the teleprompter |
| Mascot alert card when a timer ends | **In** | Same cute energy as NotchPing |
| Universal "now playing" for every app | Out | macOS 26 keeps this API private to Apple apps. Browser music covers the main gap |
| Volume and brightness HUD replacement | Out | Needs to intercept system keys with Accessibility, too intrusive for daily use |
| Notification mirroring (WhatsApp, iMessage) | Out | Private APIs only |
| Screen recorder | Out | Big, and macOS already has one |
| Lyrics, Spotify likes | Out | Need Spotify's web API and a login |

## 4. Permissions

Saku never asks at launch. Each prompt appears only when you use the feature that needs it.

| Permission | Asked when | Why |
| --- | --- | --- |
| Automation: Spotify, Music | First time Saku reads or controls the player | Track info, artwork, play, pause, skip |
| Automation: Google Chrome, Safari | Only if browser music is turned on | Read and control the playing tab |
| Calendars | Calendar tab, "Allow access" | Events and the next-meeting countdown |
| Reminders | Calendar tab, "Allow access" | Reminder lists |
| Camera | Camera tab, "Start mirror" | Live mirror |
| Microphone, Speech Recognition | Teleprompter, "Voice follow" | Follow your voice on-device |
| Login item | General, "Open at login" | Start with the Mac |
