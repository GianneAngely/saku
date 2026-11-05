# Saku design

## Name

**Saku** is Indonesian for *pocket*, and 咲く (saku) is Japanese for *to bloom*. The notch blooms open into a pocket of small tools.
Checked on 2026-11-05: no notch or macOS utility called Saku on GitHub, the App Store or the web. ("Poni" was the first idea, but a Windows notch app already uses it.)

## Palette

The notch must stay pure black so it melts into the camera housing. Colour lives in small accents.

| Token | Hex | Use |
| --- | --- | --- |
| notch | `#000000` | panel and closed notch |
| card | `#15121A` | cards inside the panel |
| cardHi | `#221C28` | hover, selected rows, inputs |
| stroke | white 7% | 1 px card edge |
| text | `#F7F2F6` | primary text |
| text2 | `#B8ADB7` | secondary text |
| text3 | `#7C727F` | hints, idle icons |
| blossom | `#FF7EB6` | brand accent, primary buttons, music |
| berry | `#E36A9A` | pressed and gradient partner |
| butter | `#FFD66B` | timers |
| lavender | `#C7A6FF` | AI, translate |
| mint | `#7EE0B5` | battery, success |
| sky | `#8CC8FF` | water, web, network |
| coral | `#FF7A70` | stop, delete, recording |

NotchPing uses the same blossom and berry, so the two feel like one family.

## Type

SF Pro Rounded everywhere inside the notch (matches NotchPing and the system). Numbers use monospaced digits so timers never jitter.
Sizes: 22 heavy for big timers, 14 semibold titles, 12 body, 10.5 captions. Letter spacing is never negative.

## Notch geometry

- Closed: exactly the measured notch (185 x 32 pt on this Mac), black, with 10 pt bottom corners.
- Live activity: the closed notch grows sideways into two wings of equal width so it stays centred. Height never changes.
- Open: 660 x 236 pt by default (adjustable 560 to 820 wide, 200 to 320 tall), bottom corner radius 24, small concave "ears" at the top corners that melt into the bezel.
- The top 32 pt row of the open panel holds the tab icons, split left and right of the camera. Nothing is drawn under the camera itself.
- Content area: 14 pt side padding, cards with 14 pt radius.

## States

1. **Closed** — plain notch.
2. **Live activity** — wings: music (cover + bars), timer (ring + time), charging (bolt + %), next meeting (dot + "in 8m"), date. "Auto" picks by priority: alert, running timer, charging flash, music, meeting in 10 min, then the chosen idle style.
3. **Open** — hover opens after the minimum hover time (default 0.12 s). Leaving closes after the close delay (default 0.25 s), except while typing, dragging or pinned.
4. **Drop** — dragging files near the notch opens two big targets: Tray and AirDrop.
5. **Alert** — timers and reminders open a compact card with Mascot, a title, a hint and one or two buttons.
6. **Prompter** — the panel turns into a tall reading window under the camera.

## Motion

- Open: spring (response 0.42, damping 0.78), content fades in 0.12 s after the shape starts.
- Close: spring (response 0.30, damping 0.95), content fades out first.
- Tab switch: 0.18 s cross-fade.
- Live bars: 24 fps only while music plays and the notch is visible. Idle CPU stays near zero.
- Reduce Motion: no overshoot, fades only.

## Tabs

Home, Tray, Clipboard, Timers, Notes, Prompter, Calendar, Trackers, Web, Translate, AI, Camera, Apps, System, Tools.
Each can be shown, hidden and reordered. Left of the camera: the first half. Right: the rest, then pin and settings.

## Layout sketches (open panel, 660 x 236)

```
Home       [music card: cover 92, title, artist, progress, prev/play/next] [today: date, next events, Join] [battery, weather, water]
Tray       [drop grid of files, horizontal scroll] [AirDrop target]   folders row
Clipboard  [search] [History | Snippets]  [list] [preview + Copy, Paste plain, Pin, Text from image]
Timers     [Pomodoro | Countdown | Stopwatch]  [ring + time] [controls + settings line]
Notes      [note list] [editor]
Prompter   [script list] [preview + speed, size, mirror, voice follow, Start]
Calendar   [month grid] [events or reminders of the chosen day]
Trackers   [days-left cards] [counters] [water glass]
Web        [back, forward, reload, address, star, open in Chrome] [page]
Translate  [from text + language] [swap] [to text + language]
AI         [chat] [input]
Camera     [mirror preview] [start, flip]
Apps       [pinned app grid + search] [shortcuts list]
System     [battery] [network chart + Wi-Fi] [CPU, memory]
Tools      [calculator and converter] [colour picker + recent colours]
```
