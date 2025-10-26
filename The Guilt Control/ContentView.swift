//
//  ContentView.swift
//  The Guilt Control
//
//  Created by Ashwin, Antony on 26/10/25.
//

import SwiftUI

struct ContentView: View {
    // Shared store injected from App
    @EnvironmentObject private var store: TapHistoryStore
    @State private var showHistory = false
    // User-adjustable minutes that each tap will log as "Time Wasted"
    @AppStorage("defaultTapMinutes") private var tapMinutes: Int = 30
    @FocusState private var minutesFieldFocused: Bool
    @State private var minutesInput: String = ""

    var body: some View {
        ZStack {
            store.currentColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: store.progress)

            overlay

            // Center stack: reserved exclamation space, totals, input
            VStack(spacing: 28) {
                // Reserve space so totals don't jump when exclamation appears
                ZStack {
                    if store.isBlackStage {
                        CriticalMarkView()
                            .transition(.scale.combined(with: .opacity))
                    }
                    CriticalMarkView().hidden() // keeps height
                }

                totalsView   // All‑time + last 7 days

                centerMinutesInput
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !minutesFieldFocused else {
                minutesFieldFocused = false
                return
            }
            store.addTap(minutes: tapMinutes)
        }
        .onLongPressGesture(minimumDuration: 0.8) { showHistory = true }
        .sheet(isPresented: $showHistory) {
            HistoryView(isPresented: $showHistory)
                .environmentObject(store)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { minutesFieldFocused = false }
            }
        }
    }

    private var overlay: some View {
        VStack {
            HStack(alignment: .center, spacing: 12) {
                if store.count > 0 {
                    Label("\(store.count)", systemImage: "hand.tap")
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .onTapGesture { showHistory = true }
                        .transition(.scale)
                }
                Spacer()
            }
            .padding([.top, .horizontal])

            Spacer()

            if let last = store.lastTap {
                Text("Last: \(store.format(last))")
                    .font(.footnote.monospaced())
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.35), value: store.count)
        .animation(.default, value: tapMinutes)
    }

    // NEW: All‑time total (big) + last 7 days (small)
    private var totalsView: some View {
        let allTime = store.totalMinutesAllTime
        let week = store.last7dMinutes
        return VStack(spacing: 6) {
            Text(displayString(for: allTime))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("Past 7d: \(displayString(for: week))")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("All time \(allTime) minutes. Past 7 days \(week) minutes.")
        .transition(.opacity.combined(with: .scale))
    }

    // Centered minutes editor
    private var centerMinutesInput: some View {
        VStack(spacing: 8) {
            Text("Minutes per Tap")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("30", text: $minutesInput)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($minutesFieldFocused)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .frame(width: 170)
                .monospacedDigit()
                    .onTapGesture {
                        if minutesInput == String(tapMinutes) { minutesInput = "" }
                    }
                    .onChange(of: minutesInput) { newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { minutesInput = filtered }
                    }
                    .onChange(of: minutesFieldFocused) { focused in
                        if focused {
                            // Clear for fresh entry if matches stored value
                            if minutesInput == String(tapMinutes) { minutesInput = "" }
                        } else {
                            commitMinutesInput()
                        }
                    }
            }
            Stepper(value: $tapMinutes, in: 1...600, step: 1) {
                Text("Adjust: \(tapMinutes) min")
                    .monospacedDigit()
            }
            .labelsHidden()
            .onChange(of: tapMinutes) { newValue in
                if !minutesFieldFocused { minutesInput = String(newValue) }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Minutes per Tap")
        .accessibilityValue("\(tapMinutes) minutes")
        .animation(.spring(duration: 0.3), value: tapMinutes)
        .onAppear { minutesInput = String(tapMinutes) }
    }
}

// MARK: - Private helpers
private extension ContentView {
    func commitMinutesInput() {
        let filtered = minutesInput.filter { $0.isNumber }
        guard !filtered.isEmpty else {
            // Revert to existing value if user leaves blank
            minutesInput = String(tapMinutes)
            return
        }
        if let v = Int(filtered), (1...600).contains(v) {
            tapMinutes = v
            minutesInput = String(v)
        } else {
            // Clamp or revert
            let clamped = min(max(Int(filtered) ?? tapMinutes, 1), 600)
            tapMinutes = clamped
            minutesInput = String(clamped)
        }
    }

    func displayString(for totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

// Pulsing exclamation mark for critical (black) stage
private struct CriticalMarkView: View {
    @State private var pulse = false
    var body: some View {
        Text("!")
            .font(.system(size: 180, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(colors: [.red, .orange, .yellow],
                               startPoint: .top,
                               endPoint: .bottom)
            )
            .shadow(color: .red.opacity(0.85), radius: 24)
            .shadow(color: .orange.opacity(0.4), radius: 40)
            .scaleEffect(pulse ? 1.18 : 0.82)
            .opacity(pulse ? 1.0 : 0.55)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityLabel("Critical level reached")
    }
}

#Preview {
    ContentView()
        .environmentObject(TapHistoryStore())
}
