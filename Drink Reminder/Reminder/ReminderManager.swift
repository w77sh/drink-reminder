//
//  ReminderManager.swift
//  Drink Reminder
//
//  Created by Codex on 2026/3/9.
//

import AppKit
import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class ReminderManager {
    var settings: AppSettings
    var state: ReminderState
    private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    private let settingsStore: SettingsStore
    private let notificationManager: NotificationManager
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private let calendar: Calendar
    private var hasStarted = false

    init(
        settingsStore: SettingsStore? = nil,
        notificationManager: NotificationManager? = nil,
        calendar: Calendar = .current
    ) {
        let resolvedSettingsStore = settingsStore ?? SettingsStore()
        let resolvedNotificationManager = notificationManager ?? NotificationManager()

        self.settingsStore = resolvedSettingsStore
        self.notificationManager = resolvedNotificationManager
        self.calendar = calendar

        let loadedSettings = resolvedSettingsStore.load()
        switch ReminderScheduler.validate(settings: loadedSettings) {
        case .valid:
            settings = loadedSettings
        case .invalid:
            settings = .default
            resolvedSettingsStore.save(.default)
        }

        state = ReminderState(lastProcessedDay: TimeUtils.startOfDay(for: Date(), calendar: calendar))
        start()
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        recalculateNextReminder(now: Date(), clearExistingSchedule: true)
        startTimer()
        observeWakeNotifications()

        Task {
            await refreshNotificationAuthorizationStatus(requestIfNeeded: false)
        }
    }

    func requestNotificationAuthorizationOnLaunchIfNeeded() async {
        guard settings.enableNotification && allowsAuthorizationPrompts else {
            await refreshNotificationAuthorizationStatus(requestIfNeeded: false)
            return
        }

        await refreshNotificationAuthorizationStatus(requestIfNeeded: true)
    }

    func openSystemNotificationSettings() {
        notificationManager.openSystemNotificationSettings()
    }

    func handleTimerTick() {
        handleTimerTick(now: Date())
    }

    func drinkNow() {
        drinkNow(now: Date())
    }

    func drinkNow(now: Date) {
        state.lastProcessedDay = TimeUtils.startOfDay(for: now, calendar: calendar)
        state.lastDrinkTime = now
        state.snoozedUntil = nil
        state.isPausedToday = false
        state.nextReminderTime = nil
        recalculateNextReminder(now: now)
    }

    func snooze30Minutes() {
        snooze30Minutes(now: Date())
    }

    func snooze30Minutes(now: Date) {
        state.snoozedUntil = now.addingTimeInterval(30 * 60)
        recalculateNextReminder(now: now)
    }

    func pauseToday() {
        pauseToday(now: Date())
    }

    func pauseToday(now: Date) {
        state.lastProcessedDay = TimeUtils.startOfDay(for: now, calendar: calendar)
        state.isPausedToday = true
        state.nextReminderTime = nil
        state.snoozedUntil = nil
    }

    func resumeReminders() {
        resumeReminders(now: Date())
    }

    func resumeReminders(now: Date) {
        state.lastProcessedDay = TimeUtils.startOfDay(for: now, calendar: calendar)
        state.isPausedToday = false
        state.nextReminderTime = nil
        state.snoozedUntil = nil
        recalculateNextReminder(now: now)
    }

    func updateSettings(_ newSettings: AppSettings) -> ValidationResult {
        let validation = ReminderScheduler.validate(settings: newSettings)
        guard case .valid = validation else {
            return validation
        }

        settings = newSettings
        settingsStore.save(newSettings)
        state.nextReminderTime = nil
        state.snoozedUntil = nil
        recalculateNextReminder(now: Date(), clearExistingSchedule: true)

        Task {
            await refreshNotificationAuthorizationStatus(
                requestIfNeeded: newSettings.enableNotification && allowsAuthorizationPrompts
            )
        }

        return .valid
    }

    func update(settings: AppSettings) {
        self.settings = settings
        settingsStore.save(settings)
        recalculateNextReminder(now: Date())
    }

    func pauseOrResume() {
        pauseOrResume(now: Date())
    }

    var isOutsideReminderWindow: Bool {
        !state.isPausedToday && !ReminderScheduler.isWithinReminderWindow(now: Date(), settings: settings, calendar: calendar)
    }

    var shouldUsePausedMenuBarIcon: Bool {
        state.isPausedToday || state.snoozedUntil != nil
    }

    var nextReminderDescription: String? {
        guard let nextReminderTime = state.nextReminderTime else {
            return nil
        }

        return "Next reminder: \(TimeUtils.menuDateTimeString(nextReminderTime, calendar: calendar))"
    }

    private func handleTimerTick(now: Date) {
        resetDailyStateIfNeeded(now: now)

        guard let nextReminderTime = state.nextReminderTime else {
            recalculateNextReminder(now: now)
            return
        }

        guard now >= nextReminderTime else {
            return
        }

        triggerReminder(now: now)
    }

    private func triggerReminder(now: Date) {
        state.snoozedUntil = nil
        state.nextReminderTime = ReminderScheduler.nextReminderAfterTrigger(
            now: now,
            settings: settings,
            calendar: calendar
        )

        guard settings.enableNotification else {
            return
        }

        Task {
            if notificationAuthorizationStatus != .authorized {
                await refreshNotificationAuthorizationStatus(requestIfNeeded: true)
            }

            guard notificationAuthorizationStatus == .authorized else {
                return
            }

            await notificationManager.sendReminder()
        }
    }

    private func recalculateNextReminder(now: Date, clearExistingSchedule: Bool = false) {
        resetDailyStateIfNeeded(now: now)

        if clearExistingSchedule {
            state.nextReminderTime = nil
        }

        state.nextReminderTime = ReminderScheduler.calculateNextReminder(
            now: now,
            state: state,
            settings: settings,
            calendar: calendar
        )
    }

    private func resetDailyStateIfNeeded(now: Date) {
        let currentDay = TimeUtils.startOfDay(for: now, calendar: calendar)

        guard let lastProcessedDay = state.lastProcessedDay else {
            state.lastProcessedDay = currentDay
            return
        }

        guard !calendar.isDate(lastProcessedDay, inSameDayAs: currentDay) else {
            return
        }

        state.lastDrinkTime = nil
        state.nextReminderTime = nil
        state.isPausedToday = false
        state.snoozedUntil = nil
        state.lastProcessedDay = currentDay
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimerTick()
            }
        }
        timer?.tolerance = 5
    }

    private func observeWakeNotifications() {
        guard wakeObserver == nil else {
            return
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recalculateNextReminder(now: Date())
            }
        }
    }

    private func refreshNotificationAuthorizationStatus(requestIfNeeded: Bool) async {
        let status: UNAuthorizationStatus
        if requestIfNeeded {
            status = await notificationManager.requestAuthorizationIfNeeded()
        } else {
            status = await notificationManager.authorizationStatus()
        }

        notificationAuthorizationStatus = status
    }

    private var allowsAuthorizationPrompts: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] == nil
            && environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
    }
}
