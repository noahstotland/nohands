import Foundation
import CoreAudio

/// What the executor needs from the system output volume.
public protocol VolumeControlling: Sendable {
    /// The output level, 0 to 100; nil when the device has no readable volume.
    func level() -> Int?
    func setLevel(_ level: Int) throws
    func setMuted(_ muted: Bool) throws
}

public struct VolumeError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public static let noControl = VolumeError(description: "this speaker has no volume control")
    public static let noMute = VolumeError(description: "this speaker can't be muted")
}

/// CoreAudio on the default output device, no permission needed. A device with a main volume gets it; one with only
/// per-channel volume (some USB and HDMI outputs) gets channels 1 and 2.
public struct CoreAudioVolume: VolumeControlling {
    public init() {}

    private static func address(_ selector: AudioObjectPropertySelector, element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
    }

    private static func defaultOutput() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// The elements (main, else channels 1 and 2) of `selector` that can be set on `device`.
    private static func settableElements(_ selector: AudioObjectPropertySelector, on device: AudioObjectID) -> [UInt32] {
        for elements in [[kAudioObjectPropertyElementMain], [1, 2]] {
            let usable = elements.filter { element in
                var address = address(selector, element: element)
                var settable: DarwinBoolean = false
                return AudioObjectHasProperty(device, &address)
                    && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
            }
            if !usable.isEmpty { return usable }
        }
        return []
    }

    public func level() -> Int? {
        guard let device = Self.defaultOutput() else { return nil }
        let elements = Self.settableElements(kAudioDevicePropertyVolumeScalar, on: device)
        let levels = elements.compactMap { element -> Float32? in
            var address = Self.address(kAudioDevicePropertyVolumeScalar, element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        guard !levels.isEmpty else { return nil }
        return Int((levels.reduce(0, +) / Float32(levels.count) * 100).rounded())
    }

    public func setLevel(_ level: Int) throws {
        try set(kAudioDevicePropertyVolumeScalar, to: Float32(min(max(level, 0), 100)) / 100)
    }

    public func setMuted(_ muted: Bool) throws {
        try set(kAudioDevicePropertyMute, to: UInt32(muted ? 1 : 0), missing: .noMute)
    }

    private func set<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, to value: T,
                                         missing: VolumeError = .noControl) throws {
        guard let device = Self.defaultOutput() else { throw VolumeError.noControl }
        let elements = Self.settableElements(selector, on: device)
        guard !elements.isEmpty else { throw missing }
        for element in elements {
            var address = Self.address(selector, element: element)
            var value = value
            guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr else {
                throw missing
            }
        }
    }
}
