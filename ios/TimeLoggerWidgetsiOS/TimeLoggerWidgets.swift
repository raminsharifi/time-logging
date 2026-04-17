import WidgetKit
import SwiftUI

@main
struct TimeLoggerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TimerWidget()
        TimerLiveActivity()
    }
}
