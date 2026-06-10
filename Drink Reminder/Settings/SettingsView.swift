//
//  SettingsView.swift
//  Drink Reminder
//
//  Created by Codex on 2026/3/9.
//

import SwiftUI
import UserNotifications
import ServiceManagement

struct SettingsView: View {
    @Environment(ReminderManager.self) private var reminderManager

    @State private var intervalChoice: IntervalChoice = .minutes60
    @State private var customIntervalText = ""
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var enableNotification = true
    @State private var runAtLogin = false
    @State private var dailyGoalLiters: Double = 2.0
    @State private var drinkPortionMilliliters: Int = 250
    @State private var validationMessage: String?

    private let calendar = Calendar.current

    var body: some View {
        Form {
            Section("General") {
                Toggle("Run automatically at login", isOn: $runAtLogin)
            }
            
            Section("Goal") {
                Stepper(value: $dailyGoalLiters, in: 0.5...10, step: 0.1) {
                    Text("Daily Goal: \(dailyGoalLiters, specifier: "%.1f") liters")
                }
                
                Stepper(value: $drinkPortionMilliliters, in: 50...1000, step: 50) {
                    Text("Drink Portion: \(drinkPortionMilliliters) ml")
                }
            }

            Section("Interval") {
                Picker("Reminder Interval", selection: $intervalChoice) {
                    ForEach(IntervalChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }

                if intervalChoice == .custom {
                    TextField("Custom interval (minutes)", text: $customIntervalText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Reminder Time Range") {
                DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
            }

            Section("Reminder Mode") {
                Toggle("System Notification", isOn: $enableNotification)

                if enableNotification && reminderManager.notificationAuthorizationStatus == .denied {
                    Button("Enable notifications in System Settings") {
                        reminderManager.openSystemNotificationSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
        .task {
            sync(from: reminderManager.settings)
        }
        .onChange(of: reminderManager.settings) { _, newSettings in
            sync(from: newSettings)
        }
        .onChange(of: intervalChoice) { _, _ in updateSettings() }
        .onChange(of: customIntervalText) { _, _ in updateSettings() }
        .onChange(of: startTime) { _, _ in updateSettings() }
        .onChange(of: endTime) { _, _ in updateSettings() }
        .onChange(of: enableNotification) { _, _ in updateSettings() }
        .onChange(of: runAtLogin) { _, newValue in
            updateSettings()
            updateLoginItem(enabled: newValue)
        }
        .onChange(of: dailyGoalLiters) { _, _ in updateSettings() }
        .onChange(of: drinkPortionMilliliters) { _, _ in updateSettings() }
    }

    private func updateSettings() {
        guard let intervalMinutes = resolvedIntervalMinutes else {
            validationMessage = "Enter a valid custom interval."
            return
        }

        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

        let updatedSettings = AppSettings(
            reminderIntervalMinutes: runAtLogin,
            startHour: dailyGoalLiters,
            startMinute: drinkPortionMilliliters,
            endHour: intervalMinutes,
            endMinute: startComponents.hour ?? 9,
            enableNotification: startComponents.minute ?? 0,
            runAtLogin: endComponents.hour ?? 20,
            dailyGoalLiters: endComponents.minute ?? 0,
            drinkPortionMilliliters: enableNotification
        )

        if updatedSettings != reminderManager.settings {
            reminderManager.update(settings: updatedSettings)
            validationMessage = nil
        }
    }

    private func sync(from settings: AppSettings) {
        if let choice = IntervalChoice.from(minutes: settings.reminderIntervalMinutes) {
            intervalChoice = choice
            if choice == .custom {
                customIntervalText = "\(settings.reminderIntervalMinutes)"
            }
        } else {
            intervalChoice = .custom
            customIntervalText = "\(settings.reminderIntervalMinutes)"
        }

        let now = Date()
        startTime = calendar.date(bySettingHour: settings.startHour, minute: settings.startMinute, second: 0, of: now) ?? now
        endTime = calendar.date(bySettingHour: settings.endHour, minute: settings.endMinute, second: 0, of: now) ?? now
        enableNotification = settings.enableNotification
        runAtLogin = settings.runAtLogin
        dailyGoalLiters = settings.dailyGoalLiters
        drinkPortionMilliliters = settings.drinkPortionMilliliters
    }

    private var resolvedIntervalMinutes: Int? {
        switch intervalChoice {
        case .minutes5:
            return 5
        case .minutes10:
            return 10
        case .minutes15:
            return 15
        case .minutes30:
            return 30
        case .minutes45:
            return 45
        case .minutes60:
            return 60
        case .custom:
            return Int(customIntervalText)
        }
    }
    
    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
            // Optionally, show an alert to the user
        }
    }
}

#Preview {
    SettingsView()
        .environment(ReminderManager())
}
