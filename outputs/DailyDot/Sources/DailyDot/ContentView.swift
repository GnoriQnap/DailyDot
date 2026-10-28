import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: TaskStore
    @State private var editing = false
    @State private var draft = ""
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
                Button { commit(); controller.togglePin() } label: {
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
            .contentShape(Rectangle()).onTapGesture { commit() }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.tasks) { task in
                            TaskRow(task: task, toggle: { commit(); store.toggle(task.id) }, delete: { commit(); store.delete(task.id) })
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
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 18).padding(.bottom, 12)
                }
                .onChange(of: editing) { value in
                    if value { DispatchQueue.main.async { focused = true; proxy.scrollTo("bottom", anchor: .bottom) } }
                }
            }
            HStack {
                Button { if editing { commit() }; editing = true } label: {
                    Image(systemName: "plus").font(.system(size: 24, weight: .light)).frame(width: 38, height: 38)
                }.buttonStyle(.plain).help("新增待办")
                Spacer()
            }
            .padding(.horizontal, 22).padding(.vertical, 15)
            .background(.white.opacity(0.16))
            .contentShape(Rectangle()).onTapGesture { commit() }
        }
        .foregroundStyle(ink)
        .background {
            if controller.isPinned { Color.white.opacity(0.24) }
            else { Color.white }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.65), lineWidth: 1).allowsHitTesting(false))
        .onChange(of: focused) { value in if !value && editing { commit() } }
        .onReceive(NotificationCenter.default.publisher(for: .dailyDotCommit)) { _ in commit() }
        .onChange(of: store.day) { _ in cancel() }
        .environment(\.colorScheme, .light)
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
    let toggle: () -> Void
    let delete: () -> Void
    @State private var hovered = false
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
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
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            Button(action: delete) { Image(systemName: "trash").font(.system(size: 13)).frame(width: 24, height: 22) }
                .buttonStyle(.plain).opacity(hovered ? 0.65 : 0).disabled(!hovered).help("删除任务")
                .accessibilityLabel("删除 \(task.title)")
        }
        .frame(minHeight: 28, alignment: .top)
        .padding(.horizontal, 10).padding(.vertical, 3.5)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(hovered ? 0.22 : 0)))
        .onHover { hovered = $0 }
    }
}

extension Notification.Name { static let dailyDotCommit = Notification.Name("DailyDot.commit") }
