import Foundation
import SwiftData

@Model
final class WorkSession {
    @Attribute(.unique) var id: UUID
    var stateRawValue: String
    var startAt: Date
    var endAt: Date?
    var lastHeartbeatAt: Date
    var isSystemGeneratedRest: Bool = false

    var state: WorkState {
        get { WorkState(rawValue: stateRawValue) ?? .sitting }
        set { stateRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        state: WorkState,
        startAt: Date,
        endAt: Date? = nil,
        lastHeartbeatAt: Date? = nil,
        isSystemGeneratedRest: Bool = false
    ) {
        self.id = id
        self.stateRawValue = state.rawValue
        self.startAt = startAt
        self.endAt = endAt
        self.lastHeartbeatAt = lastHeartbeatAt ?? startAt
        self.isSystemGeneratedRest = isSystemGeneratedRest
    }
}
