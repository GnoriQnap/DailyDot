import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: TaskStore
    @State private var editing = false
    @State private var draft = ""
    @State private var editingID: UUID?
    @State private var editDraft = ""
    @State private var draggingID: UUID?
    @State private var draggingDay: String?
    @State private var insertion: Int?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var listOrigin: CGFloat = 0
    @FocusState private var focused: Bool
    @ObservedObject var controller: WindowController
    private let ink = Color.black.opacity(0.78)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Date(), format: .dateTime.month(.wide).day().weekday(.wide))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.45))
                        .id(store.day)
                    Text("To-do").font(.system(size: 24, weight: .medium, design: .monospaced))
                }
                Spacer()
                Button { commitAll(); controller.togglePin() } label: {
                    Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.black.opacity(controller.isPinned ? 0.7 : 0.4))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(controller.isPinned ? "取消置顶" : "保持置顶")
                .accessibilityLabel(controller.isPinned ? "取消置顶" : "保持置顶")
                .accessibilityValue(controller.isPinned ? "已开启" : "已关闭")
                Color.clear.frame(width: 32, height: 40)
            }
            .padding(.horizontal, 28).padding(.top, 29).padding(.bottom, 25)
            .contentShape(Rectangle()).onTapGesture { commitAll() }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.tasks) { task in
                            TaskRow(task: task, isEditing: editingID == task.id, isDragging: draggingID == task.id,
                                    draft: $editDraft,
                                    toggle: { commitAll(); store.toggle(task.id) },
                                    delete: { commitAll(); store.delete(task.id) },
                                    beginEditing: { beginEditing(task) },
                                    finishEditing: { finishEdit(task.id, cancel: $0) },
                                    beginDrag: { commitAll(); draggingID = task.id; draggingDay = store.day },
                                    endDrag: { resetDrag() })
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: TaskFramesKey.self, value: [task.id: geo.frame(in: .named("taskList"))])
                                })
                                .onDrop(of: [UTType.text], delegate: TaskDropTarget(
                                    index: store.tasks.firstIndex(where: { $0.id == task.id }) ?? 0,
                                    height: rowFrames[task.id]?.height ?? 35,
                                    valid: draggingID != nil && draggingDay == store.day,
                                    insertion: $insertion, perform: performDrop))
                        }
                        if editing {
                            HStack(spacing: 13) {
                                RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.17), lineWidth: 1.3).frame(width: 20, height: 20)
                                TextField("Add new todo", text: $draft)
                                    .textFieldStyle(.plain).font(.system(size: 14, design: .monospaced))
                                    .focused($focused).onSubmit { commit() }
                                    .onExitCommand { cancel() }
                            }
                            .frame(minHeight: 28)
                            .padding(.horizontal, 10).padding(.vertical, 3.5).id("editor")
                        }
                        if store.tasks.isEmpty && !editing {
                            Text("留一点空间，给今天。")
                                .font(.system(size: 14, design: .monospaced)).foregroundStyle(.black.opacity(0.28))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16).padding(.leading, 10)
                        }
                        Color.clear.frame(height: 20).id("bottom")
                    }
                    // Keep the first insertion marker inside the scroll clipping area.
                    .padding(.top, 6)
                    .coordinateSpace(name: "taskList")
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: TaskListOriginKey.self, value: geo.frame(in: .named("taskViewport")).minY)
                    })
                    .onPreferenceChange(TaskListOriginKey.self) { listOrigin = $0 }
                    .onPreferenceChange(TaskFramesKey.self) { rowFrames = $0 }
                    .overlay(alignment: .topLeading) {
                        if draggingID != nil, let y = indicatorY {
                            Capsule().fill(Color.gray.opacity(0.5)).frame(height: 2)
                                .offset(y: y)
                                .animation(.easeInOut(duration: 0.12), value: y)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 12)
                }
                .onDrop(of: [UTType.text], delegate: TaskDropTarget(
                    index: store.tasks.count, height: 0, resolveSlot: { point in nearestSlot(at: point.y - listOrigin) }, clearOnExit: true,
                    valid: draggingID != nil && draggingDay == store.day,
                    insertion: $insertion, perform: performDrop))
                .coordinateSpace(name: "taskViewport")
                .onChange(of: editing) { value in
                    if value { DispatchQueue.main.async { focused = true; proxy.scrollTo("bottom", anchor: .bottom) } }
                }
            }
            HStack {
                Button { commitAll(); editing = true } label: {
                    Image(systemName: "plus").font(.system(size: 24, weight: .light)).frame(width: 38, height: 38)
                }.buttonStyle(.plain).help("新增待办")
                Spacer()
            }
            .padding(.horizontal, 22).padding(.vertical, 15)
            .background(.white.opacity(0.16))
            .contentShape(Rectangle()).onTapGesture { commitAll() }
        }
        .foregroundStyle(ink)
        .background {
            if controller.isPinned { Color.white.opacity(0.24) }
            else { Color.white }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.65), lineWidth: 1).allowsHitTesting(false))
        .onChange(of: focused) { value in if !value && editing { commit() } }
        .onReceive(NotificationCenter.default.publisher(for: .dailyDotCommit)) { _ in commitAll() }
        .onChange(of: store.day) { _ in cancel(); editingID = nil; resetDrag() }
        .environment(\.colorScheme, .light)
    }

    private var indicatorY: CGFloat? {
        guard let insertion, !store.tasks.isEmpty else { return nil }
        if insertion == 0 {
            return rowFrames[store.tasks[0].id].map { max(1, $0.minY - 3.5) }
        }
        if insertion >= store.tasks.count {
            return rowFrames[store.tasks.last!.id].map { $0.maxY + 1.5 }
        }
        return rowFrames[store.tasks[max(0, insertion)].id].map { $0.minY - 3.5 }
    }
    private func nearestSlot(at y: CGFloat) -> Int {
        for (index, task) in store.tasks.enumerated() {
            if let frame = rowFrames[task.id], y < frame.midY { return index }
        }
        return store.tasks.count
    }
    private func resetDrag() { draggingID = nil; draggingDay = nil; insertion = nil }
    private func performDrop() -> Bool {
        guard let id = draggingID, draggingDay == store.day, let insertion else { resetDrag(); return false }
        withAnimation(.easeInOut(duration: 0.18)) { store.move(id, toInsertionIndex: insertion) }
        resetDrag()
        return true
    }
    private func beginEditing(_ task: TodoTask) {
        commitAll()
        editDraft = task.title
        editingID = task.id
    }
    private func finishEdit(_ id: UUID, cancel: Bool) {
        guard editingID == id else { return }
        let value = editDraft
        editingID = nil; editDraft = ""
        if !cancel { store.rename(id, title: value) }
    }
    private func commitAll() {
        commit()
        if let id = editingID { finishEdit(id, cancel: false) }
    }
    private func commit() {
        guard editing else { return }
        let value = draft
        editing = false; draft = ""; focused = false
        store.add(value)
    }
    private func cancel() { editing = false; draft = ""; focused = false }
}

private struct TaskRow: View {
    let task: TodoTask
    let isEditing: Bool
    let isDragging: Bool
    @Binding var draft: String
    let toggle: () -> Void
    let delete: () -> Void
    let beginEditing: () -> Void
    let finishEditing: (Bool) -> Void
    let beginDrag: () -> Void
    let endDrag: () -> Void
    @State private var hovered = false

    private var dragSurface: some View {
        TaskDragSurface(task: task, beginEditing: beginEditing, beginDrag: beginDrag, endDrag: endDrag, hoverChanged: { hovered = $0 })
    }
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.gray.opacity(0.65))
                .frame(width: 10, height: 28)
                .opacity(hovered && !isEditing ? 1 : 0)
                .overlay { if !isEditing { dragSurface } }
                .help("拖动排序")
            Button(action: toggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).stroke(task.isCompleted ? Color.black.opacity(0.32) : .black.opacity(0.27), lineWidth: 1.3)
                    if task.isCompleted { Image(systemName: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.gray.opacity(0.65)) }
                }.frame(width: 20, height: 20)
                    .padding(4).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(task.isCompleted ? "标记为未完成" : "完成任务")
            Text(task.title).font(.system(size: 14, design: .monospaced))
                .strikethrough(task.isCompleted, color: Color.gray.opacity(0.55))
                .foregroundStyle(task.isCompleted ? Color.gray.opacity(0.55) : Color.black.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isEditing ? 0 : 1)
                .overlay(alignment: .leading) {
                    if isEditing {
                        InlineTaskEditor(text: $draft, finish: finishEditing)
                            .background {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white.opacity(0.96))
                                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.14), lineWidth: 1))
                                    .padding(.horizontal, -5).padding(.vertical, -4)
                                    .allowsHitTesting(false)
                            }
                    } else { dragSurface }
                }
            Button(action: delete) { Image(systemName: "trash").font(.system(size: 13)).frame(width: 24, height: 22) }
                .buttonStyle(.plain).opacity(hovered ? 0.65 : 0).disabled(!hovered).help("删除任务")
                .accessibilityLabel("删除 \(task.title)")
        }
        .frame(minHeight: 28, alignment: .top)
        .padding(.horizontal, 10).padding(.vertical, 3.5)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(hovered ? 0.85 : 0)))
        .shadow(color: .black.opacity(hovered && !isEditing ? 0.08 : 0), radius: 3, y: 1)
        .offset(y: hovered && !isEditing ? -1 : 0)
        .opacity(isDragging ? 0.25 : 1)
        .animation(.easeInOut(duration: 0.14), value: hovered)
        .onHover { hovered = $0 }
    }
}

private struct TaskFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TaskListOriginKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TaskDropTarget: DropDelegate {
    let index: Int
    let height: CGFloat
    var resolveSlot: ((CGPoint) -> Int)? = nil
    var clearOnExit = false
    let valid: Bool
    @Binding var insertion: Int?
    let perform: () -> Bool
    func validateDrop(info: DropInfo) -> Bool { valid }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard valid else { return DropProposal(operation: .cancel) }
        update(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { if clearOnExit { insertion = nil } }
    func performDrop(info: DropInfo) -> Bool { update(info); return valid && perform() }
    private func slot(_ info: DropInfo) -> Int { resolveSlot?(info.location) ?? (index + (height > 0 && info.location.y > height / 2 ? 1 : 0)) }
    private func update(_ info: DropInfo) { if valid { insertion = slot(info) } }
}

extension Notification.Name { static let dailyDotCommit = Notification.Name("DailyDot.commit") }
