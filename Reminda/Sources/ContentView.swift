import SwiftUI

struct ContentView: View {
    @State private var store = ReminderStore()
    @State private var voice = VoiceRecorder()
    @State private var showVoiceSheet = false
    @State private var parsing = false

    private var active: [Reminder] { store.reminders.filter { !$0.done } }
    private var completed: [Reminder] { store.reminders.filter(\.done) }

    var body: some View {
        NavigationStack {
            List {
                if active.isEmpty && completed.isEmpty {
                    emptyState
                }
                Section {
                    ForEach(active) { reminder in
                        row(reminder)
                    }
                }
                if !completed.isEmpty {
                    Section("Done") {
                        ForEach(completed) { reminder in
                            row(reminder)
                        }
                    }
                }
            }
            .navigationTitle("remindas")
            .safeAreaInset(edge: .bottom) {
                micButton
            }
        }
        .onAppear { store.start() }
        .sheet(isPresented: $showVoiceSheet, onDismiss: { voice.stop() }) {
            voiceSheet
                .presentationDetents([.height(280)])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Hold nothing back — just say it")
                .font(.headline)
            Text("\"Lomedico appointment 9am in Red Bank\" becomes a scheduled, place-aware reminder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .listRowBackground(Color.clear)
    }

    private func row(_ reminder: Reminder) -> some View {
        let isNear = store.nearbyIDs.contains(reminder.id)
        return HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { store.toggle(reminder.id) }
            } label: {
                Image(systemName: reminder.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.done ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .strikethrough(reminder.done)
                    .foregroundStyle(reminder.done ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let due = reminder.due {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    }
                    if let place = reminder.place {
                        Label(place, systemImage: isNear ? "location.fill" : "location")
                            .foregroundStyle(isNear ? Color.green : Color.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isNear && !reminder.done {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .shadow(color: .green, radius: 6)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { store.toggle(reminder.id) }
        }
        .listRowBackground(
            isNear && !reminder.done
                ? RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.12))
                : nil
        )
        .swipeActions {
            Button(role: .destructive) {
                store.delete(reminder.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var micButton: some View {
        Button {
            showVoiceSheet = true
            voice.start()
        } label: {
            Label("Say a reminder", systemImage: "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .padding()
    }

    private var voiceSheet: some View {
        VStack(spacing: 16) {
            Image(systemName: voice.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
                .symbolEffect(.variableColor, isActive: voice.isRecording)
            Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                .font(.title3.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(minHeight: 60)
            if let error = voice.errorText {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Button("Cancel") {
                    voice.stop()
                    showVoiceSheet = false
                }
                .buttonStyle(.bordered)
                Button {
                    saveSpoken()
                } label: {
                    if parsing {
                        ProgressView()
                    } else {
                        Text("Save").bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(voice.transcript.isEmpty || parsing)
            }
        }
        .padding()
    }

    private func saveSpoken() {
        parsing = true
        voice.stop()
        let spoken = voice.transcript
        Task {
            let reminder = await ReminderParser.parse(spoken)
            store.add(reminder)
            parsing = false
            showVoiceSheet = false
        }
    }
}
