# Saku features

Saku is a free notch app for macOS. This page lists everything it does and exactly where to find it. Lost? Click the **grid button** in the notch (or press `⌃⌥/`) and type what you want: *battery*, *water*, *timer*. It works in English and Bahasa Indonesia.

## Where everything is

The tab bar sits on both sides of the camera. Tabs that don't fit, and every feature inside them, are in **All features** (the grid button). Hover any tab icon to see its name.

| Feature | Where | Notes |
| --- | --- | --- |
| Music: Spotify, Apple Music | Home tab, music card; the closed notch | Cover, seek bar, album colours, bars beside the camera |
| Browser music (YouTube, SoundCloud, Spotify web…) | Settings › Music › Browser music | Chrome or Safari, once "Allow JavaScript from Apple Events" is on |
| Tray | Tray tab, or drop files on the notch | Files, links, text and images; drag them out later |
| AirDrop | Drag a file to the notch's AirDrop zone; Tray tab › AirDrop all | |
| Copy text from an image | Tray tab › right-click an image | On-device, with Vision |
| Clipboard history | Clipboard tab › History | Text, links, images, files, rich text; pins and search |
| Snippets | Clipboard tab › Snippets | Saved text in collections |
| Pomodoro | Timers tab › Pomodoro | Focus, short and long breaks; a ring beside the camera |
| Countdown | Timers tab › Countdown | Presets from 1 minute to 1 hour, or your own |
| Stopwatch | Timers tab › Stopwatch | Laps, best and worst lap |
| Calendar and events | Calendar tab › Events | Month view, today, new events with **+** |
| Reminders | Calendar tab › Reminders | Tick them off, add new ones with **+** |
| Google Calendar | Settings › Calendar › Google Calendar | Through macOS Internet Accounts; see below |
| Join meetings | Calendar tab and Home, **Join** button | Meet, Zoom, Teams, Webex, FaceTime; countdown beside the camera |
| Notes | Notes tab | Several notes, saved as you type |
| Teleprompter | Teleprompter tab | See below |
| Days left | Trackers tab, left card | Trips, exams, birthdays (yearly) |
| Habit counters | Trackers tab, middle card | Goals and a daily reset |
| Water tracker | Trackers tab, right card | Daily goal, cup size, reminders |
| Battery health and cycles | System tab, left card | Level, time left, health, cycle count, temperature, adapter watts |
| Network speed and Wi-Fi | System tab, middle card | Live up and down speed, signal |
| CPU, memory and disk | System tab, right card | |
| Mini browser and bookmarks | Web tab | Your favourite search engine, start page bookmarks |
| Translate | Translate tab | Apple's on-device translation, or DeepL and Google with your own key |
| AI assistant | AI tab | Apple Intelligence on device, or Claude and Gemini with your own key |
| Mirror and ring light | Mirror tab | Camera check before a call |
| App launcher | Apps tab | Pinned apps and search |
| Apple Shortcuts | Apps tab, right card | Run any shortcut |
| Calculator and unit converter | Tools tab, left card | `12% of 80`, `5 km to mi`, `3h20m in min` |
| Colour picker | Tools tab, right card | Pick any pixel, copy HEX or RGB |
| Weather | Home tab, date card | City in Settings › Tools; data from Open-Meteo |
| Eye breaks (20-20-20) | Settings › Tools | A gentle nudge every 20 minutes |
| Focus hooks | Settings › Timers | Run a Shortcut when focus starts or ends (Do Not Disturb, music, lights) |
| Keyboard shortcuts | Settings › Keyboard | Every tab and action can get its own keys |
| Notch look and live activities | Settings › Appearance | Size, glass panel, what shows beside the camera |
| Language | Settings › General | English or Bahasa Indonesia |

## The notch

- Opens on hover after a short, adjustable delay; closes when the pointer leaves. Pin it open with the pin button.
- **Live activities** beside the camera while closed: music, timers, charging, the next meeting, short confirmations ("Added to Tray"). *Auto* picks the most useful one, or pin a style.
- Screens without a notch get an invisible notch at the top centre, shown on hover. It can also be visible or turned off.
- Hides in full screen and while mirroring. Optional haptic tap, glass panel (macOS 26), and a menu bar icon.
- Can hide itself from screen sharing and screenshots.

## Teleprompter

Video calls look better when your eyes stay on the camera. The camera is in the notch, so Saku puts the script right under it.

- Script library with an editor.
- Scrolls under the camera with a reading line at lens height and soft fades.
- Speed in words per minute, text size, width, line spacing, mirror mode.
- 3-2-1 countdown, play, pause, restart, jump back; scroll by hand any time.
- **Voice follow**: on-device speech recognition finds where you are and scrolls with you, pausing when you stop.
- Always hidden from screen sharing, so nobody in the meeting sees the script.

## Google Calendar

Saku never asks for your Google password and has no Google key. macOS does the sign-in and the syncing:

1. Settings › Calendar › **Connect Google Calendar** opens Internet Accounts. Add your Google account there and keep Calendars on.
2. Your Google calendars appear in Saku a moment later. Pick one under *New events go to*.
3. Apple Reminders doesn't sync with Google Tasks, so Saku can save reminders as short events with an alert in a calendar you pick. They ring on your phone through Google Calendar. Ticking one off in Saku puts ✓ in front of its title and removes the alert.

## Ideas left out, and why

| Idea | Why not |
| --- | --- |
| "Now playing" for every app | macOS keeps that API private to Apple's own apps. Browser music covers the main gap |
| Volume and brightness HUD | It would have to intercept system keys with Accessibility; too intrusive for daily use |
| Notification mirroring | Private APIs only |
| Lyrics, Spotify likes | Need Spotify's web API and a login |

## Permissions

Saku never asks at launch. Each prompt appears the first time you use the feature that needs it.

| Permission | Asked when | Why |
| --- | --- | --- |
| Automation: Spotify, Music | You press **Enable controls** on the music card | Song info, artwork, play, pause, skip |
| Automation: Chrome, Safari | Only if browser music is on | Read and control the playing tab |
| Calendars | Calendar tab › Allow access | Events, the meeting countdown, new events, Google Calendar |
| Reminders | Calendar tab › Reminders › Allow access | Reminder lists |
| Camera | Mirror tab › Start mirror | The mirror |
| Microphone, Speech Recognition | Teleprompter › Voice follow | Following your voice, on device |
| Accessibility (optional) | Clipboard › paste into the app you're in | Pressing ⌘V for you |
