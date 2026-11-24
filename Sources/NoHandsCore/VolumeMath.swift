import Foundation

/// The new output level for a volume phrase.
public enum VolumeMath {
    /// The level to set, 0 to 100; nil for a mute change, which sets no level.
    public static func apply(_ change: VolumeChange, current: Int) -> Int? {
        switch change {
        case .set(let level): min(max(level, 0), 100)
        case .by(let step): min(max(current + step, 0), 100)
        case .mute: nil
        }
    }
}
