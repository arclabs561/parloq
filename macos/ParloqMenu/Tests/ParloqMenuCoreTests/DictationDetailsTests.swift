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
          "model": "mlx-community/parakeet-tdt-0.6b-v3",
          "prosody_enabled": false,
          "polish_enabled": true,
          "chime_enabled": false,
          "save_enabled": true,
          "vocab_count": 7,
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
    #expect(details.polishEnabled == true)
    #expect(details.vocabCount == 7)
    #expect(details.lastAudioSeconds == nil)

    details.update(from: try decodeEvent("""
        {
          "version": 1,
          "type": "final",
          "phase": "finalizing",
          "sequence": 3,
          "elapsed_seconds": 4.25,
          "asr_seconds": 0.75
        }
        """))

    #expect(details.model == "mlx-community/parakeet-tdt-0.6b-v3")
    #expect(details.lastAudioSeconds == 4.25)
    #expect(details.lastASRSeconds == 0.75)
    #expect(details.latestRealtimeFactor == 0.75 / 4.25)
}

private func decodeEvent(_ json: String) throws -> DictateEvent {
    try JSONDecoder().decode(DictateEvent.self, from: Data(json.utf8))
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
