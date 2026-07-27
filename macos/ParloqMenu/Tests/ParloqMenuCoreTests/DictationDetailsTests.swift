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
}

private func decodeEvent(_ json: String) throws -> DictateEvent {
    try JSONDecoder().decode(DictateEvent.self, from: Data(json.utf8))
}
