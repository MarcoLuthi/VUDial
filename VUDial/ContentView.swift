//
//  ContentView.swift
//  VUDial
//
//  Created by Marco Luthi on 08.11.2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext

    // MARK: - Managers
    @StateObject private var serialManager = SerialPortManager()
    @State private var dialManager: DialManager?

    // MARK: - Selection
    @State private var selectedDial: Dial?

    // MARK: - Error Handling
    @State private var showingError = false
    @State private var errorMessage = ""

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            if let dialManager {
                DialDiscoveryView(
                    dialManager: dialManager,
                    serialManager: serialManager,
                    selectedDial: $selectedDial
                )
            } else {
                ProgressView("Initializing...")
            }
        } detail: {
            if let dialManager, let selectedDial {
                DialControlView(
                    dial: selectedDial,
                    dialManager: dialManager
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "dial.medium.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("Select a dial to control")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Initialize DialManager with model context
            if dialManager == nil {
                dialManager = DialManager(
                    serialManager: serialManager,
                    modelContext: modelContext
                )
            }
        }
        .onChange(of: dialManager?.lastError) { oldValue, newValue in
            if let error = newValue {
                errorMessage = error
                showingError = true
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                dialManager?.lastError = nil
            }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Dial.self, configurations: config)

    // Add sample dial
    let dial = Dial(
        uid: "ABC123",
        name: "Test Dial",
        index: 0,
        currentValue: 50
    )
    container.mainContext.insert(dial)

    return ContentView()
        .modelContainer(container)
}
