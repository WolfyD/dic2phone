/// A speech model read into memory, and which choice it was read for.
struct LoadedSpeechModel {
    let choice: SpeechModel
    let whisper: WhisperModel
}
