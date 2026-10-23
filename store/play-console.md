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
| Data safety | No data collected, no data shared. Details below. |
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

- Does your app collect or share any of the required user data types?
  **No.** (Google counts data as collected only when it leaves the device.
  Everything Family Screen Time records stays in its private storage.)
- Is all of the user data collected by your app encrypted in transit? Not
  applicable (nothing is transmitted).
- Do you provide a way for users to request that their data is deleted?
  Not applicable; data is erased by uninstalling the app or clearing its
  data.
- From 0.20 (sync on the local network): the family's devices exchange
  settings and usage directly with each other over the home network,
  end-to-end encrypted, with no server of the publisher. Google counts as
  "collected" what the app sends off the device to the developer or third
  parties, so **No** remains the answer as long as no server of ours is
  involved. To be reviewed when the self-hosted server arrives; if a
  reviewer disagrees, declare "App activity" and "Device or other IDs" as
  collected, encrypted in transit, not shared, required for the app's
  functionality.

### Accessibility API declaration

- Is your app an accessibility tool (isAccessibilityTool)? **No.**
- Description of use, to paste:

> Family Screen Time is a parental control app. Its accessibility service
> detects which app is in the foreground (package and activity names of
> window changes), so that screen time is counted and the limits set by the
> parent are applied; it sends the user to the home screen when an app is
> blocked; and it shows the countdown, warnings, block notices and the
> optional device lock as accessibility overlays, which stay visible over
> full-screen apps. When the parent turns on uninstall protection, the
> service also closes the Android settings pages that would switch the app
> off (device administrator deactivation, the app's own settings pages,
> Android's security page offering to remove its access). For this, screen
> content is read only on Android's security and permission pages. No data
> is stored beyond usage times, and nothing leaves the device. Before the
> service is turned on, an in-app disclosure explains this and asks for
> consent. The source code is public: https://github.com/familyscreentime/familyscreentime

- Video: Google may ask for a short video (a link, e.g. unlisted YouTube).
  Show: first launch, the permissions screen, the disclosure dialog with
  "Accept and turn on", turning the service on in Android settings, then a
  limited app being closed with its notice.

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
