//  TapHistoryStore.swift
//  The Guilt Control
//
//  Created for shared tap tracking.
//
//  This store records tap timestamps, persists them in UserDefaults,
//  and exposes a color that linearly shifts from green -> red over
//  the first 50 taps.

import Foundation
import SwiftUI

// MARK: - Model
struct TapEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var minutes: Int // "Time Wasted" in minutes (editable)

    init(id: UUID = UUID(), date: Date, minutes: Int = 0) {
        self.id = id
        self.date = date
        self.minutes = minutes
    }
}

// MARK: - Store
@MainActor
final class TapHistoryStore: ObservableObject {
    @Published private(set) var entries: [TapEntry] = []
    private let key = "TapHistoryStore.entries"

    // MARK: - New configuration (tune if desired)
    private let repairWindow: TimeInterval = 24 * 3600      // Each entry fades to 0 influence over 24h
    private let fullRedMinutes: Double = 120                // Decayed minutes needed for full red (≈ four 30‑min sessions)

    private var decayTimer: Timer?

    init() {
        load()
        startDecayTimer()
    }

    // MARK: CRUD
    func addTap(minutes: Int = 0) {
        entries.append(TapEntry(date: Date(), minutes: max(0, minutes)))
        persist()
    }

    func addManual(date: Date, minutes: Int) {
        entries.append(TapEntry(date: date, minutes: max(0, minutes)))
        sortInPlace()
        persist()
    }

    func update(entry: TapEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            sortInPlace()
            persist()
        }
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    func delete(entry: TapEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clearAll() {
        entries.removeAll()
        persist()
    }

    // MARK: Derived
    var lastTap: Date? { entries.last?.date }
    var count: Int { entries.count }

    // Total decayed minutes = sum(minutes * linearDecayFactor(0→1))
    private var decayedTotalMinutes: Double {
        let now = Date()
        return entries.reduce(0.0) { partial, entry in
            let age = now.timeIntervalSince(entry.date)
            if age >= repairWindow { return partial }               // fully repaired
            let weight = 1.0 - (age / repairWindow)                 // linear decay
            return partial + (Double(entry.minutes) * weight)
        }
    }

    // Progress based on decayed minutes, not tap count
    var progress: Double {
        guard fullRedMinutes > 0 else { return 0 }
        return min(decayedTotalMinutes / fullRedMinutes, 1.0)
    }

    // Progress thresholds for staged "decay"
    // 0–s1: fresh green → browning
    // s1–s2: browning → rotten red
    // s2–s3: rotten red → bruised purple
    // s3–1: bruised purple → danger black
    private let s1: Double = 0.35
    private let s2: Double = 0.65
    private let s3: Double = 0.85

    // Tunable gamma ( <1 = reach later colors sooner / faster decay feel )
    private let gamma: Double = 0.88

    // Palette (muted & progressively darker)
    private let freshRGB      = (r: 0.38, g: 0.74, b: 0.46) // fresh healthy green
    private let browningRGB   = (r: 0.60, g: 0.52, b: 0.24) // early rot (olive / amber)
    private let rottenRedRGB  = (r: 0.62, g: 0.20, b: 0.18) // dull spoiled red
    private let bruiseRGB     = (r: 0.42, g: 0.22, b: 0.50) // dark bruised purple
    private let blackRGB      = (r: 0.03, g: 0.03, b: 0.04) // near-black (soft)

    var currentColor: Color {
        let pLinear = progress
        let p = pow(pLinear, gamma)

        let (r,g,b): (Double,Double,Double)
        switch p {
        case ..<s1:
            let t = p / s1
            (r,g,b) = (
                lerp(freshRGB.r, browningRGB.r, t),
                lerp(freshRGB.g, browningRGB.g, t),
                lerp(freshRGB.b, browningRGB.b, t)
            )
        case ..<s2:
            let t = (p - s1) / (s2 - s1)
            (r,g,b) = (
                lerp(browningRGB.r, rottenRedRGB.r, t),
                lerp(browningRGB.g, rottenRedRGB.g, t),
                lerp(browningRGB.b, rottenRedRGB.b, t)
            )
        case ..<s3:
            let t = (p - s2) / (s3 - s2)
            (r,g,b) = (
                lerp(rottenRedRGB.r, bruiseRGB.r, t),
                lerp(rottenRedRGB.g, bruiseRGB.g, t),
                lerp(rottenRedRGB.b, bruiseRGB.b, t)
            )
        default:
            let t = (p - s3) / (1 - s3)
            (r,g,b) = (
                lerp(bruiseRGB.r, blackRGB.r, t),
                lerp(bruiseRGB.g, blackRGB.g, t),
                lerp(bruiseRGB.b, blackRGB.b, t)
            )
        }
        return Color(red: r, green: g, blue: b)
    }

    // Trigger "danger" state only once we enter final (black) band
    var isBlackStage: Bool { progress >= s3 }

    // Simple linear interpolation
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    // MARK: Persistence
    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            #if DEBUG
            print("Persist error: \(error)")
            #endif
        }
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode([TapEntry].self, from: data) {
                entries = decoded.sorted { $0.date < $1.date }
                return
            }
        }
        if let legacy = defaults.array(forKey: key) as? [Double] {
            let migrated = legacy.map { TapEntry(date: Date(timeIntervalSince1970: $0), minutes: 0) }
            entries = migrated.sorted { $0.date < $1.date }
            persist()
        }
    }

    private func sortInPlace() {
        entries.sort { $0.date < $1.date }
    }

    // MARK: - Decay Timer
    private func startDecayTimer() {
        decayTimer?.invalidate()
        // Tick each minute to refresh color as entries heal
        decayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Trigger view updates (computed properties depend on time)
                self?.objectWillChange.send()
            }
        }
    }

    deinit {
        decayTimer?.invalidate()
    }

    // MARK: Formatting
    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    func format(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
