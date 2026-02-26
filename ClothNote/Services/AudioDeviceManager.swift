import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isInput: Bool
    let isBlackHole: Bool
}

class AudioDeviceManager: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var blackHoleDevices: [AudioDevice] = []

    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevices()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func refreshDevices() {
        let devices = getInputDevices()
        DispatchQueue.main.async { [weak self] in
            self?.inputDevices = devices
            self?.blackHoleDevices = devices.filter { $0.isBlackHole }
        }
    }

    private func getInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            guard let name = getDeviceName(deviceID: deviceID) else { return nil }

            return AudioDevice(
                id: deviceID,
                name: name,
                isInput: true,
                isBlackHole: name.lowercased().contains("blackhole")
            )
        }
    }

    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, data)
        guard getStatus == noErr else { return false }

        let bufferList = data.assumingMemoryBound(to: AudioBufferList.self)
        let bufferCount = Int(bufferList.pointee.mNumberBuffers)
        guard bufferCount > 0 else { return false }

        let firstBuffer = bufferList.pointee.mBuffers
        return firstBuffer.mNumberChannels > 0
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        guard status == noErr else { return nil }

        return name as String
    }

    private func startMonitoring() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }
        propertyListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    private func stopMonitoring() {
        guard let block = propertyListenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }
}
