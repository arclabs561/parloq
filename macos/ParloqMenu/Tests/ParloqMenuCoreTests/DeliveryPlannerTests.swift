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

@Test func fallbackAppendsOnlyNewFinalizedText() {
    var planner = DeliveryPlanner(strategy: .finalizedAppend)

    #expect(planner.plan(
        text: "hello dr",
        finalizedText: "hello",
        isFinal: false
    ) == .append("hello"))
    #expect(planner.plan(
        text: "hello draft changed",
        finalizedText: "hello",
        isFinal: false
    ) == .none)
    #expect(planner.plan(
        text: "hello world",
        finalizedText: "hello world",
        isFinal: false
    ) == .append(" world"))
}

@Test func fallbackCopiesARevisedOfflineFinal() {
    var planner = DeliveryPlanner(strategy: .finalizedAppend)

    #expect(planner.plan(
        text: "live words",
        finalizedText: "live words",
        isFinal: false
    ) == .append("live words"))
    #expect(planner.plan(
        text: "corrected wording",
        finalizedText: "corrected wording",
        isFinal: true
    ) == .copy("corrected wording"))
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
