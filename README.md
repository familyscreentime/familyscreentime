# Family Screen Time

Screen-time management for Windows 10/11 and Android: self-hostable, and
working without an internet connection too. MIT licence.

## Who writes it

The code, the tests and the documentation are written by Claude, an AI
model made by Anthropic. Olivier Berten leads the project: he sets what
the app should do, reviews the choices, and tests every version on his
family's devices. Commits made by Claude say so in their message.

Website: https://familyscreentime.org · Repository:
https://github.com/familyscreentime/familyscreentime

## Repository contents

| Folder | Role | Status |
| --- | --- | --- |
| `packages/screentime_engine` | Rule engine in pure Dart, shared by every client | Phase 1 complete |
| `apps/family_screen_time` | Flutter app: Android client today, Windows client later | Phase 1 complete, in real-use testing |
| `site` | familyscreentime.org: home page and privacy policy (FR, NL, EN), static files; `build_site.py` regenerates them | Ready to upload |
| `store` | Google Play: store listing, Play Console answers and declarations (English and French console), icon and feature graphic | Ready for internal testing |

Synchronisation (local network, then the PHP/MySQL server) comes next, then
the Windows client, as described in the specification.
