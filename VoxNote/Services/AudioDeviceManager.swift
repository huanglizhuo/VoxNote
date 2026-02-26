import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let sampleRate: Double
    let inputChannels: UInt32
    let outputChannels: UInt32
    
    var isInput: Bool {
        return inputChannels > 0
    }
    
    var isBlackHole: Bool {
        return name.lowercased().contains("blackhole")
    }
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
        let allDevices = getAllAudioDevices()
        let deviceInfos = allDevices.map { getDeviceInfo($0) }
        
        DispatchQueue.main.async { [weak self] in
            let inputs = deviceInfos.filter { $0.isInput }
            self?.inputDevices = inputs
            self?.blackHoleDevices = inputs.filter { $0.isBlackHole }
        }
    }

    private func getAllAudioDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )

        if status != noErr {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)

        let status2 = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &devices
        )

        if status2 != noErr {
            return []
        }

        return devices
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )

        if status == noErr {
            return name as String
        }

        return "Unknown"
    }

    private func getSampleRate(_ deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var sampleRate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &sampleRate
        )

        if status == noErr {
            return sampleRate
        }

        return 0
    }

    private func getChannelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        )

        if status != noErr {
            return 0
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer {
            bufferList.deallocate()
        }

        let status2 = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            bufferList
        )

        if status2 != noErr {
            return 0
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var channelCount: UInt32 = 0

        for buffer in buffers {
            channelCount += buffer.mNumberChannels
        }

        return channelCount
    }

    private func getDeviceInfo(_ deviceID: AudioDeviceID) -> AudioDevice {
        let name = getDeviceName(deviceID)
        let sampleRate = getSampleRate(deviceID)
        let inputChannels = getChannelCount(
            deviceID: deviceID,
            scope: kAudioObjectPropertyScopeInput
        )
        let outputChannels = getChannelCount(
            deviceID: deviceID,
            scope: kAudioObjectPropertyScopeOutput
        )

        return AudioDevice(
            id: deviceID,
            name: name,
            sampleRate: sampleRate,
            inputChannels: inputChannels,
            outputChannels: outputChannels
        )
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
