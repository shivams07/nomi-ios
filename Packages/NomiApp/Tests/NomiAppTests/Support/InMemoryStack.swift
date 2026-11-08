import NomiApp
import SwiftData

/// An in-memory SwiftData stack for a test: one `ModelContainer` and the
/// `mainContext` that belongs to it.
///
/// **A test must keep the stack alive for as long as it uses the context.** A
/// `ModelContext` does not keep its `ModelContainer` alive. A helper that builds
/// a container and returns only `container.mainContext`, or returns a tuple
/// whose container the caller drops with `_`, lets the container go while the
/// context is still in use, and SwiftData traps. That is the crash behind the
/// test failures on `main`: the process dies on the first such test, and
/// `xcodebuild test` restarts it once per crash.
///
/// Hold the stack in a stored property of the test case, not in a local. Swift
/// may end a local's lifetime after its last use, and the context's use is not
/// what keeps the container alive:
///
///     private var stacks: [InMemoryStack] = []
///
///     private func makeContext() throws -> ModelContext {
///       let stack = try InMemoryStack(schema: Schema([Transaction.self]))
///       stacks.append(stack)
///       return stack.context
///     }
///
/// The default schema is the app's own (`NomiModelContainer.schema`). Not
/// `InMemoryModelContainer.shared`: that one is shared across tests, and these
/// tests count rows.
@MainActor
final class InMemoryStack {
  let container: ModelContainer
  let context: ModelContext

  init(schema: Schema = NomiModelContainer.schema) throws {
    let configuration = ModelConfiguration(
      schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    container = try ModelContainer(for: schema, configurations: [configuration])
    context = container.mainContext
  }
}
