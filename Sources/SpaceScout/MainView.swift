import SwiftUI
import SpaceScoutCore

struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 20) {
                header
                if model.demo {
                    Label("DEMO · Synthetic data. Scanning, cleanup, Open and Finder actions are disabled.", systemImage: "play.rectangle")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.teal).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Theme.mint).cornerRadius(8)
                }
                overview
                ResultsView(model: model)
                footer
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background).foregroundColor(Theme.navy)
        .frame(minWidth: 1040, minHeight: 720)
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.confirming) { confirmation }
        .sheet(item: $model.inspector) { candidate in inspector(candidate) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder.circle.fill").font(.system(size: 31)).foregroundColor(Color(red: 0.32, green: 0.84, blue: 0.72))
                Text("SpaceScout").font(.system(size: 20, weight: .semibold))
            }.padding(.bottom, 15)
            VStack(alignment: .leading, spacing: 8) {
                Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(2).opacity(0.45).padding(.bottom, 5)
                nav("Overview", symbol: "square.grid.2x2", category: nil)
                ForEach(CandidateCategory.allCases, id: \.self) { category in nav(category.label, symbol: category.symbol, category: category) }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "lock.shield").font(.system(size: 24)).foregroundColor(Color(red: 0.32, green: 0.84, blue: 0.72))
                Text("Your files. Your call.").font(.system(size: 14, weight: .semibold))
                Text("Local scans. No uploads.\nModels, skills and projects\nstay protected.").font(.system(size: 12)).lineSpacing(5).opacity(0.65)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.05)).cornerRadius(12)
            Text("PREVIEW  0.1.0").font(.system(size: 10, weight: .medium)).tracking(1.5).opacity(0.4)
        }.padding(22).frame(width: 216).frame(maxHeight: .infinity).background(Theme.navy).foregroundColor(.white)
    }
    private func nav(_ title: String, symbol: String, category: CandidateCategory?) -> some View {
        Button { model.category = category } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).font(.system(size: 13, weight: model.category == category ? .semibold : .regular))
                Spacer()
                if let category { Text("\(model.review.candidates.filter { $0.category == category }.count)").font(.system(size: 11)).opacity(0.55) }
            }.padding(.horizontal, 12).padding(.vertical, 12)
                .background(model.category == category ? .white.opacity(0.12) : .clear).cornerRadius(9)
        }.buttonStyle(.plain).accessibilityLabel("Show \(title)")
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("A little more breathing room.").font(.system(size: 27, weight: .semibold))
                Text("See what’s taking space. Decide what stays.").font(.system(size: 13)).foregroundColor(Theme.secondary)
            }
            Spacer()
            if model.busy && !model.cleaning {
                Button("Cancel scan", action: model.cancel).buttonStyle(.bordered)
            } else {
                Button(action: model.scan) { Label(model.hasScanned ? "Scan again" : "Scan storage", systemImage: "viewfinder").padding(.horizontal, 7).padding(.vertical, 5) }
                    .buttonStyle(.borderedProminent).tint(Theme.teal).disabled(model.demo || model.busy).keyboardShortcut("r", modifiers: .command)
            }
        }
    }
    private var overview: some View {
        HStack(alignment: .top, spacing: 16) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Label("VOLUME STORAGE", systemImage: "internaldrive").font(.system(size: 10, weight: .semibold)).tracking(1); Spacer(); Text(model.demo ? "Sample volume" : "Home volume").font(.system(size: 11)).foregroundColor(Theme.secondary) }
                    if let storage = model.storage {
                        HStack(alignment: .firstTextBaseline, spacing: 6) { Text(bytes(storage.availableBytes)).font(.system(size: 30, weight: .semibold)); Text("available").font(.system(size: 12)).foregroundColor(Theme.secondary) }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.mint)
                                Capsule().fill(Theme.teal).frame(width: proxy.size.width * CGFloat(min(1, max(0, Double(storage.totalBytes - storage.availableBytes) / Double(max(1, storage.totalBytes))))))
                            }
                        }.frame(height: 8).accessibilityLabel("Volume used \(bytes(storage.totalBytes - storage.availableBytes)) out of \(bytes(storage.totalBytes))")
                        HStack { Text("\(bytes(storage.totalBytes - storage.availableBytes)) used"); Spacer(); Text("\(bytes(storage.totalBytes)) total") }.font(.system(size: 11)).foregroundColor(Theme.secondary)
                    } else { Text(model.capacityError == nil ? "Measuring volume…" : "Volume unavailable").font(.title3); Text(model.capacityError ?? "Available capacity is measured independently.").font(.caption).foregroundColor(Theme.secondary) }
                }
            }.frame(maxWidth: .infinity)
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Label("REVIEW BEFORE CLEANUP", systemImage: "checkmark.shield").font(.system(size: 10, weight: .semibold)).tracking(1)
                    Text(model.demo ? "Your choice" : bytes(model.eligibleBytes)).font(.system(size: 30, weight: .semibold)).foregroundColor(Theme.teal)
                    Text(model.demo ? "Explore sample findings below." : "Allocated estimate of eligible items.").font(.system(size: 12)).foregroundColor(Theme.secondary)
                    Text("Nothing is selected automatically.").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.teal)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 265)
        }
    }
    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: model.busy ? "hourglass" : "checkmark.circle").foregroundColor(Theme.teal)
                Text(model.phase).font(.system(size: 11)).lineLimit(1)
                Spacer()
                if model.busy { ProgressView().scaleEffect(0.55).frame(width: 15, height: 15) }
                else if model.hasScanned { Text("\(model.progressCount.formatted()) entries checked").font(.system(size: 11)).foregroundColor(Theme.secondary) }
            }
            if model.busy && !model.cleaning { Text(model.currentPath).font(.system(size: 10)).foregroundColor(Theme.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.selected.count) selected · \(bytes(model.selectedBytes)) allocated").font(.system(size: 12, weight: .semibold))
                    Text("Moving to Trash does not free space until Trash is emptied.").font(.system(size: 10)).foregroundColor(Theme.secondary)
                }
                Spacer()
                Button("Open Trash", action: model.openTrash).disabled(model.demo || model.busy)
                Button(action: model.requestConfirmation) { Label("Review selection", systemImage: "arrow.right").padding(.vertical, 4) }
                    .buttonStyle(.borderedProminent).tint(Theme.teal).disabled(model.demo || model.busy || model.selected.isEmpty)
            }
        }
    }
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Move selected items to Trash?", systemImage: "trash").font(.title2.weight(.semibold))
            Text("\(model.selected.count) exact items · \(model.selectedBytes.formatted()) bytes allocated (\(bytes(model.selectedBytes)))")
            Text("Close the related apps, developer tools and command-line processes first. Every item will be checked again. Changed, protected or incomplete items will be refused.").font(.callout).foregroundColor(Theme.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.selected) { item in
                        VStack(alignment: .leading, spacing: 4) { Text(item.url.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled); Text("\(bytes(item.allocatedBytes)) · \(item.allocatedBytes.formatted()) bytes allocated").font(.caption).foregroundColor(Theme.secondary) }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 230)
            Text("Trash is reversible through Finder. SpaceScout cannot empty Trash. Available space is measured after this operation; allocated estimates are not promised savings.").font(.caption).foregroundColor(Theme.secondary)
            HStack { Spacer(); Button("Cancel") { model.confirming = false }.keyboardShortcut(.cancelAction); Button("Move \(model.selected.count) items to Trash", action: model.trashConfirmed).buttonStyle(.borderedProminent).tint(Theme.teal) }
        }.padding(28).frame(width: 650)
    }
    private func inspector(_ candidate: Candidate) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(candidate.title, systemImage: candidate.category.symbol).font(.title2.weight(.semibold))
            Text(candidate.url.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            HStack { Text("\(bytes(candidate.allocatedBytes)) allocated"); Spacer(); Text(candidate.modifiedAt, style: .date) }.font(.callout)
            Text(candidate.reason)
            if let error = model.actionError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.red).textSelection(.enabled) }
            if case .reviewOnly(let reason) = candidate.eligibility { Label(reason, systemImage: "lock.shield").foregroundColor(Theme.teal) }
            Text("Older timestamps do not prove that an item is unused. AI models, skills and detected projects are protected. Allocation estimates may include shared APFS storage and do not predict free-space gains.").font(.caption).foregroundColor(Theme.secondary)
            HStack { Button("Open") { model.open(candidate) }.disabled(model.demo || model.busy); Button("Reveal in Finder") { model.reveal(candidate) }.disabled(model.demo || model.busy); Spacer(); Button("Done") { model.inspector = nil }.keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 560)
    }
}
