// ============================================================================
// DebugFlagBaselineTests.swift — Baseline for the apfelDebugEnabled refactor
// promised in #105 ("Replace nonisolated(unsafe) var with Mutex or actor").
//
// What this file locks in:
//   - Public type of the flag is Bool (not an actor, not a Mutex wrapper).
//   - Reads and writes are SYNCHRONOUS from both sync and async contexts.
//   - Default value is false.
//   - Save/restore pattern (the idiom used across the test suite) works.
//
// If the refactor changes this contract (e.g. `await apfelDebugFlag.get()`),
// these tests stop compiling — which is the deliberate signal that every call
// site needs updating. That is the point of this baseline.
// ============================================================================

import Foundation
import ApfelCore

func runDebugFlagBaselineTests() {
    test("apfelDebugEnabled is typed as Bool") {
        // Compile-time assertion. If the variable's type ever changes, the
        // assignment below stops compiling.
        let snapshot: Bool = apfelDebugEnabled
        // Use snapshot so the compiler doesn't warn about unused binding.
        try assertTrue(snapshot == true || snapshot == false)
    }

    test("apfelDebugEnabled has default value false at test-runner startup") {
        // Only meaningful if nothing earlier in the suite left it true without
        // restoring. The existing DebugLoggerTests use defer-restore, so this
        // assertion holds and guards against future leakage.
        try assertEqual(apfelDebugEnabled, false)
    }

    test("apfelDebugEnabled supports synchronous write + read") {
        let original = apfelDebugEnabled
        defer { apfelDebugEnabled = original }
        apfelDebugEnabled = true
        try assertEqual(apfelDebugEnabled, true)
        apfelDebugEnabled = false
        try assertEqual(apfelDebugEnabled, false)
    }

    test("nested save/restore idiom restores prior value") {
        let original = apfelDebugEnabled
        defer { apfelDebugEnabled = original }

        apfelDebugEnabled = true
        do {
            let inner = apfelDebugEnabled
            defer { apfelDebugEnabled = inner }
            apfelDebugEnabled = false
            try assertEqual(apfelDebugEnabled, false)
        }
        try assertEqual(apfelDebugEnabled, true)
    }

    testAsync("apfelDebugEnabled reads synchronously from an async context") {
        // If this variable becomes actor-isolated, the line below would require
        // `await`, which is a breaking change for every file that reads the
        // flag from async code today (Session, Handlers, Server streaming path).
        let _: Bool = apfelDebugEnabled
    }

    testAsync("apfelDebugEnabled writes synchronously from an async context") {
        let original = apfelDebugEnabled
        defer { apfelDebugEnabled = original }
        apfelDebugEnabled = true
        try assertEqual(apfelDebugEnabled, true)
    }
}
