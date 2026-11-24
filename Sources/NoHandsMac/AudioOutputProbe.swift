import Foundation
import CoreAudio

/// A hint that something on the Mac is making sound.
public protocol AudioOutputProbing: Sendable {
    /// True when another app is producing audio output right now. Any error answers false.
    func isPlaying() -> Bool
}

/// CoreAudio, no permission needed. On macOS 14.2 and later it asks each audio process whether it is running
/// output, leaving NoHands out: with echo cancellation or a headset such as AirPods, NoHands' own capture keeps
/// the output device running. Before 14.2 it asks whether the default output device runs for anyone.
public struct AudioOutputProbe: AudioOutputProbing {
    private let ownPID: pid_t

    public init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) { self.ownPID = ownPID }

    public func isPlaying() -> Bool {
        if #available(macOS 14.2, *) { return otherProcessRunsOutput() }
        return defaultOutputRunsSomewhere()
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func defaultOutputRunsSomewhere() -> Bool {
        guard let device = Self.uint32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
              device != kAudioObjectUnknown else { return false }
        return Self.uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
    }

    @available(macOS 14.2, *)
    private func otherProcessRunsOutput() -> Bool {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }
        for process in processes {
            guard Self.uint32(process, kAudioProcessPropertyIsRunningOutput) == 1 else { continue }
            if let pid = Self.uint32(process, kAudioProcessPropertyPID), pid_t(pid) == ownPID { continue }
            return true
        }
        return false
    }
}
