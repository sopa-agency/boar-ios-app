import Foundation

/// The planning half of src/services/adaptiveChat.ts runAdaptiveChat: classify -> profiles -> plan, from on-device
/// state the caller resolved (installed models, preset, role assignments, active model, RAM). Execution is separate.
public enum AdaptivePlan {
    public struct Result: Sendable, Equatable {
        /// Classify.classifyTask(query): the plan doesn't carry it, only the decisions made from it.
        public var taskType: TaskType
        public var profiles: [Profiles.ModelProfile]
        public var plan: Router.RoutingPlan

        public init(taskType: TaskType, profiles: [Profiles.ModelProfile], plan: Router.RoutingPlan) {
            self.taskType = taskType
            self.profiles = profiles
            self.plan = plan
        }

        /// The generate step's model id, nil if the plan has no generate step. adaptiveChat's modelUsed is this id
        /// looked up in the catalog (nil for a non-catalog model): the caller does that lookup.
        public var generateModelId: String? { plan.steps.first { $0.type == .generate }?.modelId }
    }

    /// [statuses]: every catalog asset with whether it is on disk (ModelManager.statusAll); only LLMs are used.
    /// [overrides]: the user's role assignments. [activeModelId]: the model the user picked ("Use"); it fills the fast
    /// and general roles unless the user assigned those explicitly (without this, balanced routing ignored the user's
    /// choice). [deviceRamBytes]: total RAM, 0 when unreadable (compatibility becomes "unknown").
    public static func plan(
        query: String,
        statuses: [Profiles.AvailableModel],
        preset: RoutingPreset,
        overrides: [ModelRole: String],
        activeModelId: String?,
        deviceRamBytes: Int64,
        maxTokens: Int
    ) -> Result {
        let available = statuses.filter { $0.model.isLanguageModel }
        let taskType = Classify.classifyTask(query)
        var effectiveOverrides = overrides
        if let active = activeModelId, !active.isEmpty {
            // mapOf(FAST to active, GENERAL to active) + overrides: the user's explicit assignments win.
            effectiveOverrides = [.fast: active, .general: active].merging(overrides) { _, user in user }
        }
        let profiles = Profiles.buildModelProfiles(preset, available: available, overrides: effectiveOverrides, deviceRamBytes: deviceRamBytes, fallbackModelId: activeModelId)
        let context = Router.RoutingContext(
            taskType: taskType,
            query: query,
            hasLocalKnowledgeBase: true,
            retrievalAvailable: true,
            availableModels: profiles,
            preset: preset,
            budget: Router.InferenceBudget(maxTokens: maxTokens, allowVerification: true, allowRetrieval: true)
        )
        return Result(taskType: taskType, profiles: profiles, plan: Router.planRoute(context))
    }
}
