import Foundation

/// A tiny, dependency-free property-test harness used because this environment lacks XCTest /
/// SwiftCheck (Command Line Tools only). Deterministic via an explicit seed (PBT-08 spirit):
/// failures print the seed + iteration so they can be replayed.
public struct PRNG {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    public mutating func next() -> UInt64 {
        // SplitMix64
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func int(_ lo: Int, _ hi: Int) -> Int {
        if hi <= lo { return lo }
        return lo + Int(next() % UInt64(hi - lo + 1))
    }

    public mutating func u32() -> UInt32 { UInt32(truncatingIfNeeded: next()) }
    public mutating func bool() -> Bool { (next() & 1) == 0 }
    public mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next()) }
}

public struct PropertyRunner {
    public private(set) var failures: [String] = []
    public private(set) var passed = 0
    private let seed: UInt64
    private let iterations: Int

    public init(seed: UInt64 = 0xC0FFEE, iterations: Int = 500) {
        self.seed = seed
        self.iterations = iterations
    }

    /// Runs `body` for N iterations with a per-property deterministic PRNG. `body` returns true on success.
    public mutating func check(_ name: String, _ body: (inout PRNG) -> Bool) {
        var prng = PRNG(seed: seed &+ UInt64(name.hashValue & 0xFFFF))
        for i in 0..<iterations {
            if !body(&prng) {
                failures.append("FAIL [\(name)] at iteration \(i) (seed=\(seed))")
                print("✗ \(name) — failed at iteration \(i) (seed=\(seed))")
                return
            }
        }
        passed += 1
        print("✓ \(name) (\(iterations) cases)")
    }

    /// A single example assertion evaluated from a closure (lets call sites build state inline).
    public mutating func expect(_ name: String, _ body: () -> Bool) {
        expect(name, body())
    }

    /// A single example assertion.
    public mutating func expect(_ name: String, _ condition: Bool) {
        if condition {
            passed += 1
            print("✓ \(name)")
        } else {
            failures.append("FAIL [\(name)]")
            print("✗ \(name)")
        }
    }

    public var allPassed: Bool { failures.isEmpty }
}
