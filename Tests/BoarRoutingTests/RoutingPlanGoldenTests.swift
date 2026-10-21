import Foundation
import Testing
@testable import BoarRouting

/// Adaptive-routing planning (profiles, router, default model, compatibility, adaptiveChat's planning half) must match
/// the TypeScript engine on every golden case (scripts/export-native-golden-routing-plan.mjs). Outputs are compared as
/// plain trees (maps, lists, strings, booleans, doubles), every number exactly.
@Suite struct RoutingPlanGoldenTests {
    let g: Tree
    init() throws { g = try Golden.load("routing-plan.json") }

    // The catalog the script used (android-native app/src/main/assets/boar-data/catalog.json, order kept). Corpus
    // assets are not LLMs and never take part in routing, so they are left out.
    static let catalog: [RoutableModel] = [
        RoutableModel(id: "phi-3.5-mini-instruct-q4km", sizeBytes: 2_393_232_672, roles: ["general", "reasoning"]),
        RoutableModel(id: "bge-small-en-v1.5-q8", isLanguageModel: false, sizeBytes: 36_806_944, roles: ["embedding"]),
        RoutableModel(id: "qwen3-4b-instruct-2507-q4km", sizeBytes: 2_497_281_120, roles: ["general", "fast"]),
        RoutableModel(id: "qwen2.5-1.5b-instruct-q4km", sizeBytes: 986_048_768, roles: ["fast"]),
        RoutableModel(id: "qwen2.5-7b-instruct-q4km", sizeBytes: 4_683_074_240, roles: ["reasoning", "verifier"]),
        RoutableModel(id: "lfm2.5-8b-a1b-q4km", sizeBytes: 5_155_564_768),
        RoutableModel(id: "gemma-4-e4b-it-q4_0", sizeBytes: 5_154_941_280),
        RoutableModel(id: "corpus-standard", isLanguageModel: false, sizeBytes: 614_084),
        RoutableModel(id: "corpus-full", isLanguageModel: false, sizeBytes: 2_530_725),
        RoutableModel(id: "wiki-vital5", isLanguageModel: false, sizeBytes: 163_647_488),
    ]

    private func check(_ name: String, _ each: (Tree) -> (String, Any, Any, Bool)) {
        var bad = Mismatches()
        let cs = g[name].array
        #expect(!cs.isEmpty, "\(name) has cases")
        for c in cs {
            let (input, want, got, equal) = each(c)
            if !equal { bad.add(input: input, want: want, got: got) }
        }
        #expect(bad.count == 0, Comment(rawValue: bad.report(name, limit: 10)))
    }

    // MARK: trees

    private func profileTree(_ p: Profiles.ModelProfile) -> Tree {
        .object([
            "modelId": .string(p.modelId), "role": .string(p.role.value), "enabled": .bool(p.enabled), "userOverride": .bool(p.userOverride),
            "estimatedMemoryMb": p.estimatedMemoryMb.map(Tree.number) ?? .null,
            "estimatedTokensPerSecond": p.estimatedTokensPerSecond.map(Tree.number) ?? .null,
            "compatibilityStatus": .string(p.compatibilityStatus.value),
        ])
    }

    private func planTree(_ p: Router.RoutingPlan) -> Tree {
        .object([
            "steps": .array(p.steps.map {
                .object([
                    "id": .string($0.id), "type": .string($0.type.value), "modelId": $0.modelId.map(Tree.string) ?? .null,
                    "required": .bool($0.required), "maxTokens": $0.maxTokens.map { .number(Double($0)) } ?? .null,
                    "timeoutMs": $0.timeoutMs.map { .number(Double($0)) } ?? .null,
                ])
            }),
            "selectedModelIds": .array(p.selectedModelIds.map(Tree.string)),
            "estimatedCost": .object(["modelSwitches": .number(Double(p.estimatedCost.modelSwitches))]),
            "fallbackPolicy": .string(p.fallbackPolicy.value),
            "reasonCodes": .array(p.reasonCodes.map(Tree.string)),
        ])
    }

    // MARK: adaptive

    private var extraModels: [String: RoutableModel] {
        var m: [String: RoutableModel] = [:]
        for o in g["extraModels"].array {
            let id = o["id"].string!
            let cap = o["capabilities"]
            m[id] = RoutableModel(
                id: id, sizeBytes: o["sizeBytes"].int64!, roles: cap["roles"].array.map { $0.string! },
                estimatedMemoryMb: cap["estimatedMemoryMb"].double, estimatedTokensPerSecond: cap["estimatedTokensPerSecond"].double
            )
        }
        return m
    }

    private func overrides(_ o: Tree) -> [ModelRole: String] {
        guard case .object(let d) = o else { return [:] }
        return Dictionary(uniqueKeysWithValues: d.map { (ModelRole.of($0.key)!, $0.value.string!) })
    }

    /// ModelManager.statusAll as the script built it: the whole catalog, then the set's extra models.
    private func statuses(_ set: String, reversed: Bool, extras: [String: RoutableModel]) -> [Profiles.AvailableModel] {
        let s = g["modelSets"][set]
        let present = Set(s["present"].array.map { $0.string! })
        let models = Self.catalog + s["extras"].array.map { extras[$0.string!]! }
        let list = models.map { Profiles.AvailableModel($0, present: present.contains($0.id)) }
        return reversed ? list.reversed() : list
    }

    @Test func adaptiveChatPlanning() {
        let allOverrides = g["overrides"].array.map(overrides)
        let extras = extraModels
        let catalogIds = Set(Self.catalog.map(\.id))
        check("adaptive") { c in
            let set = c["set"].string!
            let reversed = c["reversed"].bool
            let preset = RoutingPreset.of(c["preset"].string!)!
            let ov = allOverrides[c["overrides"].int]
            let active = c["activeId"].string
            let ram = c["ram"].int64 ?? 0
            let maxTokens = c["maxTokens"].int
            let query = c["query"].string!
            let r = AdaptivePlan.plan(
                query: query, statuses: statuses(set, reversed: reversed, extras: extras), preset: preset, overrides: ov,
                activeModelId: active, deviceRamBytes: ram, maxTokens: maxTokens
            )
            let want = Tree.object([
                "taskType": c["taskType"], "profiles": c["profiles"], "plan": c["plan"], "modelUsed": c["modelUsed"],
            ])
            // modelUsed: the generate step's model looked up in the catalog (the extras are not in it).
            let used = r.generateModelId.flatMap { catalogIds.contains($0) ? $0 : nil }
            let got = Tree.object([
                "taskType": .string(r.taskType.value), "profiles": .array(r.profiles.map(profileTree)),
                "plan": planTree(r.plan), "modelUsed": used.map(Tree.string) ?? .null,
            ])
            return ("plan(\(query), \(set)\(reversed ? " reversed" : ""), \(preset), \(ov), \(active ?? "nil"), \(ram), \(maxTokens))", want, got, want == got)
        }
    }

    // MARK: planRoute

    /// planRoute's hand-built profile sets (disabled, duplicate and missing roles).
    private var profileSets: [[Profiles.ModelProfile]] {
        g["profileSets"].array.map { set in
            set.array.map {
                Profiles.ModelProfile(
                    modelId: $0["modelId"].string!, role: ModelRole.of($0["role"].string!)!, enabled: $0["enabled"].bool,
                    userOverride: false, compatibilityStatus: .unknown
                )
            }
        }
    }

    @Test func planRouteOnEveryTaskPresetProfileSetAndBudget() {
        let sets = profileSets
        check("planRoute") { c in
            let lowPower = c["lowPower"].isNull ? nil : c["lowPower"].bool
            let ctx = Router.RoutingContext(
                taskType: TaskType.of(c["taskType"].string!)!,
                query: "",
                hasLocalKnowledgeBase: c["hasKb"].bool,
                retrievalAvailable: c["retrievalAvailable"].bool,
                availableModels: sets[c["profileSet"].int],
                preset: RoutingPreset.of(c["preset"].string!)!,
                deviceState: lowPower.map { Router.DeviceState(lowPowerMode: $0) },
                budget: Router.InferenceBudget(
                    maxTokens: c["maxTokens"].int, maxTotalLatencyMs: c["latency"].int64,
                    allowVerification: c["allowVerification"].bool, allowRetrieval: c["allowRetrieval"].bool
                )
            )
            let want = c["plan"]
            let got = planTree(Router.planRoute(ctx))
            return ("planRoute(\(c))", want, got, want == got)
        }
    }

    // MARK: default model

    @Test func rankAnswerModelsAndTheLowRamCaps() {
        check("rankAnswerModels") { c in
            let ram = c["ram"].int64!
            let candidates = c["candidates"].array.map {
                DefaultModel.Candidate(
                    id: $0["id"].string!,
                    answerTier: $0["answerTier"].string.flatMap(DefaultModel.Tier.of),
                    fit: $0["fit"].string.flatMap(FitVerdict.of),
                    sizeBytes: $0["sizeBytes"].int64,
                    tokPerSec: $0["tokPerSec"].double
                )
            }
            let r = DefaultModel.rankAnswerModels(candidates, totalRamBytes: ram)
            let want = Tree.array([c["pick"], c["ranked"], c["tooBigForLowRam"], c["tooBigForAutoPick"], c["isCompact"]])
            let got = Tree.array([
                r.pick.map { .object(["id": .string($0.id), "reason": .string($0.reason)]) } ?? .null,
                .array(r.ranked.map { .object(["id": .string($0.id), "picked": .bool($0.picked), "reason": .string($0.reason)]) }),
                .array(candidates.map { .bool(DefaultModel.tooBigForLowRam($0, ram)) }),
                .array(candidates.map { .bool(DefaultModel.tooBigForAutoPick($0, ram)) }),
                .array(candidates.map { .bool(DefaultModel.isCompactModel($0)) }),
            ])
            return ("rankAnswerModels(\(c["candidates"]), \(ram))", want, got, want == got)
        }
    }

    @Test func pickDefaultAnswerModelIsTheRankingsPick() {
        let cs = [
            DefaultModel.Candidate(id: "small", answerTier: .compact, fit: .resident, sizeBytes: 986_048_768),
            DefaultModel.Candidate(id: "big", answerTier: .default, fit: .resident, sizeBytes: 2_497_281_120),
        ]
        #expect(DefaultModel.pickDefaultAnswerModel(cs, totalRamBytes: 8_000_000_000) == DefaultModel.Choice(id: "big", reason: "default-tier"))
        #expect(DefaultModel.pickDefaultAnswerModel(cs, totalRamBytes: 4_000_000_000) == DefaultModel.Choice(id: "small", reason: "compact-low-ram"))
        #expect(DefaultModel.pickDefaultAnswerModel([], totalRamBytes: 8_000_000_000) == nil)
    }

    // MARK: compatibility

    @Test func computeCompatibility() {
        check("compatibility") { c in
            let size = c["size"].int64!, ram = c["ram"].int64!
            let got = ModelCompatibility.compute(sizeBytes: size, deviceRamBytes: ram).value
            return ("computeCompatibility(\(size), \(ram))", c["out"].string!, got, c["out"].string == got)
        }
    }

    @Test func profilesKeepThePresetsRoleOrder() {
        let roles = Profiles.buildModelProfiles(.research, available: [], overrides: [:], deviceRamBytes: 0).map(\.role)
        #expect(roles == [.reasoning, .general, .verifier, .embedding])
    }
}
