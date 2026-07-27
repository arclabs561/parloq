import ParloqMenuCore
import Testing

@Test func inputLevelClampsDBFSAndMapsItToFiveBars() {
    #expect(InputLevelMeter(dbFS: nil).activeBars == 0)
    #expect(InputLevelMeter(dbFS: -120).activeBars == 0)
    #expect(InputLevelMeter(dbFS: -60).activeBars == 0)
    #expect(InputLevelMeter(dbFS: -48).activeBars == 1)
    #expect(InputLevelMeter(dbFS: -30).activeBars == 3)
    #expect(InputLevelMeter(dbFS: -12).activeBars == 4)
    #expect(InputLevelMeter(dbFS: 0).activeBars == 5)
    #expect(InputLevelMeter(dbFS: 6).activeBars == 5)
}

@Test func inputSpectrumNormalizesAndPadsNineFrequencyBands() {
    let spectrum = InputSpectrum(dbFS: [
        -120, -72, -54, -36, -18, 0, 4, .nan,
    ])

    #expect(spectrum.bandDBFS.count == 9)
    #expect(spectrum.bandDBFS == [
        -120, -72, -54, -36, -18, 0, 0, -120, -120,
    ])
    #expect(spectrum.normalizedBands[0] == 0)
    #expect(spectrum.normalizedBands[1] == 0)
    #expect(spectrum.normalizedBands[5] == 1)
    #expect(spectrum.iconBands.count == 4)
    #expect(spectrum.hasTelemetry)
}

@Test func inputSpectrumTreatsMissingTelemetryAsSilence() {
    let spectrum = InputSpectrum(dbFS: nil)

    #expect(spectrum.bandDBFS == Array(repeating: -120, count: 9))
    #expect(spectrum.isSilent)
    #expect(!spectrum.hasTelemetry)
}

@Test func inputSpectrumKeepsMeasuredSilenceDistinctFromMissingTelemetry() {
    let measuredSilence = InputSpectrum(
        dbFS: Array(repeating: -120, count: 9)
    )

    #expect(measuredSilence.isSilent)
    #expect(measuredSilence.hasTelemetry)
}
