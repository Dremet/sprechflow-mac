import Testing
@testable import SprechflowCore

struct DictationGestureTests {
    @Test func holdStartsThenReleaseStops() {
        var gesture = DictationGesture()
        #expect(gesture.modifiersChanged(chordIsDown: true, at: 0).isEmpty)
        #expect(gesture.tick(at: 0.2).isEmpty)
        #expect(gesture.tick(at: 0.26) == [.startHold])
        #expect(gesture.modifiersChanged(chordIsDown: true, at: 0.3).isEmpty)
        #expect(gesture.modifiersChanged(chordIsDown: false, at: 2) == [.stop])
        #expect(gesture.tick(at: 3).isEmpty)
    }

    @Test func doubleTapLatchesUntilNextPress() {
        var gesture = DictationGesture()
        _ = gesture.modifiersChanged(chordIsDown: true, at: 0)
        #expect(gesture.modifiersChanged(chordIsDown: false, at: 0.1).isEmpty)
        #expect(gesture.modifiersChanged(chordIsDown: true, at: 0.2) == [.startHandsFree])
        #expect(gesture.modifiersChanged(chordIsDown: false, at: 0.3).isEmpty)
        #expect(gesture.tick(at: 20).isEmpty)
        #expect(gesture.modifiersChanged(chordIsDown: true, at: 21) == [.stop])
        #expect(gesture.tick(at: 22).isEmpty)
        #expect(gesture.modifiersChanged(chordIsDown: false, at: 23).isEmpty)
    }

    @Test func singleTapAndOrdinaryShortcutsDoNotRecord() {
        var gesture = DictationGesture()
        _ = gesture.modifiersChanged(chordIsDown: true, at: 0)
        _ = gesture.modifiersChanged(chordIsDown: false, at: 0.1)
        #expect(gesture.tick(at: 0.6).isEmpty)
        _ = gesture.modifiersChanged(chordIsDown: true, at: 1)
        gesture.otherKeyPressed()
        #expect(gesture.tick(at: 2).isEmpty)
        #expect(gesture.modifiersChanged(chordIsDown: false, at: 3).isEmpty)
    }

    @Test func lateSecondPressBecomesHoldInsteadOfHandsFree() {
        var gesture = DictationGesture()
        _ = gesture.modifiersChanged(chordIsDown: true, at: 0)
        _ = gesture.modifiersChanged(chordIsDown: false, at: 0.1)
        #expect(gesture.modifiersChanged(chordIsDown: true, at: 1).isEmpty)
        #expect(gesture.tick(at: 1.3) == [.startHold])
    }

    @Test func resetWhileHeldCannotRestartUntilRelease() {
        var gesture = DictationGesture()
        _ = gesture.modifiersChanged(chordIsDown: true, at: 0)
        _ = gesture.tick(at: 1)
        gesture.reset()
        #expect(gesture.tick(at: 2).isEmpty)
        #expect(gesture.modifiersChanged(chordIsDown: false, at: 3).isEmpty)
        _ = gesture.modifiersChanged(chordIsDown: true, at: 4)
        #expect(gesture.tick(at: 4.3) == [.startHold])
    }

    @Test func blockedRunLoopNeverStartsAfterRelease() {
        var gesture = DictationGesture()
        _ = gesture.modifiersChanged(chordIsDown: true, at: 0)
        #expect(gesture.modifiersChanged(chordIsDown: false, at: 2).isEmpty)
        #expect(gesture.tick(at: 3).isEmpty)
    }
}
