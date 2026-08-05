import AVFoundation

@MainActor
final class ForvoAudioPlayer {
    static let shared = ForvoAudioPlayer()

    private var player: AVPlayer?

    private init() {}

    func play(_ pronunciation: ForvoPronunciation) {
        player?.pause()
        let player = AVPlayer(url: pronunciation.audioURL)
        self.player = player
        player.play()
    }
}
