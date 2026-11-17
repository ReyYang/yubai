import SwiftUI
import YubaiCore

private struct DeferredGeometryChange<Value: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> Value
    let action: (Value) -> Void
    @State private var publication = DeferredLayoutValue<Value>()
    func body(content: Content) -> some View {
        content.onGeometryChange(for: Value.self, of: transform) { value in
            publication.submit(value, apply: action)
        }.onDisappear { publication.cancel() }
    }
}

private struct DeferredPreferenceChange<Key: PreferenceKey>: ViewModifier where Key.Value: Equatable {
    let action: (Key.Value) -> Void
    @State private var publication = DeferredLayoutValue<Key.Value>()
    func body(content: Content) -> some View {
        content.onPreferenceChange(Key.self) { value in
            publication.submit(value, apply: action)
        }.onDisappear { publication.cancel() }
    }
}

extension View {
    func deferredGeometryChange<Value: Equatable>(for type: Value.Type, of transform: @escaping (GeometryProxy) -> Value,
                                                 action: @escaping (Value) -> Void) -> some View {
        modifier(DeferredGeometryChange(transform: transform, action: action))
    }
    func deferredPreferenceChange<Key: PreferenceKey>(_ key: Key.Type, action: @escaping (Key.Value) -> Void) -> some View where Key.Value: Equatable {
        modifier(DeferredPreferenceChange<Key>(action: action))
    }
}

#if os(iOS)
private struct DeferredScrollGeometryChange<Value: Equatable>: ViewModifier {
    let transform: (ScrollGeometry) -> Value
    let action: (Value) -> Void
    @State private var publication = DeferredLayoutValue<Value>()
    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Value.self, of: transform) { _, value in
            publication.submit(value, apply: action)
        }.onDisappear { publication.cancel() }
    }
}

extension View {
    func deferredScrollGeometryChange<Value: Equatable>(for type: Value.Type, of transform: @escaping (ScrollGeometry) -> Value,
                                                       action: @escaping (Value) -> Void) -> some View {
        modifier(DeferredScrollGeometryChange(transform: transform, action: action))
    }
}
#endif
