# Dic2Phone

A pocket dictaphone for Android that looks, sounds and feels like an old cassette
recorder (or a MiniDisc). Hold REC to catch a thought, a meeting or a tune, then play it
back with flags, captions and tape effects. Recordings stay on your phone unless you
share them.

- Hold REC to record, tap it to lock recording on, and FLAG moments as you go
- Voice-activated recording that skips the silences
- Tape transport with REW/FF, cue/review, varispeed and flags
- On-device captions and search, powered by [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
- Optional tape effects, a locked vault for private tapes, and a shelf for old ones

## Privacy

Dic2Phone collects nothing: no account, no ads, no analytics, no telemetry, no crash
reports. Nothing about you or your recordings is ever sent to the developer or anyone else.
The app works fully offline. It only goes online in two cases:

- when you download a caption model, it fetches it from Hugging Face
- if you turn on WHERE RECORDED, Android's built-in geocoder (usually a Google service)
  looks up the place name; the place is stored only in the tape on your phone

## Building

Open the project in Android Studio, or run:

```sh
./gradlew assembleDebug
```

Captions are built natively from `app/src/main/cpp/whisper.cpp` for 64-bit ARM phones.

### Release APK

```sh
./gradlew assembleRelease
```

The APK lands in `app/build/outputs/apk/release/`. To sign it with your own key, create
`keystore.properties` in the project root (it's ignored by git):

```properties
storeFile=C:/path/to/your.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Without that file, or with `-PdebugSign`, the release is signed with the debug key so it
can still be installed for testing.

### Key sounds

Official builds use real cassette-deck recordings from Pixabay for the key clicks.
They're used under the [Pixabay Content License](https://pixabay.com/service/license-summary/),
which doesn't allow redistributing them on their own, so **they are not in this
repository** and they are **not** covered by the GPL. A build from source plays simple
synthesized clicks instead.

If you have your own sounds, put them in `app/src/main/assets/sounds/` (ignored by git) as raw
16-bit mono little-endian PCM at 24 kHz, named `key_rec.pcm`, `key_stop.pcm`,
`key_soft1.pcm`, `key_soft2.pcm`, `tape_eject.pcm`, `tape_insert.pcm` and
`tape_wind.pcm` (a seamless loop).

## Made with AI

Dic2Phone was designed, directed and tested by WolfyD, and much of its code was written
with an AI coding assistant (Claude, by Anthropic). Every change was tried on a real
phone, but bugs are possible: issues are welcome.

## License

Copyright © 2026 WolfyD (wolfyden@gmail.com)

Dic2Phone is free software under the [GNU General Public License v3.0 or later](LICENSE).
Third-party parts (whisper.cpp, fonts, libraries) keep their own licenses, and the
Pixabay sounds are not covered by the GPL: see [NOTICE](NOTICE).
