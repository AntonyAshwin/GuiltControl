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
            centerMinutesInput
        }
        .contentShape(Rectangle()) // whole screen tappable
        .onTapGesture {
            // Avoid recording a tap while user is editing minutes
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
        .toolbar { // Keyboard accessory Done button
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
}

#Preview {
    ContentView()
        .environmentObject(TapHistoryStore())
}
