import AVFoundation
import AppKit

enum SoundEvent: CaseIterable, Sendable {
    case sessionStart
    case taskComplete
    case taskError
    case approvalNeeded
    case taskAcknowledge
    case contextLimit
    case idleReminder
}

/// Timbre family for the synthesized cues (Sound → "Sound pack").
enum SoundPack: String, CaseIterable, Identifiable, Sendable {
    /// Square wave, snappy decay — the classic chiptune character.
    case chip
    /// Triangle wave, longer decay, lower amplitude — rounder and quieter.
    case soft
    /// Narrow pulse wave, shortened notes with a slight pitch-up per note —
    /// brighter, fast-arpeggio cabinet feel.
    case arcade

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chip: "Chip"
        case .soft: "Soft"
        case .arcade: "Arcade"
        }
    }

    static func named(_ raw: String) -> SoundPack {
        SoundPack(rawValue: raw) ?? .chip
    }
}

/// 8-bit style sound cues, synthesized on demand (square/triangle/pulse
/// waves with decay — no bundled audio assets). Matches the reference app's
/// chiptune character; the Soft pack rounds the same melodies off and the
/// Arcade pack brightens them into quick arpeggios.
@MainActor
final class SoundBank {
    static let shared = SoundBank()

    private struct BufferKey: Hashable {
        var event: SoundEvent
        var pack: SoundPack
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [BufferKey: AVAudioPCMBuffer] = [:]
    private var isConfigured = false
    private var isScreenLocked = false

    /// Read-only lock state for quiet-scene gating outside the sound path.
    var isScreenLockedNow: Bool { isScreenLocked }

    private init() {
        observeScreenLock()
    }

    /// Honors master toggle, per-event toggles, quiet scenes, and sound pack.
    func play(_ event: SoundEvent, settings: AppSettings) {
        guard settings.soundEnabled, isEnabled(event, in: settings) else { return }
        if settings.quietWhenScreenLocked, isScreenLocked { return }
        playRaw(event, volume: settings.soundVolume, pack: SoundPack.named(settings.soundPack))
    }

    /// Settings-pane preview.
    func preview(_ event: SoundEvent, volume: Double, pack: SoundPack = .chip) {
        playRaw(event, volume: volume, pack: pack)
    }

    private func isEnabled(_ event: SoundEvent, in settings: AppSettings) -> Bool {
        switch event {
        case .sessionStart: settings.soundSessionStart
        case .taskComplete: settings.soundTaskComplete
        case .taskError: settings.soundTaskError
        case .approvalNeeded: settings.soundApprovalNeeded
        case .taskAcknowledge: settings.soundTaskAcknowledge
        case .contextLimit: settings.soundContextLimit
        case .idleReminder: settings.soundIdleReminder
        }
    }

    private func playRaw(_ event: SoundEvent, volume: Double, pack: SoundPack) {
        configureIfNeeded()
        guard let buffer = buffer(for: event, pack: pack) else { return }
        player.volume = Float(min(max(volume, 0), 1))
        if !engine.isRunning {
            try? engine.start()
        }
        guard engine.isRunning else { return }
        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// Buffers are rendered lazily and cached per (event, pack).
    private func buffer(for event: SoundEvent, pack: SoundPack) -> AVAudioPCMBuffer? {
        let key = BufferKey(event: event, pack: pack)
        if let cached = buffers[key] { return cached }
        let rendered = Self.render(notes: Self.melody(for: event), pack: pack)
        buffers[key] = rendered
        return rendered
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.format)
    }

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isScreenLocked = true }
        }
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isScreenLocked = false }
        }
    }

    // MARK: - Synthesis

    private struct Note {
        var frequency: Double
        var duration: Double
        var amplitude: Double = 0.5
    }

    private static let sampleRate = 44_100.0
    private static var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    private static func melody(for event: SoundEvent) -> [Note] {
        switch event {
        case .sessionStart:
            [Note(frequency: 523.25, duration: 0.07), Note(frequency: 659.25, duration: 0.09)]
        case .taskComplete:
            [
                Note(frequency: 523.25, duration: 0.06),
                Note(frequency: 659.25, duration: 0.06),
                Note(frequency: 783.99, duration: 0.11)
            ]
        case .taskError:
            [
                Note(frequency: 220.00, duration: 0.11, amplitude: 0.55),
                Note(frequency: 174.61, duration: 0.16, amplitude: 0.55)
            ]
        case .approvalNeeded:
            [
                Note(frequency: 783.99, duration: 0.07),
                Note(frequency: 523.25, duration: 0.07),
                Note(frequency: 783.99, duration: 0.07),
                Note(frequency: 523.25, duration: 0.10)
            ]
        case .taskAcknowledge:
            [Note(frequency: 659.25, duration: 0.05)]
        case .contextLimit:
            [
                Note(frequency: 659.25, duration: 0.08),
                Note(frequency: 523.25, duration: 0.08),
                Note(frequency: 440.00, duration: 0.12)
            ]
        case .idleReminder:
            [
                Note(frequency: 587.33, duration: 0.05, amplitude: 0.35),
                Note(frequency: 587.33, duration: 0.05, amplitude: 0.35)
            ]
        }
    }

    /// Renders the melody per pack: Chip is a square wave with a short decay;
    /// Soft is a triangle wave, slightly longer decay, lower amplitude;
    /// Arcade is a bright narrow pulse with shortened notes and a slight
    /// pitch-up per note for a fast-arpeggio feel.
    private static func render(notes: [Note], pack: SoundPack) -> AVAudioPCMBuffer? {
        let gap: Double
        let durationScale: Double
        let amplitudeScale: Double
        let attack: Double
        switch pack {
        case .chip:
            gap = 0.015; durationScale = 1.0; amplitudeScale = 1.0; attack = 0.02
        case .soft:
            gap = 0.015; durationScale = 1.3; amplitudeScale = 0.72; attack = 0.05
        case .arcade:
            gap = 0.008; durationScale = 0.72; amplitudeScale = 0.95; attack = 0.012
        }
        let total = notes.reduce(0.0) { $0 + $1.duration * durationScale + gap }
        let frameCount = AVAudioFrameCount(total * sampleRate) + 1
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }

        var index = 0
        for (noteIndex, note) in notes.enumerated() {
            let noteFrames = Int(note.duration * durationScale * sampleRate)
            // Arcade nudges each successive note up ~half a semitone.
            let frequency = pack == .arcade
                ? note.frequency * pow(1.03, Double(noteIndex))
                : note.frequency
            let period = sampleRate / frequency
            for frame in 0..<noteFrames where index < Int(frameCount) {
                let phase = Double(frame).truncatingRemainder(dividingBy: period) / period
                let wave: Double
                switch pack {
                case .chip:
                    wave = phase < 0.5 ? 1 : -1
                case .soft:
                    // Triangle: -1 → 1 → -1 across the period.
                    wave = phase < 0.5 ? (4 * phase - 1) : (3 - 4 * phase)
                case .arcade:
                    // 25% duty pulse — richer harmonics than a square.
                    wave = phase < 0.25 ? 1 : -1
                }
                // Decay envelope keeps it clean without clicks; Soft rings
                // out on a gentler curve, Arcade snaps off faster.
                let progress = Double(frame) / Double(noteFrames)
                let decay: Double
                switch pack {
                case .chip: decay = 1 - progress
                case .soft: decay = pow(1 - progress, 0.85)
                case .arcade: decay = pow(1 - progress, 1.35)
                }
                let envelope = decay * (progress < attack ? progress / attack : 1)
                samples[index] = Float(wave * note.amplitude * amplitudeScale * envelope)
                index += 1
            }
            let gapFrames = Int(gap * sampleRate)
            for _ in 0..<gapFrames where index < Int(frameCount) {
                samples[index] = 0
                index += 1
            }
        }
        buffer.frameLength = AVAudioFrameCount(index)
        return buffer
    }
}
