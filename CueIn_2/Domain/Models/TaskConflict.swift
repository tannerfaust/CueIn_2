import Foundation

/// Outcome of the server-side 3-way conflict check during integration push.
///
/// The server returns a `TaskConflict` instead of pushing whenever it detects
/// that *both* sides changed since the last successful sync — i.e. the user
/// edited the task in CueIn while a teammate (or the user themself) edited the
/// same record in Linear/Notion. Auto-resolving with last-write-wins would
/// silently lose data, so the client surfaces the conflict and asks the user.
///
/// Stored locally only (no Supabase column) — once resolved, the conflict
/// disappears on the next successful sync.
struct TaskConflict: Identifiable, Equatable, Codable, Hashable {

    enum Source: String, Codable, Hashable { case linear, notion }

    let cueInID: UUID
    let source: Source
    /// When Linear / Notion last accepted an edit to this task. Newer than the
    /// link's recorded value, otherwise this wouldn't be a conflict.
    let remoteUpdatedAt: Date
    /// When CueIn last edited this task locally.
    let localUpdatedAt: Date
    /// Snapshot of the remote-side fields the server fetched while detecting
    /// the conflict (title, status, priority, etc.). Lets the resolution UI
    /// preview "their" version without an extra API round-trip.
    let remoteSnapshot: [String: String]
    /// When the conflict was first observed locally; used to keep the banner
    /// stable even after retries.
    let observedAt: Date

    var id: UUID { cueInID }
}
