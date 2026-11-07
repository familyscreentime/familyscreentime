# Play Console: what to fill in

Steps and answers for publishing Family Screen Time (org.familyscreentime)
on Google Play, starting with internal testing. The Console is in your
language; the answers below are in English where Google reviews them.

## 1. Create the app

Play Console › Create app:

- App name: Family Screen Time
- Default language: French (fr-FR)
- App or game: App
- Free or paid: Free
- Accept the declarations (developer policies, US export laws).

## 2. App content (Policy › App content)

| Section | Answer |
| --- | --- |
| Privacy policy | https://familyscreentime.org/privacy.html (French: /confidentialite.html, Dutch: /privacybeleid.html) |
| App access | Some functionality is restricted. Instructions below. |
| Ads | No, the app has no ads. |
| Content rating | Questionnaire below. |
| Target audience | Decision to take: see below. |
| Data safety | No data collected or shared (exchanges between linked devices are end-to-end encrypted, hence exempt). Details below. |
| Government apps | No. |
| Financial features | None. |
| Health | None. |
| News | No. |
| Sensitive permissions and APIs | Accessibility API: declaration below. Foreground service: declaration below. |

### App access: instructions for reviewers

> Parent mode is protected by a parent code the user creates on first
> launch. To review: open the app, choose a language, create any 6-digit
> parent code (for example 123456), enter a child's first name, then grant
> the permissions listed (accessibility service, usage access, display over
> other apps, notifications). Parent mode: tap the lock icon on the child's
> screen and enter the code. No account or login is needed; the app works
> fully offline.

### Content rating (IARC questionnaire)

- Category: Utility, productivity, communication or other.
- Violence, sexuality, language, controlled substances, gambling: No.
- Users can interact or exchange content: No.
- Shares the user's location: No.
- Digital purchases: No.
- Unrestricted internet access (web browser): No.

### Target audience: a decision for you

The app is set up and controlled by a parent, but a child uses its child
screen on their own device.

- **Option A, recommended: 18 and over.** The app is presented as a tool
  for parents, who install and configure it, as other parental control
  apps do. The review is simpler.
- **Option B: include ages under 13.** The app then falls under Google's
  Families policy. It already meets the main points (no ads, no data
  collection), but a child-directed app using the accessibility service and
  device administration is likely to get closer scrutiny.

The store listing and the privacy policy say plainly that the app is
installed by a parent on a child's device, whichever you choose.

### Data safety

From 0.20, linked devices exchange data with each other, and the form must
account for it. What travels, only between the devices the parent linked,
end-to-end encrypted, with no server of the publisher: over the home
Wi-Fi, and from 0.23 through a relay server the family hosts itself (or
someone it trusts), if the parent sets one up:

- the children's first names;
- rules, app groups, extra time, blocks and time away from the devices;
- time spent in each app (app, start, end, device);
- names and icons of the apps installed on each child's device;
- a random id, a name and a public key per device.

A device linked to no other sends nothing.

Google's help ("Provide information for Google Play's Data safety
section", October 2026) defines collection as transmitting data off the
device, but explicitly exempts end-to-end encryption: "User data that is
sent off device, but that is unreadable by you or anyone other than the
sender and recipient as a result of end-to-end encryption does not need to
be disclosed." The condition: no intermediary, the developer included, can
read the data; only sender and recipient hold the keys. That is the case
here: each session between two devices is encrypted with ephemeral keys
(X25519, ChaCha20-Poly1305) known to them alone. Through the relay server,
each event is encrypted on the device before it leaves
(XChaCha20-Poly1305), with a key only the linked devices hold: the server
stores and passes on ciphertext, and neither it nor its administrator can
read it. The relay is not the developer's: the developer runs no server.

Exports (CSV, ActivityWatch) are files the parent hands to another app of
their choice through Android's share menu: user-initiated, not collection
by the app.

Answers:

- Does your app collect or share any of the required user data types?
  **No.**
- The questions on encryption in transit and deletion no longer show. If
  they do: not applicable.
- Check the preview ("No data collected", "No data shared"), then
  **Submit**.

If a reviewer objects, quote the exemption above. If they hold their view,
declare: collection **Yes**; encrypted in transit **Yes**; deletion
**Yes** (unlink the device, uninstall the app or clear its data); types
**Personal info › Name**, **App activity › App interactions** and
**Installed apps**, **Device or other IDs**; for each collected yes, shared
no, optional, purpose **App functionality**.

The relay server only ever stores end-to-end encrypted events: the
exemption holds.

### Accessibility API declaration

App content › Accessibility API. The `isAccessibilityTool` attribute is
not set, so the app is declared as not an accessibility tool, which is
right. The form (October 2026) asks three things:

- **Use**: tick only **App functionality** (counting the time of the apps
  on screen, closing a blocked app, showing the countdown and the lock,
  uninstall protection). Nothing for analytics, ads, personalisation,
  accounts or developer communications.
- **Sensitive data**: **No**, as in the Data safety section. The service
  sends nothing to the developer or third parties; the app on screen and
  usage times stay on the device, or go to the linked devices and the
  family's relay server, end-to-end encrypted (the exemption in Google's
  help, which the question links to). If a reviewer objects, answer
  **Yes** here and declare the collection in Data safety (see above): the
  in-app disclosure already says what is done with this data.
- **Prominent disclosure**: a link to a video (unlisted on YouTube, under
  3 minutes) showing the disclosure shown before the service is turned on,
  then tick the confirmation.

Video, on a tablet with Android's screen recorder (a fresh install from
the Play Store):

1. Opening the app and setting it up up to the permissions screen.
2. Tapping **Accessibility**: the disclosure opens. Leave it on screen
   long enough to read all of it (scroll if it is longer).
3. Tapping **Accept and turn on**: Android's accessibility page opens;
   turn Family Screen Time on and confirm.
4. Back in the app: accessibility is ticked.
5. Optional but useful: a limited app closing, with its message, and the
   small video window of a blocked app closing.

Showing **Decline** once (the dialog closes, nothing is turned on) helps
the reviewer see the choice is free.

Reference text, if a reviewer asks for a description of use:

> Family Screen Time is a parental control app. Its accessibility service
> detects which app is in the foreground (package and activity names of
> window changes) and which apps have windows on screen (package names of
> the window list: split screen, picture in picture), so that screen time
> is counted and the limits set by the parent are applied; it sends the
> user to the home screen when an app is blocked, and dismisses the
> picture-in-picture window of a blocked app; in browsers, it counts scroll
> events (their number, pace and distance, never the page content) to tell
> reading from quick scrolling through feeds; and it shows the countdown, warnings, block notices and the
> optional device lock as accessibility overlays, which stay visible over
> full-screen apps. When the parent turns on uninstall protection, the
> service also closes the Android settings pages that would switch the app
> off (device administrator deactivation, the app's own settings pages,
> Android's security page offering to remove its access). For this, screen
> content is read only on Android's security and permission pages. No data
> is stored beyond usage times, which stay on the device, or go only to the
> user's other devices the parent linked (over the home Wi-Fi, or through a
> relay server the family hosts itself, always end-to-end encrypted, never
> to the developer or third parties). Before the
> service is turned on, an in-app disclosure explains this and asks for
> consent. The source code is public: https://github.com/familyscreentime/familyscreentime

### Foreground service (special use)

- Type: specialUse. Subtype declared in the manifest: "Parental control:
  enforces the screen-time limits set by the parent."
- Description, to paste:

> The foreground service runs the screen-time monitor: it records how long
> each app is used, evaluates the parent's rules and shows a persistent
> countdown notification. It must run continuously while the device is in
> use, otherwise limits would not be enforced; the user sees it as an
> ongoing notification. No other foreground service type fits this
> parental-control use.

- Video, if asked: the ongoing countdown notification while using a
  limited app.

### Other permissions, if a reviewer asks

- REQUEST_IGNORE_BATTERY_OPTIMIZATIONS: the monitor must keep running in
  the background to enforce limits; battery optimisation stops it. The
  user is asked from the permissions screen and can decline.
- Device administrator: optional, with no policies; it only prevents
  uninstalling the app without the parent. It can be turned off from
  parent mode.
- PACKAGE_USAGE_STATS: usage statistics and fallback detection of the
  foreground app; usage history stays on the device.
- INTERNET, ACCESS_NETWORK_STATE, CHANGE_WIFI_MULTICAST_STATE: optional
  linked devices find each other on the home Wi-Fi (DNS-SD) and exchange
  settings and usage directly, end-to-end encrypted, and with the relay
  server the parent set up, if any (the family's own, never the
  developer's). A device linked to no other uses no network.

## 3. Upload to internal testing

1. Testing › Internal testing › Create new release.
2. Play App Signing: accept "Use Google-generated key". The key in
   `familyscreentime-upload.jks` is then only your upload key.
3. Upload `app-release.aab` (from `flutter build appbundle --release`).
4. Release name: the version (e.g. 0.14.0). Release notes: a line in
   French.
5. Testers: create an email list with the Google accounts allowed to
   install (yours, and the child's account to try). Save, review, roll out.
6. Copy the opt-in link ("Join on the web"). Open it on each device while
   signed in with a tester account, accept, then install from the Play
   Store link it gives.

Each new upload needs a higher version code: it is the number after `+` in
`pubspec.yaml` (`version: 0.14.0+19`), which the build raises with each
version.

## 4. On the child's tablet

- Uninstall any version installed by hand first: Play cannot update an
  app signed with another key.
- To check: whether a supervised account can join the internal test. If it
  can, the child installs from the opt-in link and you approve in Family
  Link as for any app. If it cannot, a closed test with a Google Group of
  testers may be needed; to be seen once the console is open.

## 5. Later: public release

Personal developer accounts created after 13 November 2023 must run a
closed test with at least 12 testers, opted in for 14 days in a row,
before applying for production access.
