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
