//  HistoryView.swift
//  The Guilt Control
//
//  Presents editable history of tap entries with Time Wasted field.
//
//  Long-press main screen or tap counter to show.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: TapHistoryStore
    @Binding var isPresented: Bool

    @State private var showAddSheet = false
    @State private var editingEntry: TapEntry? = nil
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView("No History", systemImage: "clock", description: Text("Tap the green screen or add manually."))
                } else {
                    List {
                        ForEach(store.entries.sorted { $0.date > $1.date }) { entry in
                            Button { editingEntry = entry } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(store.format(entry.date))
                                            .font(.subheadline.monospaced())
                                        if entry.minutes > 0 {
                                            Text("Time Wasted: \(entry.minutes) min")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .tint(.primary)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.delete(entry: entry) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { editingEntry = entry } label: {
                                    Label("Edit", systemImage: "pencil")
                                }.tint(.blue)
                            }
                        }
                        .onDelete(perform: { indexSet in
                            // IndexSet corresponds to sorted order applied above; map back to original
                            let sorted = store.entries.sorted { $0.date > $1.date }
                            for index in indexSet { store.delete(entry: sorted[index]) }
                        })
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !store.entries.isEmpty {
                        Button(role: .destructive) { showClearConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Clear All")
                    }
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Entry")
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { store.clearAll() }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(item: $editingEntry, content: { entry in
                EditEntryView(mode: .edit, original: entry) { updated in
                    store.update(entry: updated)
                }
            })
            .sheet(isPresented: $showAddSheet) {
                EditEntryView(mode: .add, original: TapEntry(date: Date(), minutes: 0)) { newEntry in
                    store.addManual(date: newEntry.date, minutes: newEntry.minutes)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add/Edit View
private struct EditEntryView: View {
    enum Mode { case add, edit }
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    let onSave: (TapEntry) -> Void

    @State private var entry: TapEntry

    init(mode: Mode, original: TapEntry, onSave: @escaping (TapEntry) -> Void) {
        self.mode = mode
        self._entry = State(initialValue: original)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Timestamp") {
                    DatePicker("Date & Time", selection: $entry.date)
                }
                Section("Time Wasted (minutes)") {
                    Stepper(value: $entry.minutes, in: 0...10_000) {
                        HStack {
                            Text("Minutes")
                            Spacer()
                            Text("\(entry.minutes)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Enter minutes", value: $entry.minutes, format: .number)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(mode == .add ? "Add Entry" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(entry.minutes < 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// Preview
#Preview {
    HistoryView(isPresented: .constant(true))
        .environmentObject(TapHistoryStore())
}
