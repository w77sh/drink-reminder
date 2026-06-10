//
//  MenuBarView.swift
//  Drink Reminder
//
//  Created by Codex on 2026/3/9.
//

import AppKit
import SwiftUI
import UserNotifications

struct MenuBarView: View {
    @Environment(ReminderManager.self) private var reminderManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status Section
            VStack(alignment: .leading) {
                Label(primaryStatusLine, systemImage: "cup.and.saucer.fill")
                    .font(.headline)
                
                if let secondaryStatusLine {
                    Text(secondaryStatusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let notificationStatusLine {
                    Button(action: {
                        reminderManager.openSystemNotificationSettings()
                    }) {
                        Label(notificationStatusLine, systemImage: "bell.badge.fill")
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Actions Section
            VStack(alignment: .leading, spacing: 4) {
                Button(action: {
                    reminderManager.drinkNow()
                }) {
                    Label("Drink now", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(reminderManager.state.isPausedToday)

                Button(action: {
                    reminderManager.snooze30Minutes()
                }) {
                    Label("Snooze 30 minutes", systemImage: "powersleep")
                }
                .buttonStyle(.plain)
                .disabled(reminderManager.state.isPausedToday)

                Button(action: reminderAction) {
                    Label(reminderActionTitle, systemImage: reminderManager.state.isPausedToday ? "play.circle.fill" : "pause.circle.fill")
                }
                .buttonStyle(.plain)
            }

            Divider()

            // App Management Section
            Button(action: {
                openSettings()
                NSApplication.shared.activate(ignoringOtherApps: true)
            }) {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var primaryStatusLine: String {
        if reminderManager.state.isPausedToday {
            return "Paused today"
        }

        if reminderManager.isOutsideReminderWindow {
            return "Outside reminder window"
        }

        if let nextReminderTime = reminderManager.state.nextReminderTime {
            return "Next reminder: \(TimeUtils.menuDateTimeString(nextReminderTime))"
        }

        return "Next reminder unavailable"
    }

    private var secondaryStatusLine: String? {
        guard !reminderManager.state.isPausedToday else {
            return reminderManager.nextReminderDescription
        }

        guard reminderManager.isOutsideReminderWindow else {
            return nil
        }

        return reminderManager.nextReminderDescription
    }

    private var notificationStatusLine: String? {
        if !reminderManager.settings.enableNotification {
            return "Notifications disabled"
        }

        if reminderManager.notificationAuthorizationStatus == .denied {
            return "Enable notifications in System Settings"
        }

        return nil
    }

    private var reminderActionTitle: String {
        reminderManager.state.isPausedToday ? "Resume reminders" : "Pause today"
    }

    private func reminderAction() {
        if reminderManager.state.isPausedToday {
            reminderManager.resumeReminders()
        } else {
            reminderManager.pauseToday()
        }
    }
}

#Preview {
    MenuBarView()
        .environment(ReminderManager())
}
