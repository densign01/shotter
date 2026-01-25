import AppKit
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Sound")

/// Manages capture sound effects
class SoundManager {
    static let shared = SoundManager()
    
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    /// Play the capture shutter sound
    func playCaptureSound() {
        // Try bundled sound first, fall back to system sound
        if let customSound = loadBundledSound() {
            playSound(customSound)
        } else {
            playSystemSound()
        }
    }
    
    private func loadBundledSound() -> AVAudioPlayer? {
        // Try to load a bundled sound file
        guard let soundURL = Bundle.main.url(forResource: "shutter", withExtension: "aiff")
                ?? Bundle.main.url(forResource: "shutter", withExtension: "wav")
                ?? Bundle.main.url(forResource: "shutter", withExtension: "mp3") else {
            return nil
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.prepareToPlay()
            return player
        } catch {
            logger.warning("Failed to load bundled sound: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func playSound(_ player: AVAudioPlayer) {
        audioPlayer = player
        audioPlayer?.volume = 0.5  // Subtle volume
        audioPlayer?.play()
    }
    
    private func playSystemSound() {
        // Use the system camera shutter sound or a subtle alternative
        // Sound ID 1108 is a subtle "tock" sound
        // For a camera-like sound, we can use the "Grab" sound by path
        
        if let grabSoundURL = URL(string: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif") {
            if FileManager.default.fileExists(atPath: grabSoundURL.path) {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: grabSoundURL)
                    audioPlayer?.volume = 0.5
                    audioPlayer?.play()
                    return
                } catch {
                    logger.debug("Failed to play Grab sound: \(error.localizedDescription)")
                }
            }
        }
        
        // Try alternate system sounds that sound like a camera shutter
        let systemSoundPaths = [
            "/System/Library/Sounds/Tink.aiff",
            "/System/Library/Sounds/Pop.aiff",
            "/System/Library/Sounds/Morse.aiff"
        ]
        
        for path in systemSoundPaths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                    audioPlayer?.volume = 0.3  // Keep system sounds quieter
                    audioPlayer?.play()
                    return
                } catch {
                    continue
                }
            }
        }
        
        // Ultimate fallback: use NSSound
        NSSound.beep()
    }
}
