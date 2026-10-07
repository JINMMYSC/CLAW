import ActivityKit
import HamsterKit
import SwiftUI
import WidgetKit

private struct ClawTimelineEntry: TimelineEntry { let date: Date; let summary: String; let taskCount: Int }
private struct ClawTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> ClawTimelineEntry { .init(date: Date(), summary: "CLAW 今日", taskCount: 0) }
  func getSnapshot(in context: Context, completion: @escaping (ClawTimelineEntry) -> Void) { completion(placeholder(in: context)) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<ClawTimelineEntry>) -> Void) {
    let data = UserDefaults(suiteName: "group.7518554")?.data(forKey: "claw_widget_snapshot_v1")
    struct Snapshot: Decodable { let summary: String; let openTaskCount: Int }
    let snapshot = data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    let entry = ClawTimelineEntry(date: Date(), summary: snapshot?.summary ?? "打开 CLAW 查看今日", taskCount: snapshot?.openTaskCount ?? 0)
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
  }
}
private struct ClawWidgetView: View {
  var entry: ClawTimelineEntry
  var body: some View { VStack(alignment: .leading) { Label("CLAW 今日", systemImage: "sparkles").font(.headline); Text(entry.summary).lineLimit(2); Spacer(); Text("\(entry.taskCount) 个待办").font(.caption).foregroundColor(.secondary) }.padding().widgetURL(URL(string: "hamster://clawTalk?today=1")) }
}
private struct ClawTodayWidget: Widget {
  let kind = "ClawTodayWidget"
  var body: some WidgetConfiguration { StaticConfiguration(kind: kind, provider: ClawTimelineProvider()) { ClawWidgetView(entry: $0) }.configurationDisplayName("CLAW 今日").description("查看今日摘要和待办。").supportedFamilies([.systemSmall, .systemMedium]) }
}

@available(iOSApplicationExtension 16.1, *)
private struct ClawActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ClawLiveActivityAttributes.self) { context in
      HStack { Image(systemName: context.attributes.kind == "recording" ? "mic.fill" : "waveform"); Text(context.state.detail); Spacer(); Text("\(context.state.elapsedSeconds)s").monospacedDigit() }.padding()
    } dynamicIsland: { context in
      DynamicIsland { DynamicIslandExpandedRegion(.leading) { Image(systemName: "sparkles") }; DynamicIslandExpandedRegion(.center) { Text(context.state.detail) } } compactLeading: { Image(systemName: "waveform") } compactTrailing: { Text("\(context.state.elapsedSeconds)s") } minimal: { Image(systemName: "sparkles") }
    }
  }
}

@main struct ClawWidgetBundle: WidgetBundle {
  @WidgetBundleBuilder var body: some Widget { ClawTodayWidget(); if #available(iOSApplicationExtension 16.1, *) { ClawActivityWidget() } }
}
