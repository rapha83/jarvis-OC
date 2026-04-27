import CoreAudio
import Foundation

final class AudioInputDeviceObserver {
    private var isActive = false
    private var devicesListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?

    static func hasUsableDefaultInputDevice() -> Bool {
        guard let uid = defaultInputDeviceUID() else {
            return false
        }
        return aliveInputDeviceUIDs().contains(uid)
    }

    static func defaultInputDeviceSummary() -> String {
        guard let deviceID = defaultInputDeviceID() else {
            return "microfone padrao desconhecido"
        }
        let name = deviceName(for: deviceID) ?? "desconhecido"
        let uid = deviceUID(for: deviceID) ?? "uid desconhecido"
        return "\(name) (\(uid))"
    }

    static func inputDevices() -> [AudioInputDevice] {
        let defaultUID = defaultInputDeviceUID()
        return inputDeviceIDs().compactMap { deviceID in
            guard
                deviceIsAlive(deviceID),
                deviceHasInput(deviceID),
                let uid = deviceUID(for: deviceID)
            else {
                return nil
            }
            let name = deviceName(for: deviceID) ?? uid
            return AudioInputDevice(id: uid, name: name, isDefault: uid == defaultUID)
        }
        .sorted {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func setDefaultInputDevice(uid: String) -> Bool {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let deviceID = inputDeviceID(uid: trimmed) else {
            return false
        }

        var target = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &target
        )
        return status == noErr
    }

    static func defaultInputDeviceUID() -> String? {
        guard let deviceID = defaultInputDeviceID() else {
            return nil
        }
        return deviceUID(for: deviceID)
    }

    static func aliveInputDeviceUIDs() -> Set<String> {
        var uids = Set<String>()
        for deviceID in inputDeviceIDs() where deviceIsAlive(deviceID) && deviceHasInput(deviceID) {
            if let uid = deviceUID(for: deviceID) {
                uids.insert(uid)
            }
        }
        return uids
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        guard !isActive else {
            return
        }
        isActive = true

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let queue = DispatchQueue.main

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devicesListener: AudioObjectPropertyListenerBlock = { _, _ in
            onChange()
        }
        _ = AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, queue, devicesListener)

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultInputListener: AudioObjectPropertyListenerBlock = { _, _ in
            onChange()
        }
        _ = AudioObjectAddPropertyListenerBlock(systemObject, &defaultInputAddress, queue, defaultInputListener)

        self.devicesListener = devicesListener
        self.defaultInputListener = defaultInputListener
    }

    func stop() {
        guard isActive else {
            return
        }
        isActive = false

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        if let devicesListener {
            var devicesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectRemovePropertyListenerBlock(systemObject, &devicesAddress, DispatchQueue.main, devicesListener)
        }

        if let defaultInputListener {
            var defaultInputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectRemovePropertyListenerBlock(systemObject, &defaultInputAddress, DispatchQueue.main, defaultInputListener)
        }

        devicesListener = nil
        defaultInputListener = nil
    }

    private static func defaultInputDeviceID() -> AudioObjectID? {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else {
            return nil
        }
        return deviceID
    }

    private static func inputDeviceID(uid: String) -> AudioObjectID? {
        inputDeviceIDs().first { deviceID in
            deviceIsAlive(deviceID)
                && deviceHasInput(deviceID)
                && deviceUID(for: deviceID) == uid
        }
    }

    private static func inputDeviceIDs() -> [AudioObjectID] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
        guard status == noErr, size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceIDs)
        guard status == noErr else {
            return []
        }
        return deviceIDs
    }

    private static func deviceUID(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else {
            return nil
        }
        return uid.takeUnretainedValue() as String
    }

    private static func deviceName(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let name else {
            return nil
        }
        return name.takeUnretainedValue() as String
    }

    private static func deviceIsAlive(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive)
        return status == noErr && alive != 0
    }

    private static func deviceHasInput(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr, size > 0 else {
            return false
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let bufferList = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList)
        guard status == noErr else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }
}
