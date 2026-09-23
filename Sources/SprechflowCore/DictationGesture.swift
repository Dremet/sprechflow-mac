import Foundation

/// The platform adapter supplies only the modifier chord and monotonic timestamps.
/// Ordinary typing is never recorded. A short first tap waits for a second tap;
/// holding the first press starts momentary recording after a small debounce.
public struct DictationGesture {
    public enum Action: Equatable { case startHold, startHandsFree, stop }
    private enum Phase {
        case idle, armed(TimeInterval), waitingForSecond(TimeInterval), holding, handsFree, suppressed
    }
    public let holdDelay: TimeInterval
    public let doubleTapInterval: TimeInterval
    private var phase: Phase = .idle
    private var chordDown = false

    public init(holdDelay: TimeInterval = 0.25, doubleTapInterval: TimeInterval = 0.35) {
        self.holdDelay = holdDelay
        self.doubleTapInterval = doubleTapInterval
    }

    public var deadline: TimeInterval? {
        switch phase {
        case .armed(let start): return start + holdDelay
        case .waitingForSecond(let end): return end
        default: return nil
        }
    }

    public mutating func modifiersChanged(chordIsDown: Bool, at time: TimeInterval) -> [Action] {
        guard chordIsDown != chordDown else { return [] }
        chordDown = chordIsDown
        if chordIsDown {
            switch phase {
            case .waitingForSecond(let deadline) where time <= deadline:
                phase = .handsFree
                return [.startHandsFree]
            case .handsFree:
                phase = .suppressed
                return [.stop]
            case .idle, .waitingForSecond:
                phase = .armed(time)
            default: break
            }
        } else {
            switch phase {
            case .armed(let start):
                // If the main run loop was delayed, never start recording after release.
                phase = time - start < holdDelay ? .waitingForSecond(time + doubleTapInterval) : .idle
            case .holding:
                phase = .idle
                return [.stop]
            case .suppressed: phase = .idle
            default: break
            }
        }
        return []
    }

    public mutating func tick(at time: TimeInterval) -> [Action] {
        switch phase {
        case .armed(let start) where chordDown && time >= start + holdDelay:
            phase = .holding
            return [.startHold]
        case .waitingForSecond(let deadline) where time >= deadline:
            phase = .idle
        default: break
        }
        return []
    }

    public mutating func otherKeyPressed() {
        switch phase {
        case .armed, .waitingForSecond: phase = chordDown ? .suppressed : .idle
        default: break
        }
    }

    /// Resets a failed, cancelled or externally stopped recording. A chord still
    /// held down must be released before it can trigger another recording.
    public mutating func reset() { phase = chordDown ? .suppressed : .idle }
}
