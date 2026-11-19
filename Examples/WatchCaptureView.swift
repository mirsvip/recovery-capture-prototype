// Add to a watchOS app target that depends on both package libraries.
#if os(watchOS)
import SwiftUI
import WatchKit
import RecoveryCore
import RecoveryWatchTransport

@MainActor
struct WatchCaptureView: View {
    let bridge: WatchConnectivityBridge
    let habitID: UUID
    // Persist this installation identifier; do not generate it for every tap.
    let deviceID: String
    @State private var status = ""

    var body: some View {
        VStack {
            Button("Log completion") {
                do {
                    try bridge.capture(CapturePayload(
                        habitID: habitID, sourceDeviceID: deviceID
                    ))
                    WKInterfaceDevice.current().play(.success)
                    status = "Saved on Watch"
                } catch {
                    status = "Could not save. Please try again."
                }
            }
            Text(status).font(.footnote)
        }
        .onAppear { bridge.start() }
        .onOpenURL { _ in bridge.flushOutbox() }
    }
}
#endif
