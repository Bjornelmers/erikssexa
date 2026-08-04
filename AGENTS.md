# Erikssexa – Agent Instructions

## Project Overview
Flutter web app for a gamified adventure/countdown game. Deployed via **Vercel** with auto-deploy from GitHub.

## Tech Stack
- **Framework**: Flutter (Web)
- **Database**: Firebase Firestore (free tier)
- **Hosting**: Vercel (auto-deploys from `main` branch on GitHub)
- **Repo**: https://github.com/Bjornelmers/erikssexa

## How to Deploy
**DO NOT use `firebase deploy`** — Firebase Hosting is NOT used for this app.
The `firebase.json` file is not configured for hosting.

### Deployment steps:
1. Make code changes
2. Commit and push to GitHub:
   ```bash
   git add <changed files>
   git commit -m "feat: your message"
   git push origin main
   ```
3. Vercel automatically detects the push and redeploys via the `build.sh` script (takes ~2–3 minutes).

### Local Flutter Binary Location
```
/Users/sofiaelmers/development/flutter/bin/flutter
```
(Not on PATH by default — use the full path above to run local builds or tests)

### Local Git config
All commits must be configured locally to be authored by:
- User: `Björn Elmers`
- Email: `bjornelmers@gmail.com`

## Key Files
- `lib/main.dart` — Main application logic, including the state/adventure manager, quest configurations, and main UI.
- `lib/audio_controller.dart` — Audio playback controller.
- `lib/custom_particles.dart` — Custom particle effects.
- `lib/firebase_options.dart` — Firebase initialization options.
- `build.sh` — Custom build script for Vercel.
- `vercel.json` — Vercel routing configuration.

## Language
The app UI is in **Swedish** and **English** (mainly Swedish for user-facing texts, Viking theme, etc.). Keep any newly added user-facing text, dialogs, buttons, and error messages consistent with the medieval/Viking Swedish tone.
