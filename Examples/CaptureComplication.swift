// Add to a separate watchOS Widget Extension target.
#if os(watchOS)
import SwiftUI
import WidgetKit

private struct CaptureEntry: TimelineEntry { let date: Date }

private struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry { CaptureEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        // The capture launcher is static. It needs no polling or network calls.
        completion(Timeline(entries: [CaptureEntry(date: Date())], policy: .never))
    }
}

struct CaptureComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecoveryCapture", provider: CaptureProvider()) { _ in
            Image(systemName: "plus.circle.fill")
                .accessibilityLabel("Capture a completion")
                .widgetURL(URL(string: "recoverycapture://capture"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick capture")
        .description("Open the app to log a completion.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
#endif
