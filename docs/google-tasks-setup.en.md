# Connect Google Tasks to Saku

*Bahasa Indonesia: [google-tasks-setup.md](google-tasks-setup.md)*

Saku's **To-do** tab works on its own as a task list on this Mac. To sync it both ways with Google Tasks (and the Tasks app on your phone), Saku needs **your own OAuth client** from Google Cloud. It's free, you make it once, and it takes about 10 minutes.

Why your own? Saku has no server and carries nobody's Google keys. You make the "door" to your Google account, and Saku only uses it on this Mac. Saku asks for **Google Tasks** only: not your email, Drive or anything else.

> Sign in to Google Cloud with the Google account whose tasks you want to sync. If the console looks a little different from this guide, look for **Google Auth Platform** in the menu on the left.

## 1. Create a project

1. Open <https://console.cloud.google.com/projectcreate>.
2. **Project name**: `Saku`. Leave the location as "No organization".
3. Click **Create**, then make sure the `Saku` project is selected at the top of the page.

## 2. Turn on the Google Tasks API

1. Open <https://console.cloud.google.com/apis/library/tasks.googleapis.com>.
2. With the `Saku` project selected, click **Enable**.

## 3. Set up the consent screen

1. Open <https://console.cloud.google.com/auth/overview> and click **Get started**.
2. **App name**: `Saku`. **User support email**: pick your email.
3. **Audience**: choose **External** (personal Gmail accounts are always External).
4. **Contact information**: your email. Tick the agreement, then **Create**.
5. Open <https://console.cloud.google.com/auth/scopes> (Data Access) › **Add or remove scopes**, search for `Google Tasks API`, tick `.../auth/tasks`, then **Update** and **Save**.

## 4. Choose a mode: In production or Testing

Open <https://console.cloud.google.com/auth/audience>.

| | In production (unverified) | Testing |
| --- | --- | --- |
| Needs | Complete **Branding**: your own home page, privacy policy and authorized domain | Your email in **Test users** |
| Who can sign in | Any Google account (up to 100 people) | Only accounts in **Test users** (up to 100) |
| How long a sign-in lasts in Saku | Until you remove it | **7 days**, then you sign in again |

Have a web page of your own? Use **In production**: sign in once and it lasts. No web page? Use **Testing** and sign in again every 7 days.

### In production

Google only allows **Publish app** once Branding has a home page, a privacy policy and their domain. All of them must be your own, because authorized domains are registered per project and you run the app in your project. So don't use the addresses of Saku's website: they belong to the Saku developer's project.

1. Put two pages on a domain you control, for example for free on GitHub Pages: a home page that describes the app, and a privacy policy that explains how Google Tasks data is used. For an example, see [Saku's privacy policy](https://gianneangely.github.io/saku-site/privacy.html).
2. Open <https://console.cloud.google.com/auth/branding>. Under **Authorized domains**, click **Add domain** and enter your domain. Do this first, before the links below.
3. Fill in **Application home page** and **Application privacy policy link** with your two pages. **Application terms of service link** is optional.
4. Leave **App logo** empty, because a logo makes Google require verification. Click **Save**.
5. Back on <https://console.cloud.google.com/auth/audience>, click **Publish app** › **Confirm**.

A banner then says "Your app requires verification". Leave it and don't submit for verification: you don't need it for personal use. It only means two things: a warning screen when you sign in (step 7), and a limit of 100 users.

**Signed in while still in Testing?** That sign-in still runs out on day 7. Sign in once more after publishing (or wait for Saku to ask), and from then on it lasts.

### Testing

1. Under **Test users**, click **Add users**.
2. Enter the email of the Google account whose tasks you want to sync, then **Save**.

A sign-in lasts 7 days. When it runs out, Settings › To-do says **Google asked to sign in again.** Click **Sign in with Google** (step 7). Your tasks are safe: a copy stays on your Mac, and the changes you made meanwhile are sent once you're signed in again.

## 5. Create a Desktop OAuth client

1. Open <https://console.cloud.google.com/auth/clients/create>.
2. **Application type**: **Desktop app**. **Name**: `Saku Mac`.
3. Click **Create**, then **Download JSON** in the dialog (or the download icon in the client list). It's named like `client_secret_123….apps.googleusercontent.com.json`.

This file is a small secret of yours: don't send it to anyone or upload it to GitHub.

## 6. Add it to Saku

Pick one:

- **Easiest:** Saku › Settings › **To-do** › **Import client JSON…**, then choose the file you just downloaded.
- **By hand:** rename the file to `google-oauth.json` and put it in Saku's folder. In Finder, choose **Go › Go to Folder…**, type `~/Library/Application Support/Saku/`, and move the file there.
- **Without the file:** in Settings › To-do, open "Or paste the client ID and secret", paste the **Client ID** and **Client secret** from the client's page, then **Save**.

## 7. Sign in with Google

1. Settings › To-do › **Sign in with Google**. Your browser opens.
2. Choose your Google account.
3. **"Google hasn't verified this app"** appears: click **Advanced** › **Go to Saku (unsafe)**. It shows because the app is your own and Google hasn't reviewed it, and you only see it when you sign in. In Testing the screen is a little different: just click **Continue**.
4. Allow **Create, edit, organize, and delete all your tasks**, then click **Continue**.
5. The browser tab says "Saku is connected to Google Tasks." Close it. In Saku the status turns to **Connected to Google Tasks** and your lists show up in the To-do tab.

## Troubleshooting

- **"Sign-in timed out. Try again."**: the browser didn't come back to Saku within 5 minutes. Click Sign in with Google again.
- **"Error 403: access_denied"**: your app is in Testing and your account isn't in Test users (step 4).
- **"Google asked to sign in again."**: Google's permission ran out or was removed. In Testing this happens every 7 days: publish to In production (step 4), then sign in once more. In production it only happens if the access was removed or Saku wasn't used for 6 months. Click **Sign in with Google** again.
- **Disconnect**: Settings › To-do › **Sign out**. Saku removes its access at Google, and your tasks on Google stay. You can also remove it at <https://myaccount.google.com/connections>.

## What Saku stores

- Sign-in token: in the macOS **Keychain**.
- Client file: `~/Library/Application Support/Saku/google-oauth.json` (never in the app or the repo).
- A copy of your tasks for offline use: `~/Library/Application Support/Saku/todo.json`. Changes made offline are sent when you're back online.

The full privacy policy is at <https://gianneangely.github.io/saku-site/privacy.html>.
