import BackgroundTasks
import Foundation
import os

/// Lets transcription keep running for a while after the user leaves the app, using iOS 26
/// continued-processing tasks. The system shows the progress in a Live Activity and the user can
/// cancel it there. If the system declines the request, processing simply continues while the app
/// is in the foreground.
@MainActor
final class BackgroundProcessingCoordinator {
    private struct Job {
        var title: String
        var task: BGContinuedProcessingTask?
        var fraction: Double = 0
        var subtitle: String
        var onExpiration: () -> Void
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EarToNote", category: "Background")
    private var jobs: [UUID: Job] = [:]

    private var identifierPrefix: String {
        "\(Bundle.main.bundleIdentifier ?? "com.eartonote.app").process"
    }

    func begin(jobID: UUID, title: String, subtitle: String, onExpiration: @escaping () -> Void) {
        guard jobs[jobID] == nil else { return }
        jobs[jobID] = Job(title: title, task: nil, subtitle: subtitle, onExpiration: onExpiration)

        // Each job uses a unique identifier because registering the same identifier twice terminates the app.
        let identifier = "\(identifierPrefix).\(jobID.uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                self?.attach(task, to: jobID)
            }
        }
        guard registered else {
            logger.warning("Continued processing identifier is not permitted: \(identifier, privacy: .public)")
            return
        }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.info("Continued processing request was declined: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(jobID: UUID, fraction: Double, subtitle: String) {
        guard var job = jobs[jobID] else { return }
        job.fraction = fraction
        job.subtitle = subtitle
        jobs[jobID] = job
        if let task = job.task {
            apply(job, to: task)
        }
    }

    func end(jobID: UUID, success: Bool) {
        guard let job = jobs.removeValue(forKey: jobID) else { return }
        if let task = job.task {
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.setTaskCompleted(success: success)
        }
    }

    private func attach(_ task: BGTask, to jobID: UUID) {
        guard let task = task as? BGContinuedProcessingTask, var job = jobs[jobID] else {
            // The job already finished before the system started the task.
            task.setTaskCompleted(success: true)
            return
        }
        task.progress.totalUnitCount = 100
        let onExpiration = job.onExpiration
        task.expirationHandler = {
            Task { @MainActor in
                onExpiration()
            }
        }
        job.task = task
        jobs[jobID] = job
        apply(job, to: task)
    }

    private func apply(_ job: Job, to task: BGContinuedProcessingTask) {
        task.progress.completedUnitCount = Int64((min(max(job.fraction, 0), 1) * 100).rounded())
        task.updateTitle(job.title, subtitle: job.subtitle)
    }
}
