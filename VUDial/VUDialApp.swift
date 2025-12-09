//
//  VUDialApp.swift
//  VUDial
//
//  Created by Marco Luthi on 08.11.2025.
//

import SwiftUI
import SwiftData

@main
struct VUDialApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Dial.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 900, height: 600)
    }
}
