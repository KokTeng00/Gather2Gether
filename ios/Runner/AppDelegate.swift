import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.gather2gether/share",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak controller] call, result in
        guard call.method == "shareText" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let arguments = call.arguments as? [String: Any],
          let text = arguments["text"] as? String,
          !text.isEmpty
        else {
          result(FlutterError(
            code: "invalid_share",
            message: "Share text is empty.",
            details: nil
          ))
          return
        }
        let share = UIActivityViewController(
          activityItems: [text],
          applicationActivities: nil
        )
        if let popover = share.popoverPresentationController,
           let view = controller?.view {
          popover.sourceView = view
          popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        controller?.present(share, animated: true)
        result(true)
      }
      let reminders = FlutterMethodChannel(
        name: "com.gather2gether/reminders",
        binaryMessenger: controller.binaryMessenger
      )
      reminders.setMethodCallHandler { call, result in
        guard
          let arguments = call.arguments as? [String: Any],
          let id = (arguments["id"] as? NSNumber)?.intValue
        else {
          result(FlutterError(code: "invalid_reminder", message: "Reminder id is missing.", details: nil))
          return
        }
        let center = UNUserNotificationCenter.current()
        let identifier = "event-\(id)"
        if call.method == "cancel" {
          center.removePendingNotificationRequests(withIdentifiers: [identifier])
          result(true)
          return
        }
        guard
          call.method == "schedule",
          let epoch = (arguments["at"] as? NSNumber)?.int64Value,
          let title = arguments["title"] as? String,
          let body = arguments["body"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        let date = Date(timeIntervalSince1970: TimeInterval(epoch) / 1000)
        guard date > Date() else {
          result(FlutterError(code: "invalid_reminder", message: "Reminder time is in the past.", details: nil))
          return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          guard granted, error == nil else {
            DispatchQueue.main.async { result(false) }
            return
          }
          let content = UNMutableNotificationContent()
          content.title = title
          content.body = body
          content.sound = .default
          if let eventId = arguments["eventId"] as? String {
            content.userInfo = ["eventId": eventId]
          }
          let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
          )
          let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
          )
          center.add(request) { scheduleError in
            DispatchQueue.main.async { result(scheduleError == nil) }
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
