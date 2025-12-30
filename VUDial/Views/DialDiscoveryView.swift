//
//  DialDiscoveryView.swift
//  VUDial
//
//  Created by Claude Code on 08.11.2025.
//

import SwiftUI
import SwiftData

struct DialDiscoveryView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dial.index) private var dials: [Dial]

    // MARK: - Properties
    @ObservedObject var dialManager: DialManager
    @ObservedObject var serialManager: SerialPortManager
    @Binding var selectedDial: Dial?

    @State private var editingDial: Dial?
    @State private var newName: String = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Connection Status Bar
            connectionStatusBar

            // Dial List
            if dials.isEmpty {
                emptyState
            } else {
                dialList
            }
        }
        .navigationTitle("VUDials")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: scanForDials) {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(!serialManager.isConnected || dialManager.isScanning)
            }

            ToolbarItem(placement: .automatic) {
                Button(action: toggleConnection) {
                    Label(
                        serialManager.isConnected ? "Disconnect" : "Connect",
                        systemImage: serialManager.isConnected ? "bolt.slash" : "bolt"
                    )
                }
            }
        }
        .sheet(item: $editingDial) { dial in
            renameDialSheet(for: dial)
        }
    }

    // MARK: - Subviews

    private var connectionStatusBar: some View {
        HStack {
            Circle()
                .fill(serialManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(serialManager.connectionStatus)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if dialManager.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Scanning...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dial.medium")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Dials Found")
                .font(.title2)
                .fontWeight(.semibold)

            Text(serialManager.isConnected
                 ? "Click 'Scan' to discover VUDials on the I2C bus"
                 : "Connect to VU Hub to begin")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if !serialManager.isConnected {
                Button(action: toggleConnection) {
                    Label("Connect to VU Hub", systemImage: "bolt")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: scanForDials) {
                    Label("Scan for Dials", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(dialManager.isScanning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var dialList: some View {
        List {
            ForEach(dials) { dial in
                DialRow(dial: dial)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDial = dial
                    }
                    .listRowBackground(
                        selectedDial?.uid == dial.uid ?
                            Color.accentColor.opacity(0.2) : Color.clear
                    )
                    .contextMenu {
                        Button("Rename") {
                            editingDial = dial
                            newName = dial.name
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            deleteDial(dial)
                        }
                    }
            }
        }
    }

    private func renameDialSheet(for dial: Dial) -> some View {
        VStack(spacing: 20) {
            Text("Rename Dial")
                .font(.headline)

            TextField("Dial Name", text: $newName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    editingDial = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    dial.name = newName
                    try? modelContext.save()
                    editingDial = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Methods

    private func toggleConnection() {
        if serialManager.isConnected {
            dialManager.disconnect()
        } else {
            _ = dialManager.connect()
        }
    }

    private func scanForDials() {
        Task {
            await dialManager.scanForDials()
        }
    }

    private func deleteDial(_ dial: Dial) {
        withAnimation {
            modelContext.delete(dial)
            try? modelContext.save()
        }
    }
}

// MARK: - Dial Row

struct DialRow: View {
    let dial: Dial

    var body: some View {
        HStack {
                // Status indicator
                Circle()
                    .fill(dial.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dial.name)
                        .font(.headline)

                    HStack {
                        Text("Index \(dial.index)")
                        Text("•")
                        Text("\(Int(dial.currentValue))%")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Color preview
                if dial.red > 0 || dial.green > 0 || dial.blue > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(
                            red: dial.red / 100.0,
                            green: dial.green / 100.0,
                            blue: dial.blue / 100.0
                        ))
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Dial.self, configurations: config)

    // Add sample dials
    let dial1 = Dial(uid: "ABC123", name: "CPU Usage", index: 0, currentValue: 45)
    let dial2 = Dial(uid: "DEF456", name: "Memory", index: 1, currentValue: 78)
    dial1.setBacklight(red: 80, green: 20, blue: 10)

    container.mainContext.insert(dial1)
    container.mainContext.insert(dial2)

    let serialManager = SerialPortManager()
    let dialManager = DialManager(serialManager: serialManager, modelContext: container.mainContext)

    return NavigationStack {
        DialDiscoveryView(
            dialManager: dialManager,
            serialManager: serialManager,
            selectedDial: .constant(nil)
        )
    }
    .modelContainer(container)
}
