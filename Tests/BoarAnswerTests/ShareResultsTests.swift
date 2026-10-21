import BoarCore
import Foundation
import Testing

@testable import BoarAnswer

/// The cases of src/eval/shareResults.test.ts.
struct ShareResultsTests {
    private func row(_ q: String) -> JSONValue {
        .object(["runId": "eval-1", "evalSetVersion": "1", "queryId": .string(q), "configId": "model:qwen", "outcome": "success"])
    }
    private func body(_ s: String) -> JSONValue { JSONValue(jsonString: s)! }
    typealias Result = ShareResults.Result

    @Test func theURLNeedsBothValuesAndIgnoresATrailingSlash() {
        #expect(ShareResults.submitResultsUrl(supabaseUrl: nil, publishableKey: "k") == nil)
        #expect(ShareResults.submitResultsUrl(supabaseUrl: "https://x.supabase.co", publishableKey: "") == nil)
        #expect(ShareResults.submitResultsUrl(supabaseUrl: "https://x.supabase.co/", publishableKey: "k") == "https://x.supabase.co/functions/v1/submit-results")
    }

    @Test func theSubmissionCarriesTheRunTheDeviceAndEveryRowLeavingOutWhatIsUnknown() {
        let s = ShareResults.buildSubmission(
            rows: [row("a"), row("b")], device: ShareResults.Device(platform: "android", osVersion: "15", brand: "POCO", model: "X6", ramBytes: 12_000_000_000), appVersion: "1.0.0"
        )
        // The run keeps the TS key order; rows are written with sorted keys.
        #expect(s.jsonString == #"{"run":{"runId":"eval-1","evalSetVersion":"1","appVersion":"1.0.0","platform":"android","osVersion":"15","deviceBrand":"POCO","deviceModel":"X6","ramBytes":12000000000},"rows":[\#(row("a").jsonString),\#(row("b").jsonString)]}"#)
        #expect(ShareResults.Device().platform == "ios")
        let run = ShareResults.buildSubmission(
            rows: [row("a")], device: ShareResults.Device(apiLevel: 35, soc: "", hardware: "mt6897", ramBytes: 0, cpuCores: 8, cpuFeatures: ["i8mm"], coreMaxFreqKHz: [2_200_000, 3_350_000]), appVersion: "1"
        )
        #expect(run.runValue("soc") == nil)
        #expect(run.runValue("ramBytes") == nil)
        #expect(run.runValue("cpuFeatures")?.jsonString == #"["i8mm"]"#)
        #expect(run.runValue("coreMaxFreqKHz")?.jsonString == "[2200000,3350000]")
        #expect(run.runValue("apiLevel")?.jsonString == "35")
        #expect(ShareResults.buildSubmission(rows: [row("a")], device: ShareResults.Device(cpuFeatures: []), appVersion: "1").runValue("cpuFeatures") == nil)
    }

    @Test func serverAnswersBecomeOutcomes() {
        let table: [(Int, Result)] = [(201, .shared), (409, .alreadyShared), (429, .rateLimited), (400, .rejected), (401, .rejected), (412, .rejected), (500, .serverError), (503, .busy), (0, .failed)]
        for (status, result) in table { #expect(ShareResults.outcome(status: status, body: nil).result == result, "\(status)") }
        let at = "2026-09-29T16:23:54.043438+00:00"
        #expect(ShareResults.outcome(status: 429, body: body(#"{"error":"cooldown","retryAt":"\#(at)"}"#)) == ShareResults.Outcome(result: .cooldown, retryAt: at, status: 429, detail: "cooldown"))
        #expect(ShareResults.outcome(status: 429, body: body(#"{"error":"rate_limited","retryAt":"\#(at)"}"#)).retryAt == at)
        #expect(ShareResults.outcome(status: 429, body: body(#"{"error":"rate_limited","retryAt":"soon"}"#)).retryAt == nil)
        #expect(ShareResults.outcome(status: 429, body: body(#"{"error":"network_limited"}"#)).result == .networkLimited)
        #expect(ShareResults.outcome(status: 201, body: body(#"{"pendingReview":true}"#)).result == .sharedPending)
        #expect(ShareResults.outcome(status: 201, body: body(#"{"pendingReview":false}"#)).result == .shared)
        #expect(ShareResults.outcome(status: 503, body: body(#"{"error":"review_queue_full"}"#)) == ShareResults.Outcome(result: .busy, status: 503, detail: "review_queue_full"))
        let retryable: [Result] = [.offline, .busy, .serverError, .failed]
        #expect(retryable.allSatisfy { $0.canRetry })
        let final: [Result] = [.shared, .rejected, .rateLimited, .keyFailed]
        #expect(!final.contains { $0.canRetry })
        #expect(Result.sharedPending.succeeded && !Result.offline.succeeded)
        #expect(Result.sharedPending.key == "shared-pending")
    }

    @Test func retryAtMustBeAnISOOffsetDateTime() {
        for ok in ["2026-09-29T16:23:54Z", "2026-09-29T16:23+01:00", "2024-02-29T00:00:00.5-03:30"] { #expect(ShareResults.isOffsetDateTime(ok), "\(ok)") }
        for bad in ["2026-09-29T16:23:54", "2026-02-30T00:00:00Z", "2026-09-29 16:23:54Z", "2026-13-01T00:00:00Z", "2026-09-29T24:00:00Z", ""] { #expect(!ShareResults.isOffsetDateTime(bad), "\(bad)") }
    }

    @Test func signingInputAndHardwareDescriptions() {
        #expect(ShareResults.signedMessage(challenge: "abc", payload: #"{"run":{}}"#) == #"abc.{"run":{}}"#)
        #expect(ShareResults.parseCpuFeatures("fp asimd  asimddp i8mm\n") == ["fp", "asimd", "asimddp", "i8mm"])
        #expect(ShareResults.describeChipset(ShareResults.Device(soc: "MT6897", socManufacturer: "Mediatek")) == "Mediatek MT6897")
        #expect(ShareResults.describeChipset(ShareResults.Device(hardware: "qcom")) == "qcom")
        #expect(ShareResults.describeCores([2_200_000, 2_200_000, 2_200_000, 2_200_000, 3_200_000, 3_200_000, 3_200_000, 3_350_000]) == "1 × 3.35 GHz + 3 × 3.2 GHz + 4 × 2.2 GHz")
        #expect(ShareResults.describeCores([0, 0]) == nil)
        // HALF_UP on the double's exact value: 2.345 is stored just above the half, 2.675 just below.
        #expect(ShareResults.describeCores([2_345_000]) == "1 × 2.35 GHz")
        #expect(ShareResults.describeCores([2_675_000]) == "1 × 2.67 GHz")
        #expect(ShareResults.describeCores([3_000_000]) == "1 × 3 GHz")
    }
}
