import SwiftUI
import SpaceScoutCore

struct ResultsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.category?.label ?? "Storage findings").font(.system(size: 17, weight: .semibold))
                    Text("\(model.visibleCandidates.count) items · allocated size estimates").font(.system(size: 11)).foregroundColor(Theme.secondary)
                }
                Spacer()
                HStack { Image(systemName: "magnifyingglass"); TextField("Search findings", text: $model.search).textFieldStyle(.plain) }.padding(8).frame(width: 175).background(Theme.background).cornerRadius(8).accessibilityLabel("Search findings")
                Button { model.largestFirst.toggle() } label: { Label(model.largestFirst ? "Largest first" : "Smallest first", systemImage: "arrow.up.arrow.down") }.font(.system(size: 11)).buttonStyle(.borderless)
            }.padding(18)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let error = model.actionError {
                        HStack(alignment: .top) {
                            Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11)).textSelection(.enabled)
                            Spacer()
                            Button("Dismiss") { model.actionError = nil }
                        }.foregroundColor(.red).padding(14).background(Color.red.opacity(0.04))
                    }
                    if !model.issues.isEmpty {
                        DisclosureGroup("\(model.issues.count) scan issues · coverage is incomplete") {
                            ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 3) { Text(issue.url.path).font(.system(size: 10, design: .monospaced)); Text(issue.message).font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                            }
                        }.font(.system(size: 12)).foregroundColor(.brown).padding(16).background(Color.orange.opacity(0.06))
                    }
                    if !model.outcomes.isEmpty {
                        DisclosureGroup("Cleanup results · \(bytes(model.outcomes.filter { $0.status == .trashed }.reduce(0) { $0 + $1.allocatedBytes })) moved to Trash (not freed)") {
                            ForEach(Array(model.outcomes.enumerated()), id: \.offset) { _, outcome in
                                VStack(alignment: .leading, spacing: 3) { Text("\(outcome.status.rawValue.uppercased()) · \(outcome.url.path)").font(.system(size: 10, design: .monospaced)); Text(outcome.message).font(.caption) }.foregroundColor(outcome.status == .trashed ? Theme.secondary : .red).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                            }
                        }.font(.system(size: 12)).padding(16)
                        let failed = model.outcomes.filter { $0.status != .trashed }
                        if !failed.isEmpty { Label("\(failed.count) items were not moved. Expand cleanup results for exact paths and reasons.", systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundColor(.red).padding(12) }
                    }
                    if model.visibleCandidates.isEmpty { emptyState }
                    else { ForEach(model.visibleCandidates) { item in row(item); Divider().padding(.leading, 65) } }
                }
            }
        }.background(.white).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: model.busy ? "viewfinder" : "internaldrive").font(.system(size: 34, weight: .light)).foregroundColor(Theme.teal)
            Text(model.busy ? "Taking a closer look…" : (model.hasScanned ? "No matching findings" : "Start with a local scan")).font(.system(size: 18, weight: .semibold))
            Text(model.busy ? "Scanning metadata in supported locations. You can cancel at any time." : (model.hasScanned ? "Check your filters and scan issues. Protected or inaccessible locations may not be measured." : "Explore supported caches and Downloads. Your files stay in place until you choose and confirm eligible items.")).font(.system(size: 12)).foregroundColor(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
        }.frame(maxWidth: .infinity).padding(.vertical, 65)
    }
    private func detailReason(_ item: Candidate) -> String {
        if case .reviewOnly(let reason) = item.eligibility { return reason + "\n" + item.reason }
        return item.reason
    }
    private func row(_ item: Candidate) -> some View {
        HStack(spacing: 14) {
            Toggle("Select \(item.title)", isOn: Binding(get: { model.review.selectedIDs.contains(item.id) }, set: { _ in model.toggle(item) }))
                .toggleStyle(.checkbox).labelsHidden().disabled(model.demo || model.busy || !item.isEligible).accessibilityLabel("Select \(item.title)")
            Image(systemName: item.category.symbol).font(.system(size: 19)).foregroundColor(Theme.teal).frame(width: 34, height: 38).background(Theme.mint.opacity(0.65)).cornerRadius(9)
            Button { model.inspector = item } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) { Text(item.title).font(.system(size: 13, weight: .semibold)); if !item.isEligible { Label("Review only", systemImage: "lock").font(.system(size: 9, weight: .medium)).foregroundColor(Theme.secondary) } }
                    Text(item.url.path).font(.system(size: 10)).foregroundColor(Theme.secondary).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help(detailReason(item))
            Text(bytes(item.allocatedBytes)).font(.system(size: 13, weight: .semibold, design: .rounded)).frame(minWidth: 73, alignment: .trailing)
            Button("Open") { model.open(item) }.font(.system(size: 11)).disabled(model.demo || model.busy).accessibilityLabel("Open \(item.title)").help("Open file in its default app, or folder in Finder")
            Button { model.reveal(item) } label: { Image(systemName: "arrow.up.forward.square").foregroundColor(Theme.secondary) }.buttonStyle(.borderless).disabled(model.demo || model.busy).help("Reveal in Finder").accessibilityLabel("Reveal \(item.title) in Finder")
            Button { model.inspector = item } label: { Image(systemName: "info.circle").foregroundColor(Theme.secondary) }.buttonStyle(.borderless).accessibilityLabel("Details for \(item.title)")
        }.padding(.horizontal, 18).padding(.vertical, 15)
    }
}
