import EventKit
import Foundation

enum CalendarServiceError: LocalizedError {
    case noDueDate
    case permissionDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .noDueDate:
            return "期限日がないTODOはカレンダーに追加できません。"
        case .permissionDenied:
            return "カレンダーへのアクセスが許可されていません。"
        case .calendarUnavailable:
            return "追加先のカレンダーが見つかりません。"
        }
    }
}

final class CalendarService {
    private let eventStore = EKEventStore()

    func addEvent(for task: TodoTask) async throws {
        guard let dueDate = task.dueDate else {
            throw CalendarServiceError.noDueDate
        }

        let granted = try await requestAccess()
        guard granted else {
            throw CalendarServiceError.permissionDenied
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarServiceError.calendarUnavailable
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = task.title
        event.notes = task.note.isEmpty ? nil : task.note
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = dueDate.startOfDay
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: dueDate.startOfDay) ?? dueDate.startOfDay
        try eventStore.save(event, span: .thisEvent)
    }

    private func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
}
