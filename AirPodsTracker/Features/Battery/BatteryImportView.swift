import SwiftUI
import PhotosUI
import UIKit
import TrackerCore

@MainActor
struct BatteryImportView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var candidates: [BatteryCandidate] = []
    @State private var assignments: [UUID: BatteryPart] = [:]
    @State private var recognizing = false
    @State private var hasRecognized = false
    @State private var errorMessage: String?
    @State private var draft: BatteryImportDraft?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("选一张包含电量的截图，对照原图选择左耳、右耳和充电盒。识别结果只作候选，最后还可以修改。")
                    PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                        Label(screenshot == nil ? "选择电量截图" : "更换截图", systemImage: "photo")
                    }.disabled(recognizing)
                } footer: {
                    Text("仅访问你选中的图片，在本机识别，图片不会上传或写入记录。")
                }
                if let screenshot {
                    Section("原图") {
                        Image(uiImage: screenshot).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .accessibilityLabel("你选择的原始电量截图，请对照下面的候选内容")
                    }
                }
                if recognizing {
                    Section { ProgressView("正在本机识别…") }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                        Text("仍可直接手动填写电量。").foregroundStyle(.secondary)
                    }
                }
                if hasRecognized && candidates.isEmpty {
                    Section {
                        Text("没有识别到百分比")
                        Text("你可以更换更清晰的截图，或直接手动填写。").foregroundStyle(.secondary)
                    }
                }
                if !candidates.isEmpty {
                    Section {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            candidateRow(candidate, index: index + 1)
                        }
                    } header: {
                        Text("选择要采用的数值")
                    } footer: {
                        Text("同一张图可能含有手机或其他耳机的电量。部件建议不会自动选中，请确认属于当前设备「\(store.device?.name ?? "尚未选择")」。")
                    }
                    if hasDuplicateAssignment {
                        Section { Text("同一部件选中了多个候选。请每个部件只保留一个数值。").foregroundStyle(APStyle.warning) }
                    }
                    Section {
                        Button("带入确认表单") {
                            draft = BatteryImportDraft(left: value(for: .left), right: value(for: .right), caseLevel: value(for: .caseLevel))
                        }
                        .disabled(assignments.isEmpty || hasDuplicateAssignment || store.device == nil)
                    } footer: {
                        Text("截图的读数时间默认未知，不会把导入时间当作读数时间。请在下一页核对后保存。")
                    }
                }
                Section {
                    Button("直接手动填写", systemImage: "square.and.pencil") {
                        draft = BatteryImportDraft(left: nil, right: nil, caseLevel: nil,
                                                   source: screenshot == nil ? .manual : .screenshot)
                    }.disabled(store.device == nil || recognizing)
                    if store.device == nil { Text("请先在设置中建立设备。").foregroundStyle(.secondary) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(APStyle.background)
            .navigationTitle("从截图记录电量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task(id: selectedPhoto) { await recognizeSelection() }
            .sheet(item: $draft) { draft in
                BatteryInputSheet(initialLeft: draft.left, initialRight: draft.right, initialCase: draft.caseLevel,
                                  initialMeasuredAt: nil, source: draft.source)
                    .environmentObject(store)
            }
        }
    }

    private func candidateRow(_ candidate: BatteryCandidate, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("候选 \(index)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(candidate.value.map { "\($0)%" } ?? "数值无效").font(.headline).monospacedDigit()
            }
            Text(candidate.text).font(.callout).textSelection(.enabled)
            Text(position(of: candidate.bounds)).font(.caption).foregroundStyle(.secondary)
            if let part = candidate.part {
                Text("文字建议：\(part.title)，请自行核对").font(.caption).foregroundStyle(.secondary)
            }
            Picker("用于", selection: Binding<BatteryPart?>(get: { assignments[candidate.id] }, set: { assignments[candidate.id] = $0 })) {
                Text("不采用").tag(nil as BatteryPart?)
                ForEach(BatteryPart.allCases) { Text($0.title).tag(Optional($0)) }
            }.disabled(candidate.value == nil)
        }.padding(.vertical, 4)
    }

    private var hasDuplicateAssignment: Bool {
        Set(assignments.values).count != assignments.values.count
    }

    private func value(for part: BatteryPart) -> Int? {
        candidates.first { assignments[$0.id] == part }?.value
    }

    private func position(of bounds: CGRect) -> String {
        let vertical = bounds.midY > 0.66 ? "上部" : (bounds.midY < 0.33 ? "下部" : "中部")
        let horizontal = bounds.midX < 0.33 ? "左侧" : (bounds.midX > 0.66 ? "右侧" : "中央")
        return "原图位置：\(vertical) · \(horizontal)"
    }

    @MainActor
    private func recognizeSelection() async {
        guard let selectedPhoto else { return }
        recognizing = true
        hasRecognized = false
        errorMessage = nil
        candidates = []
        assignments = [:]
        screenshot = nil
        defer { recognizing = false }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw TrackerError("未能读取这张图片，请重新选择。")
            }
            try Task.checkCancellation()
            screenshot = image
            let result = try await BatteryOCRService.recognize(imageData: data)
            try Task.checkCancellation()
            candidates = result
            hasRecognized = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "识别未完成：\(error.localizedDescription)"
        }
    }
}

private struct BatteryImportDraft: Identifiable {
    let id = UUID()
    let left: Int?
    let right: Int?
    let caseLevel: Int?
    var source: BatterySource = .screenshot
}
