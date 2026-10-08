import AudioToolbox
import CoreAudio
import Foundation

/// Volume and mute of the current default output device, with change notifications
/// (including changes made elsewhere, e.g. from Control Center or a different device).
@MainActor
final class AudioController {
    static let shared = AudioController()

    var onChange: (() -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private static let watchedSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]

    private init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.bindDefaultDevice() }
        }
        bindDefaultDevice()
    }

    var canChangeVolume: Bool {
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    var volume: Float {
        get { read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, as: Float32.self) ?? 0 }
        set {
            let clamped = min(max(newValue, 0), 1)
            write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(clamped))
            // Matches the system behaviour: turning the volume up unmutes, all the way down mutes.
            if clamped > 0, isMuted { isMuted = false }
            if clamped == 0, !isMuted { isMuted = true }
        }
    }

    var isMuted: Bool {
        get { (read(kAudioDevicePropertyMute, as: UInt32.self) ?? 0) != 0 }
        set { write(kAudioDevicePropertyMute, UInt32(newValue ? 1 : 0)) }
    }

    // MARK: - CoreAudio plumbing

    private func bindDefaultDevice() {
        if device != kAudioObjectUnknown, let listener = deviceListener {
            for selector in Self.watchedSelectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            }
        }

        device = Self.defaultOutputDevice()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        for selector in Self.watchedSelectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
        deviceListener = listener
        onChange?()
    }

    private func read<T>(_ selector: AudioObjectPropertySelector, as _: T.Type) -> T? where T: Numeric & BitwiseCopyable {
        var address = Self.address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = T.zero
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func write<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: T) {
        var address = Self.address(selector)
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
