import Foundation
import ParloqMenuCore
import Testing

@Test func detailsMergeSparseEventsAndKeepLatestFinalTiming() throws {
    var details = DictationDetails()
    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "status",
          "phase": "idle",
          "sequence": 1,
          "device": ":2",
          "device_name": "Studio Display Microphone",
          "device_available": true,
          "available_devices": [
            {"id": ":0", "name": "MacBook Pro Microphone"},
            {"id": ":2", "name": "Studio Display Microphone"}
          ],
          "model": "mlx-community/parakeet-tdt-0.6b-v3",
          "prosody_enabled": true,
          "prosody_baseline_count": 3,
          "polish_enabled": true,
          "chime_enabled": false,
          "save_enabled": true,
          "recordings_path": "/tmp/recordings",
          "vocab_count": 7,
          "vocab_path": "/tmp/example-vocab.txt",
          "stream_interval_seconds": 0.5
        }
        """))
    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "transcript",
          "phase": "recording",
          "sequence": 2,
          "elapsed_seconds": 1.5
        }
        """))

    #expect(details.device == ":2")
    #expect(details.deviceAvailable == true)
    #expect(details.availableDevices == [
        DictationDevice(id: ":0", name: "MacBook Pro Microphone"),
        DictationDevice(id: ":2", name: "Studio Display Microphone"),
    ])
    #expect(details.polishEnabled == true)
    #expect(details.recordingsPath == "/tmp/recordings")
    #expect(details.vocabCount == 7)
    #expect(details.vocabPath == "/tmp/example-vocab.txt")
    #expect(details.vocabWarning == nil)
    #expect(details.lastAudioSeconds == nil)

    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "final",
          "phase": "finalizing",
          "sequence": 3,
          "elapsed_seconds": 4.25,
          "asr_seconds": 0.75,
          "prosody_state": "elevated",
          "prosody_energy_z": 1.25,
          "prosody_baseline_count": 4,
          "prosody_rms_db": -24.5
        }
        """))

    #expect(details.model == "mlx-community/parakeet-tdt-0.6b-v3")
    #expect(details.deviceName == "Studio Display Microphone")
    #expect(details.lastAudioSeconds == 4.25)
    #expect(details.lastASRSeconds == 0.75)
    #expect(details.latestRealtimeFactor == 0.75 / 4.25)
    #expect(details.latestProsodyState == .elevated)
    #expect(details.latestProsodyEnergyZ == 1.25)
    #expect(details.prosodyBaselineCount == 4)
    #expect(details.latestProsodyRMSDB == -24.5)
}

@Test func detailsClearConfigurationWarningOnConfirmedDeviceStatus() throws {
    var details = DictationDetails()
    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "status",
          "phase": "idle",
          "sequence": 1,
          "device": ":7",
          "device_name": "Missing Microphone",
          "device_available": false,
          "configuration_warning": "Saved microphone is not connected"
        }
        """))
    #expect(details.deviceAvailable == false)
    #expect(details.configurationWarning == "Saved microphone is not connected")

    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "ack",
          "phase": "idle",
          "sequence": 2,
          "device": ":0",
          "device_name": "MacBook Pro Microphone",
          "device_available": true
        }
        """))
    #expect(details.deviceAvailable == true)
    #expect(details.configurationWarning == nil)
}

@Test func detailsClearVocabularyWarningAfterSuccessfulReload() throws {
    var details = DictationDetails()
    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "status",
          "phase": "idle",
          "sequence": 1,
          "vocab_count": 3,
          "vocab_path": "/tmp/vocab.txt",
          "vocab_warning": "Using prior corrections"
        }
        """))
    #expect(details.vocabWarning == "Using prior corrections")

    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "status",
          "phase": "recording",
          "sequence": 2,
          "vocab_count": 4,
          "vocab_path": "/tmp/vocab.txt"
        }
        """))
    #expect(details.vocabCount == 4)
    #expect(details.vocabWarning == nil)
}

@Test func configureRequestEncodesTypedMicrophoneSetting() throws {
    let request = DictateRequest(device: DictationDevice(
        id: ":2",
        name: "Studio Display Microphone"
    ))
    let object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any]
    )
    #expect(object["version"] as? Int == 1)
    #expect(object["command"] as? String == "configure")
    let settings = try #require(object["settings"] as? [String: Any])
    let device = try #require(settings["device"] as? [String: String])
    #expect(device == [
        "id": ":2",
        "name": "Studio Display Microphone",
    ])
}

@Test func configureRequestEncodesRecordingRetentionSetting() throws {
    let request = DictateRequest(saveRecordings: true)
    let object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any]
    )
    #expect(object["command"] as? String == "configure")
    let settings = try #require(object["settings"] as? [String: Any])
    #expect(settings["save_recordings"] as? Bool == true)
    #expect(settings["device"] == nil)
}

private func decodeEvent(_ json: String) throws -> DictateEvent {
    try JSONDecoder().decode(DictateEvent.self, from: Data(json.utf8))
}

@Test func protocolPreservesUnknownProsodyStates() throws {
    let event = try decodeEvent("""
        {
          "version": 1,
          "type": "final",
          "phase": "finalizing",
          "sequence": 5,
          "prosody_state": "future_measure"
        }
        """)

    #expect(event.prosodyState == .unknown("future_measure"))
}

@Test func protocolDecodesInputPeakTelemetry() throws {
    let event = try decodeEvent("""
        {
          "version": 1,
          "type": "status",
          "phase": "recording",
          "sequence": 4,
          "elapsed_seconds": 2.0,
          "input_peak_db": -18.5,
          "input_spectrum_db": [-55, -43, -29, -18.5, -24, -38, -52, -65, -74]
        }
        """)

    #expect(event.inputPeakDB == -18.5)
    #expect(event.inputSpectrumDB == [
        -55, -43, -29, -18.5, -24, -38, -52, -65, -74,
    ])
}

@Test func protocolDecodesFinalRawTextWhenProvided() throws {
    let event = try decodeEvent("""
        {
          "version": 1,
          "type": "final",
          "phase": "finalizing",
          "sequence": 6,
          "text": "Parloq is ready.",
          "raw_text": "par lock is ready"
        }
        """)

    #expect(event.text == "Parloq is ready.")
    #expect(event.rawText == "par lock is ready")
}
