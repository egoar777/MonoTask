import Foundation
import SwiftData

/// Represents a deleted record that needs to be synchronized to Supabase.
/// This prevents empty local databases (such as after a clean install)
/// from falsely assuming remote records were deleted.
@Model
final class SyncTombstone {
    var id: UUID = UUID()
    var recordId: UUID = UUID()
    var recordType: String = ""
    var deletedAt: Date = Date.now

    init(recordId: UUID, recordType: String, deletedAt: Date = Date.now) {
        self.id = UUID()
        self.recordId = recordId
        self.recordType = recordType
        self.deletedAt = deletedAt
    }
}
