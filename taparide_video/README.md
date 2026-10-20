# Tap A Ride videos

Motion-designed commercial and pitch film for Tap A Ride, made with [Remotion](https://www.remotion.dev) (React → MP4).
Every app screen is a real screenshot of https://taparide.vercel.app, and Tapi is the app's own 3D mascot rebuilt for video.

| Video | Composition | Size | Length |
|---|---|---|---|
| Commercial (landscape) | `TapARideAd` | 1920×1080 | 44 s |
| Commercial (vertical, for WhatsApp/Instagram/TikTok) | `TapARideAdVertical` | 1080×1920 | 44 s |
| Pitch film | `TapARidePitch` | 1920×1080 | about 2 min 40 s |

## Render

```bash
npm install
npm run music            # writes the original music beds to public/music
npx remotion studio      # preview and scrub in the browser
npx remotion render TapARidePitch out/TapARide-Pitch.mp4 --port=3917
```

On this PC another app uses Remotion's default port, so pass `--port=3917`. To use the installed Chrome instead of
downloading one, add `--browser-executable="C:/Program Files/Google/Chrome/Application/chrome.exe"`.

## Updating the screens

The screenshots in `public/screens` are captured from the live site with Playwright (phone screens at 3×, desktop at 2×).
Re-capture them after app changes so the video matches what people will test, for example once the Gemini key is live
so Tapi's answer comes from the real AI.

## Music and voice

`scripts/music.mjs` synthesises original, royalty-free music beds (no samples), so the videos can be shown and shared
without licensing questions. Swap in licensed music any time by replacing `public/music/*.wav`.
`VOICEOVER.md` has a narration script timed to the pitch film's scenes for a human voice-over.

## Licence note

Remotion is free for individuals and companies of up to three people; larger organisations need a company licence
(see remotion.dev/license).

## Sources

Problem-section facts come from the team's *Abuja Smart Mobility Platform Concept & Strategy* brief and are cited on
screen (Daily Trust, New National Star, The Trumpet, The Sun, Abuja Guide, WithinNigeria). Photos: Wikimedia Commons
contributors (CC BY-SA). Map data © OpenStreetMap contributors.
