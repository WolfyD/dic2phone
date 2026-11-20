# Dic2Phone

A cassette-style dictaphone. Two apps live in this repo:

- `app/` — the Android app (Kotlin, Jetpack Compose). It is the reference implementation.
- `ios/` — the iOS app (Swift, SwiftUI), a port of the Android app.
- `app/src/main/cpp/whisper.cpp` — vendored whisper.cpp, shared by both apps for captions.

The owner directs and tests but does not write Kotlin or Swift. Make the technical calls,
explain them in plain terms, and ask only about product decisions.

## Rules

These come before speed and before feature count. Check every change against them.

### 1. Clean, organized code
- One type per file, named after the type. Folders group by feature (`Recording/`, `Vault/`,
  `Captions/`), not by kind (`Models/`, `Helpers/`).
- No dead code, commented-out code, or unused parameters.
- Small functions that do one thing. If a function needs a section comment, split it.

### 2. Code that explains itself
- Names carry the meaning: `silenceThreshold`, not `t`; `sealTape(_:)`, not `process(_:)`.
- Comments only say *why* something non-obvious is done (a platform quirk, a security
  decision, a magic number's origin). Never restate *what* the code does.
- No banner comments, no file-header essays.

### 3. KISS & SOLID
- The simplest design that works. No protocols, generics or layers "for later".
- Single responsibility: UI renders state, view models hold state, services do I/O.
- Depend on protocols only at real seams (audio input, storage, crypto) where tests need a
  fake. Not everywhere.
- Prefer platform frameworks over third-party dependencies.

### 4. It should make sense
- Data flows one way: services -> view model -> view. Views never touch files or audio.
- No singletons reaching into each other. Dependencies are passed in.
- No global mutable state. Use Swift concurrency (`actor`, `@MainActor`) instead of locks
  and callbacks where possible.

### 5. Safe and secure (OWASP Mobile Top 10, CWE Top 25)
- **Storage (M9, CWE-312/922):** tapes, captions and metadata use
  `FileProtectionType.completeUnlessOpen`: a dictaphone records in a locked phone, so new
  tapes must be creatable while locked, but nothing can be read back until it's unlocked.
  Vault tapes are encrypted with AES-GCM (CryptoKit); the key lives in the Keychain behind
  biometrics or passcode (`.biometryCurrentSet` / `.userPresence`), never in files or
  UserDefaults. The vault is excluded from backups and never has plaintext on disk.
- **Logging (CWE-532):** never log transcripts, file names, locations, keys or user content.
- **Input validation (M4, CWE-20/22):** every file name, path, imported file and metadata
  field is validated. Paths are built from IDs, never from user or file-supplied strings.
- **Memory safety (CWE-787/125/416):** pointer code lives in exactly two types:
  `PCMBuffers` (moving samples in and out of Core Audio buffers) and the whisper.cpp
  bridge. Buffer sizes are checked on every call. Nothing else uses `Unsafe*` APIs.
- **Network (M5, CWE-319/494):** HTTPS only (default App Transport Security, no
  exceptions). Downloaded models are verified against a pinned SHA-256 before use.
- **Secrets (CWE-798):** none in code or the repo. Signing material stays in CI secrets.
- **Errors (CWE-209/755):** no force unwraps (`!`) or `try!` outside tests. Failures
  surface as user-facing messages without internal details.
- **Least privilege (M8):** ask for each permission (mic, location, notifications) only
  when the feature that needs it is first used.
- **Supply chain (M2):** no new dependencies without a reason. GitHub Actions are pinned to
  commit SHAs.
- **Privacy:** no analytics, telemetry or crash reporting. The app works offline. Keep the
  README's privacy section true.
