//
//  CourtClock.swift
//  CourtWatch
//
//  Reading "now" straight from the system makes anything that depends on the
//  current time impossible to test: a suite asserting which slots have passed
//  would pass in the morning and fail in the evening. Depending on a clock
//  instead lets a test pin the moment and keeps the production path on the
//  real one.
//
//  Named CourtClock rather than Clock so it does not collide with the standard
//  library's Clock at use sites.
//

import Foundation

protocol CourtClock: Sendable {
    /// The current moment.
    var now: Date { get }
    /// A moment on the day slots should be anchored to.
    var today: Date { get }
}

struct SystemClock: CourtClock {
    var now: Date { Date() }
    var today: Date { Date() }
}

/// A clock stopped at a chosen instant, for tests that need a known "now".
struct FixedClock: CourtClock {
    let now: Date
    var today: Date { now }
}
