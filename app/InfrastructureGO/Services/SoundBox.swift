import AVFoundation
import Foundation

/// The sounds of the game. Each is a short file of the bundle, played over whatever else the phone plays. The game
/// makes sense with the sound off, so every sound has a twin on the screen.
///
/// Everything that touches the phone's audio happens on a queue of its own. Setting up audio can take a moment,
/// and in a simulator it has been seen to take very long, and neither may ever hold up the screen.
nonisolated final class SoundBox: @unchecked Sendable {
    static let names = ["tick", "rattle", "pop", "swish", "tap", "hop", "accept", "refuse", "slip", "crate", "open", "part", "piece", "seal", "page",
                        "hello", "level", "select", "uncover"]
    /// Whether sounds are played. Set and read from the screen's side only.
    var isOn = true
    /// The sound asked for last, so that a debug build can show on screen that a moment asked for its sound.
    private(set) var last = ""
    private let queue = DispatchQueue(label: "edu.princeton.cee420.infrastructurego.sound", qos: .userInitiated)
    private var players: [String: AVAudioPlayer] = [:]

    init(bundle: Bundle = .main) {
        queue.async { [self] in
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            for name in Self.names {
                guard let url = bundle.url(forResource: name, withExtension: "caf"), let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.prepareToPlay()
                players[name] = player
            }
        }
    }

    func play(_ name: String, volume: Float = 1) {
        last = name
        guard isOn else { return }
        queue.async { [self] in
            guard let player = players[name] else { return }
            player.volume = volume
            player.currentTime = 0
            player.play()
        }
    }

    /// The length in seconds of every sound of the list that the bundle holds, read from the files themselves
    /// without touching the phone's audio.
    static func lengths(in bundle: Bundle = .main) -> [String: Double] {
        var found: [String: Double] = [:]
        for name in names {
            guard let url = bundle.url(forResource: name, withExtension: "caf"), let file = try? AVAudioFile(forReading: url) else { continue }
            found[name] = Double(file.length) / file.fileFormat.sampleRate
        }
        return found
    }
}
