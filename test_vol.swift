import Foundation
import CoreAudio

var deviceID = AudioDeviceID(kAudioObjectUnknown)
var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
var addr = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope:    kAudioObjectPropertyScopeGlobal,
    mElement:  kAudioObjectPropertyElementMain)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &propSize, &deviceID)

var vol: Float32 = 0
propSize = UInt32(MemoryLayout<Float32>.size)
addr = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyVolumeScalar,
    mScope:    kAudioDevicePropertyScopeOutput,
    mElement:  0)
var status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &propSize, &vol)
print("VolumeScalar (element 0) status: \(status), vol: \(vol)")

addr.mElement = 1
status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &propSize, &vol)
print("VolumeScalar (element 1) status: \(status), vol: \(vol)")

addr.mElement = 2
status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &propSize, &vol)
print("VolumeScalar (element 2) status: \(status), vol: \(vol)")
