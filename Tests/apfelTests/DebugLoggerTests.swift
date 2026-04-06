import Foundation
import ApfelCore

func runDebugLoggerTests() {
    test("apfelDebugEnabled defaults to false") {
        try assertEqual(apfelDebugEnabled, false)
    }
    test("apfelDebugEnabled can be toggled") {
        let original = apfelDebugEnabled
        defer { apfelDebugEnabled = original }
        apfelDebugEnabled = true
        try assertEqual(apfelDebugEnabled, true)
    }
}
