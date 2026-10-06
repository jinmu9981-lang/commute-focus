import Foundation

enum Planner {
    /// Forecast assumes earlier steps are confirmed complete. Only the first
    /// segment may start; the app rebuilds the plan after each confirmation.
    static func make(tasks: [WorkTask], steps: [WorkStep], availableSeconds: Int,
                     excluding: Set<UUID> = []) -> Plan {
        var budget = max(0, availableSeconds / 60 * 60)
        var segments: [FocusSegment] = []
        var reasons: [String] = []
        let ordered = tasks.filter { !excluding.contains($0.id) }.sorted {
            if $0.priority != $1.priority { return $0.priority.rawValue < $1.priority.rawValue }
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for task in ordered {
            var pending = steps.filter { $0.taskID == task.id && !$0.completed }.sorted {
                $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
            }
            // Zero estimates must be corrected, never silently bypassed.
            if pending.first?.remainingSeconds == 0 {
                reasons.append("\(task.title)：请重新估算首个未完成步骤")
                continue
            }
            while !pending.isEmpty && budget >= 600 {
                if pending[0].remainingSeconds <= 0 { break }
                var group = [pending.removeFirst()]
                var total = group[0].remainingSeconds
                while total < 600, let next = pending.first, next.remainingSeconds > 0 {
                    group.append(pending.removeFirst())
                    total += next.remainingSeconds
                }
                if total < 600 {
                    reasons.append("\(task.title)：不足 10 分钟且没有可合并的后续步骤")
                    break
                }
                // Whole-minute blocks; sub-minute remainder stays on the step.
                let roundedTotal = Int(ceil(Double(total) / 60)) * 60
                var duration = min(1500, roundedTotal)
                if roundedTotal > duration && roundedTotal - duration < 600 {
                    duration = roundedTotal <= 1800 ? roundedTotal : roundedTotal - 600
                }
                duration = min(duration, budget, 1800)
                guard duration >= 600 else { break }
                if roundedTotal > duration && roundedTotal - duration < 600 {
                    reasons.append("\(task.title)：本次时间不足，保留完整步骤以避免不足 10 分钟的尾段")
                    break
                }
                var remaining = duration
                var allocations: [Allocation] = []
                var unfinished: [WorkStep] = []
                for var step in group {
                    let used = min(remaining, step.remainingSeconds)
                    if used > 0 {
                        allocations.append(Allocation(stepID: step.id, title: step.title, seconds: used))
                    }
                    remaining -= used
                    step.remainingSeconds -= used
                    if step.remainingSeconds > 0 { unfinished.append(step) }
                }
                // A minute rounding remainder belongs to the final allocation.
                if remaining > 0 && !allocations.isEmpty {
                    allocations[allocations.count - 1].seconds += remaining
                }
                pending = unfinished + pending
                segments.append(FocusSegment(taskID: task.id, taskTitle: task.title, allocations: allocations))
                budget -= duration
            }
        }
        if segments.isEmpty && reasons.isEmpty {
            reasons.append(budget < 600 ? "剩余时间不足 10 分钟，适合收尾或休息" : "暂无可安排的任务，请先添加任务和步骤")
        }
        return Plan(segments: segments, reasons: reasons)
    }
}
