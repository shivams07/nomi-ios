/// G1 and G4. The refresh token each cache-backed root route receives. Every
/// route takes the same cache generation (`AppEnvironment.insightsGeneration`),
/// which changes after a sync or a Siri write, so a pushed or tab-root screen
/// re-reads. A route that takes a literal instead, `0` for example, never sees
/// the change: that is the failure these per-route properties pin.
///
/// Pure, so `RootView` passes `tokens.<route>` and the mapping is asserted
/// without rendering it.
struct RouteTokens: Equatable {
  let dashboard: Int
  let budgets: Int
  let subscriptions: Int
  let settings: Int
  let reports: Int
  let accounts: Int

  init(generation: Int) {
    dashboard = generation
    budgets = generation
    subscriptions = generation
    settings = generation
    reports = generation
    accounts = generation
  }
}
