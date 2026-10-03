// Posts one Mac notification under GymTrack's name and icon, for
// install-phone.sh. A notification from osascript always carries Script
// Editor's icon, which reads as something else asking for attention.
//
//   GymTrack Notifier.app/Contents/MacOS/notifier <title> <message>
//
// Exits non-zero when nothing was posted, notifications refused included, so
// the script falls back to osascript rather than staying quiet.
import Foundation
import UserNotifications

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: notifier <title> <message>\n".utf8))
    exit(2)
}

let center = UNUserNotificationCenter.current()
let finished = DispatchSemaphore(value: 0)
var posted = false

center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
    guard granted else {
        finished.signal()
        return
    }
    let content = UNMutableNotificationContent()
    content.title = arguments[0]
    content.body = arguments[1]
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    center.add(request) { error in
        posted = error == nil
        finished.signal()
    }
}

// Long enough to answer the permission prompt the first time it appears.
_ = finished.wait(timeout: .now() + 60)
exit(posted ? 0 : 1)
