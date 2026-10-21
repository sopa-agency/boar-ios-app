import Foundation

/// Deterministic routing policy (port of src/routing/router.ts): given a task and what is available, decides an
/// execution plan (a typed list of steps). It executes nothing and never judges whether an answer is correct. Rule
/// based, not LLM driven: the same input always gives the same plan.
public enum Router {
    /// A greeting reply has nothing to fill a large budget with ("whats up?" ran to the full 512 tokens and rambled).
    /// A cap, not a floor: it only ever lowers the user's Max Output Tokens.
    public static let greetingMaxTokens = 128

    /// Token cap in low-power mode.
    public static let lowPowerMaxTokens = 256

    /// The verify step's token budget.
    public static let verifyMaxTokens = 200

    public struct InferenceBudget: Sendable, Equatable {
        public var maxTokens: Int
        /// Soft ceiling passed through to each generate/verify step's timeoutMs; advisory, not enforced here.
        public var maxTotalLatencyMs: Int64?
        public var allowVerification: Bool
        public var allowRetrieval: Bool

        public init(maxTokens: Int, maxTotalLatencyMs: Int64? = nil, allowVerification: Bool, allowRetrieval: Bool) {
            self.maxTokens = maxTokens
            self.maxTotalLatencyMs = maxTotalLatencyMs
            self.allowVerification = allowVerification
            self.allowRetrieval = allowRetrieval
        }
    }

    public struct DeviceState: Sendable, Equatable {
        public var freeRamBytes: Int64?
        /// Not wired to a battery API yet.
        public var batteryLevel: Double?
        public var lowPowerMode: Bool?

        public init(freeRamBytes: Int64? = nil, batteryLevel: Double? = nil, lowPowerMode: Bool? = nil) {
            self.freeRamBytes = freeRamBytes
            self.batteryLevel = batteryLevel
            self.lowPowerMode = lowPowerMode
        }
    }

    public enum FallbackPolicy: String, Sendable, Equatable {
        case skip, useDefault = "use-default", fail

        public var value: String { rawValue }
    }

    /// [modelSwitches]: how many times the plan swaps the resident generation model. A real cost: only one generation
    /// context fits at a time, so each swap is an unload + reload with a RAM pre-flight check.
    public struct CostEstimate: Sendable, Equatable {
        public var modelSwitches: Int
        public init(modelSwitches: Int) { self.modelSwitches = modelSwitches }
    }

    public struct RoutingStep: Sendable, Equatable {
        public var id: String
        public var type: RoutingStepType
        public var modelId: String?
        public var required: Bool
        public var maxTokens: Int?
        public var timeoutMs: Int64?

        public init(id: String, type: RoutingStepType, modelId: String? = nil, required: Bool, maxTokens: Int? = nil, timeoutMs: Int64? = nil) {
            self.id = id
            self.type = type
            self.modelId = modelId
            self.required = required
            self.maxTokens = maxTokens
            self.timeoutMs = timeoutMs
        }
    }

    public struct RoutingContext: Sendable {
        public var taskType: TaskType
        public var query: String
        public var hasLocalKnowledgeBase: Bool
        public var retrievalAvailable: Bool
        /// Already-resolved profiles (Profiles.buildModelProfiles): the router trusts them.
        public var availableModels: [Profiles.ModelProfile]
        public var preset: RoutingPreset
        public var deviceState: DeviceState?
        public var budget: InferenceBudget

        public init(
            taskType: TaskType, query: String, hasLocalKnowledgeBase: Bool, retrievalAvailable: Bool,
            availableModels: [Profiles.ModelProfile], preset: RoutingPreset, deviceState: DeviceState? = nil, budget: InferenceBudget
        ) {
            self.taskType = taskType
            self.query = query
            self.hasLocalKnowledgeBase = hasLocalKnowledgeBase
            self.retrievalAvailable = retrievalAvailable
            self.availableModels = availableModels
            self.preset = preset
            self.deviceState = deviceState
            self.budget = budget
        }
    }

    public struct RoutingPlan: Sendable, Equatable {
        public var steps: [RoutingStep]
        public var selectedModelIds: [String]
        public var estimatedCost: CostEstimate
        public var fallbackPolicy: FallbackPolicy
        /// Short machine-readable codes explaining every decision.
        public var reasonCodes: [String]

        public init(steps: [RoutingStep], selectedModelIds: [String], estimatedCost: CostEstimate, fallbackPolicy: FallbackPolicy, reasonCodes: [String]) {
            self.steps = steps
            self.selectedModelIds = selectedModelIds
            self.estimatedCost = estimatedCost
            self.fallbackPolicy = fallbackPolicy
            self.reasonCodes = reasonCodes
        }
    }

    private static func findProfile(_ models: [Profiles.ModelProfile], _ role: ModelRole) -> Profiles.ModelProfile? {
        models.first { $0.role == role && $0.enabled }
    }

    /// The generation role a task/preset prefers before looking at what is available. Research and compare always want
    /// the strongest model whatever the preset: a Simple-preset user asking a hard question shouldn't get a worse answer.
    private static func preferredRole(_ taskType: TaskType, _ preset: RoutingPreset) -> ModelRole {
        if taskType == .greeting || taskType == .conversation { return .fast }
        if taskType == .research || taskType == .compare || preset == .research { return .reasoning }
        if preset == .simple { return .general }
        return .fast
    }

    public static func planRoute(_ context: RoutingContext) -> RoutingPlan {
        var reasonCodes: [String] = []
        var steps: [RoutingStep] = []
        var selectedModelIds: [String] = []
        var stepIndex = 0
        func nextId(_ type: RoutingStepType) -> String {
            defer { stepIndex += 1 }
            return "\(type.value)-\(stepIndex)"
        }

        let constrained = context.deviceState?.lowPowerMode == true
        var effectiveMaxTokens = context.budget.maxTokens
        if constrained {
            effectiveMaxTokens = min(effectiveMaxTokens, lowPowerMaxTokens)
            reasonCodes.append("budget:low-power-mode-caps-tokens-and-role")
        }
        if context.taskType == .greeting {
            // Caps, never raises: a lower user Max Output Tokens stays.
            effectiveMaxTokens = min(effectiveMaxTokens, greetingMaxTokens)
            reasonCodes.append("budget:greeting-caps-tokens")
        }

        // 1. Retrieval, skipped where local documents aren't the relevant input (Classify.isRetrievalIrrelevant).
        let retrievalIrrelevant = Classify.isRetrievalIrrelevant(context.taskType)
        let wantsRetrieval = context.budget.allowRetrieval && context.retrievalAvailable && context.hasLocalKnowledgeBase && !retrievalIrrelevant
        if wantsRetrieval {
            steps.append(RoutingStep(id: nextId(.retrieve), type: .retrieve, required: false))
            reasonCodes.append("retrieve:relevant-to-task")
        } else {
            reasonCodes.append(retrievalIrrelevant ? "retrieve:skipped-task-not-knowledge-based" : "retrieve:skipped-unavailable-or-disabled")
        }

        // 2. Generation, the one required step. The preferred role degrades to whatever is enabled rather than failing:
        // a user with one suitable model still has a functional app.
        let wantRole: ModelRole = constrained ? .fast : preferredRole(context.taskType, context.preset)
        var genProfile = findProfile(context.availableModels, wantRole)
        if genProfile == nil {
            genProfile = findProfile(context.availableModels, .general)
                ?? findProfile(context.availableModels, .reasoning)
                ?? findProfile(context.availableModels, .fast)
                ?? context.availableModels.first { $0.enabled }
            if let g = genProfile {
                reasonCodes.append("generate:role-\(wantRole.value)-unavailable-fell-back-to-\(g.role.value)")
            }
        } else {
            reasonCodes.append("generate:role-\(wantRole.value)-resolved-to-\(genProfile!.modelId)")
        }

        if let g = genProfile {
            steps.append(RoutingStep(
                id: nextId(.generate), type: .generate, modelId: g.modelId, required: true,
                maxTokens: effectiveMaxTokens, timeoutMs: context.budget.maxTotalLatencyMs
            ))
            selectedModelIds.append(g.modelId)
        } else {
            reasonCodes.append("generate:no-model-available")
        }

        // 3. Verification, only when plausibly worth its cost: research/compare under the research preset, with
        // retrieved evidence AND a verifier that is a different model (a model grading itself isn't verification).
        let wantsVerification = context.budget.allowVerification
            && !constrained
            && context.preset == .research
            && (context.taskType == .research || context.taskType == .compare)
            && wantsRetrieval
            && genProfile != nil
        if wantsVerification {
            if let verifier = findProfile(context.availableModels, .verifier), verifier.modelId != genProfile!.modelId {
                steps.append(RoutingStep(
                    id: nextId(.verify), type: .verify, modelId: verifier.modelId, required: false,
                    maxTokens: verifyMaxTokens, timeoutMs: context.budget.maxTotalLatencyMs
                ))
                if !selectedModelIds.contains(verifier.modelId) { selectedModelIds.append(verifier.modelId) }
                reasonCodes.append("verify:enabled")
            } else {
                reasonCodes.append("verify:skipped-no-distinct-verifier-model")
            }
        } else {
            reasonCodes.append("verify:not-applicable")
        }

        return RoutingPlan(
            steps: steps,
            selectedModelIds: selectedModelIds,
            estimatedCost: CostEstimate(modelSwitches: max(0, selectedModelIds.count - 1)),
            fallbackPolicy: .useDefault,
            reasonCodes: reasonCodes
        )
    }
}
