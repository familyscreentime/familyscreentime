# Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io),
certificate by [SignPath Foundation](https://signpath.org).

## What is signed

Only the Windows client of Family Screen Time, built by the
[Windows client workflow](.github/workflows/windows.yml) on GitHub-hosted
runners, from this public repository, for a release tag (`windows-v…`):

- `FamilyScreenTime.exe`, the app, built from the source code in
  `apps/family_screen_time` and `packages`;
- `FamilyScreenTime-<version>-windows-setup.exe`, its installer, built with
  Inno Setup from `installer/windows/FamilyScreenTime.iss`.

The installer also carries files this project does not build from its own
source code; they are not signed by this project:

- `flutter_windows.dll`, the Flutter engine (Google, BSD licence);
- the Windows parts of the Flutter plugins the app uses (`bonsoir_windows`,
  `jni`), compiled from their upstream source code;
- the Microsoft Visual C++ runtime (`msvcp140.dll`, `vcruntime140*.dll`),
  signed by Microsoft.

Every signing request is approved by hand, for a version already released.

## Team roles

| Role | Members |
| --- | --- |
| Authors | [Olivier Berten](https://github.com/OLIVIER-GITHUB-LOGIN) (project lead). The code is written by Claude, an AI model made by Anthropic, at his request; its commits say so. |
| Reviewers | [Olivier Berten](https://github.com/OLIVIER-GITHUB-LOGIN): any change from someone else, by pull request, is reviewed by him before it is merged. |
| Approvers | [Olivier Berten](https://github.com/OLIVIER-GITHUB-LOGIN) approves every signing request. |

Every member uses multi-factor authentication on GitHub and on SignPath.

## Privacy

This program will not transfer any information to other networked systems
unless specifically requested by the user or the person installing or
operating it.

The devices of a family exchange data only once the parent links them:
directly on the home network, or through a relay server the family sets
up itself, end-to-end encrypted in both cases. See the
[privacy policy](https://familyscreentime.org/privacy.html). The app
contains no third-party services, analytics or ads.

## What the installer changes

The installer needs administrator rights and says, before installing,
what it changes in Windows:

- it installs the app for every account of the PC, in `Program Files`;
- it starts the monitor at each sign-in, in every account (in an account
  not set up for a child, it stops at once);
- it allows the app through the Windows firewall, so that the family's
  devices find each other on the local network.

Uninstalling (Windows Settings › Apps, administrator rights needed) removes
the app, the sign-in start and the firewall rule.
