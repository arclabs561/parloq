import Testing
@testable import ParloqMenuCore

@Test func rangeReplacementUsesEveryCompleteSnapshot() {
    var planner = DeliveryPlanner(strategy: .rangeReplacement)

    #expect(planner.plan(
        text: "hello wor",
        finalizedText: "hello",
        isFinal: false
    ) == .replace("hello wor"))
    #expect(planner.plan(
        text: "hello world",
        finalizedText: "hello world",
        isFinal: true
    ) == .replace("hello world"))
}

@Test func fallbackWaitsForTheCompleteFinalText() {
    var planner = DeliveryPlanner(strategy: .finalOnly)

    #expect(planner.plan(
        text: "hello dr",
        finalizedText: "hello",
        isFinal: false
    ) == .none)
    #expect(planner.plan(
        text: "corrected wording",
        finalizedText: "corrected wording",
        isFinal: true
    ) == .append("corrected wording"))
}

@Test func lostOwnershipCopiesOnlyTheFinal() {
    var planner = DeliveryPlanner(strategy: .rangeReplacement)
    planner.disableReplacement()

    #expect(planner.plan(
        text: "draft",
        finalizedText: "",
        isFinal: false
    ) == .none)
    #expect(planner.plan(
        text: "final",
        finalizedText: "final",
        isFinal: true
    ) == .copy("final"))
}

@Test func userActivityInvalidatesOnlyFinalDelivery() {
    var fallback = DeliveryPlanner(strategy: .finalOnly)
    let invalidatedFallback = fallback.invalidateFinalOnly()
    #expect(invalidatedFallback)
    #expect(fallback.plan(
        text: "draft",
        finalizedText: "",
        isFinal: false
    ) == .none)
    #expect(fallback.plan(
        text: "final",
        finalizedText: "final",
        isFinal: true
    ) == .copy("final"))

    var live = DeliveryPlanner(strategy: .rangeReplacement)
    let invalidatedLive = live.invalidateFinalOnly()
    #expect(!invalidatedLive)
    #expect(live.plan(
        text: "still live",
        finalizedText: "",
        isFinal: false
    ) == .replace("still live"))
}
