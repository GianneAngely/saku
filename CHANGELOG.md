# Changelog

## 1.2.1

- Settings › To-do shows in the sidebar. Before, it only opened from the To-do tab.
- The Google Tasks setup guide explains Testing and In production, and links Saku's privacy policy.

## 1.2.0

- **To-do tab:** lists, subtasks and due dates (type "Pay rent Friday"), with tasks due today beside the camera. Works on its own as a list on your Mac.
- **Google Tasks sync:** two ways, cached for offline use, with your own Google OAuth client (PKCE sign-in in your browser, token in the Keychain). Setup guide in docs/google-tasks-setup.md.
- System and Trackers show in the tab bar by default.

## 1.1.1

- **New icon:** a soft clay sakura on a purple night sky, rendered in Blender. It also sits in the closed notch and on alert cards.
- **Connecting Google Calendar is one step:** Connect asks for Calendar access once, opens Internet Accounts if needed, notices the Google account as soon as it appears, makes its main calendar the home for new events and reminders, and says "Connected". Settings › Calendar shows the permission, the accounts Saku can read and where new events go.
- Permissions survive updates: builds keep the same signing requirement, so macOS doesn't ask again after every update.
- Open source under the MIT License.

## 1.1.0

- **Google Calendar**: connect it through macOS Internet Accounts (Settings › Calendar). Saku never sees your Google password.
- **New events and reminders** right from the Calendar tab with **+**. Type the time into the title ("Lunch with Rei tomorrow 12:30") and pick the calendar and alert.
- **Reminders as calendar events**: Apple Reminders doesn't sync with Google Tasks, so reminders can go to a calendar you pick as short events with an alert.
- **All features**: the grid button in the notch (or `⌃⌥/`) lists every feature and where it lives, with search in English and Bahasa Indonesia.
- Tab names show when you hover the icons.
- Calmer layouts: the timer ring sits in the middle of the panel, battery health and cycle count get their own tiles, the tray centres its items.

## 1.0.0

- First version: music, tray and AirDrop, clipboard and snippets, Pomodoro, countdown and stopwatch, calendar and reminders, notes, teleprompter with voice follow, trackers, web, translate, AI assistant, mirror, apps and Shortcuts, battery and system monitor, calculator, colour picker, weather, eye breaks, Bahasa Indonesia.
