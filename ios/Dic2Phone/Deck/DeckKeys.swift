import SwiftUI

/// The deck's two key banks: REC beside TAPES / SHELF / SETUP, and the transport for the tape
/// in the deck.
@MainActor
struct DeckKeys {
    let recorder: Recorder
    let player: Player
    let winder: DeckWinder
    let flagKey: FlagKey
    let palette: Palette
    let keyClick: KeyClick
    let navigate: (Screen) -> Void

    /// REC is held to record, or tapped to lock recording on; while recording, FLAG marks the
    /// moment.
    var deck: [BankKey] {
        let state = recorder.state
        var keys = [
            BankKey(
                id: "rec", label: recLabel, face: .glyph(Glyph.rec), weight: 1.5,
                labelColor: palette.danger, face1: palette.rec1, face2: palette.rec2, glyphColor: .white,
                latched: state.recording, action: .hold(press: recorder.keyDown, release: recorder.keyUp)
            ),
        ]
        if state.recording {
            let count = state.flags > 0 ? " \(state.flags)" : ""
            keys.append(BankKey(
                id: "flag", label: String(localized: "FLAG") + count, face: .glyph(Glyph.flag),
                labelColor: palette.accent, action: .tap(recorder.flag)
            ))
        }
        keys += [
            BankKey(id: "tapes", label: String(localized: "TAPES"), face: .icon(.tapes), action: .tap { navigate(.tapes) }),
            BankKey(id: "shelf", label: String(localized: "SHELF"), face: .icon(.shelf), action: .tap { navigate(.shelf) }),
            BankKey(id: "setup", label: String(localized: "SETUP"), face: .glyph(Glyph.setup), action: .tap { navigate(.setup(.look)) }),
        ]
        return keys
    }

    var transport: [BankKey] {
        let playing = player.deckPlaying
        let onFlag = flagKey.flagHere != nil
        return [
            BankKey(id: "rew", label: String(localized: "REW"), face: .glyph(Glyph.rewind), action: wind(forward: false)),
            BankKey(
                id: "play", label: playing ? String(localized: "PAUSE") : String(localized: "PLAY"),
                face: .glyph(playing ? Glyph.pause : Glyph.play), weight: 1.4,
                glyphColor: playing ? palette.led : nil, latched: playing, action: .tap(player.playPause)
            ),
            BankKey(id: "ff", label: String(localized: "FF"), face: .glyph(Glyph.fastForward), action: wind(forward: true)),
            BankKey(
                id: "flag", label: onFlag ? String(localized: "UNFLAG") : String(localized: "FLAG"), face: .glyph(Glyph.flag),
                labelColor: onFlag ? palette.accent : nil, action: .tap(flagKey.toggle)
            ),
            BankKey(id: "eject", label: String(localized: "EJECT"), face: .glyph(Glyph.eject), action: .tap(player.eject)),
        ]
    }

    private var recLabel: String {
        let state = recorder.state
        if state.recording, state.latched { return String(localized: "\(Glyph.rec) TAP=STOP") }
        if state.recording { return String(localized: "\(Glyph.rec) RELEASE") }
        return String(localized: "\(Glyph.rec) HOLD·TAP=LOCK")
    }

    private func wind(forward: Bool) -> KeyAction {
        .hold(
            press: {
                keyClick()
                winder.press(forward: forward)
            },
            release: winder.release
        )
    }
}
