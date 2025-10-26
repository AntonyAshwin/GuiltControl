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

    // Interpolate RGB from green (0,1,0) to red (1,0,0)
    var currentColor: Color {
        let p = progress
        return Color(red: p, green: 1 - p, blue: 0)
    }

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
