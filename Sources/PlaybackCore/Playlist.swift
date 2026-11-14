import Foundation

public struct Playlist {
    public private(set) var order: [UUID] = []
    public private(set) var position = 0
    public init() {}
    public var current: UUID? { order.indices.contains(position) ? order[position] : nil }
    public mutating func reset(_ ids: [UUID], shuffle: Bool, keeping: UUID? = nil) {
        order = shuffle ? ids.shuffled() : ids
        if let keeping, let index = order.firstIndex(of: keeping) {
            if shuffle { order.swapAt(0, index); position = 0 }
            else { position = index }
        } else { position = 0 }
    }
    public mutating func advance(loop: Bool, shuffle: Bool) -> UUID? {
        guard !order.isEmpty else { return nil }
        if position + 1 < order.count { position += 1; return current }
        guard loop else { return nil }
        let previous = current
        if shuffle {
            order.shuffle()
            if order.count > 1, order.first == previous { order.swapAt(0, 1) }
        }
        position = 0
        return current
    }
    public mutating func previous() -> UUID? {
        guard !order.isEmpty else { return nil }
        position = max(0, position - 1)
        return current
    }
    public mutating func select(_ id: UUID) {
        if let index = order.firstIndex(of: id) { position = index }
    }
}
