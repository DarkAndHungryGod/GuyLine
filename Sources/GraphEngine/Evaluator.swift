import QuantityKernel

extension Graph {
    /// Recompute every node and report each node's value or its failure reason.
    ///
    /// The pass is a single topological sweep:
    /// 1. Order the nodes with Kahn's algorithm. Any nodes left unordered are in
    ///    a cycle and are reported as ``NodeError/cycle``.
    /// 2. Visit nodes in dependency order. For each, gather the values on its
    ///    input ports from upstream outputs, then evaluate.
    ///
    /// Failure is local and propagates downstream: a node with an unwired input,
    /// a failed upstream, or a dimensionally invalid operation produces a
    /// ``NodeError`` and contributes no value, so its dependents fail in turn
    /// with ``NodeError/upstreamFailure``. Nothing escapes as a thrown error.
    public func evaluate() -> GraphResult {
        var values: [OutputEndpoint: Quantity] = [:]
        var errors: [NodeID: NodeError] = [:]

        // Index incoming wires by their target input endpoint.
        var incoming: [InputEndpoint: OutputEndpoint] = [:]
        for edge in edges {
            incoming[edge.target] = edge.source
        }

        let order = topologicalOrder()

        // Nodes excluded from the order are part of (or fed only through) a cycle.
        let ordered = Set(order)
        for id in nodes.keys where !ordered.contains(id) {
            errors[id] = .cycle
        }

        for id in order {
            guard let node = nodes[id] else { continue }

            // Gather one value per input port, recording the first failure.
            var inputValues: [Quantity] = []
            var portFailure: NodeError?
            for port in node.inputs.indices {
                let endpoint = InputEndpoint(id, port)
                guard let source = incoming[endpoint] else {
                    portFailure = .missingInput(port: port)
                    break
                }
                if errors[source.node] != nil {
                    portFailure = .upstreamFailure
                    break
                }
                guard let value = values[source] else {
                    portFailure = .upstreamFailure
                    break
                }
                inputValues.append(value)
            }

            if let portFailure {
                errors[id] = portFailure
                continue
            }

            do {
                let outputs = try node.kind.evaluate(inputs: inputValues)
                for (port, value) in outputs.enumerated() {
                    values[OutputEndpoint(id, port)] = value
                }
            } catch let error as KernelError {
                errors[id] = .kernel(error)
            } catch {
                // The kernel only throws KernelError; this is unreachable in
                // practice but keeps evaluation total.
                errors[id] = .upstreamFailure
            }
        }

        return GraphResult(values: values, errors: errors)
    }

    /// Nodes in dependency order (sources first) via Kahn's algorithm. Nodes
    /// trapped in a cycle are omitted from the returned array.
    func topologicalOrder() -> [NodeID] {
        var indegree: [NodeID: Int] = nodes.keys.reduce(into: [:]) { $0[$1] = 0 }
        var successors: [NodeID: [NodeID]] = [:]
        for edge in edges {
            let from = edge.source.node
            let to = edge.target.node
            successors[from, default: []].append(to)
            indegree[to, default: 0] += 1
        }

        // Seed with every node that has no dependencies. Sorting keeps the order
        // deterministic regardless of dictionary iteration order.
        var ready = indegree.filter { $0.value == 0 }.map(\.key)
        ready.sort { $0.raw.uuidString < $1.raw.uuidString }

        var order: [NodeID] = []
        order.reserveCapacity(nodes.count)
        while let next = ready.first {
            ready.removeFirst()
            order.append(next)
            for successor in successors[next, default: []] {
                indegree[successor, default: 0] -= 1
                if indegree[successor] == 0 {
                    // Insert in sorted position to preserve determinism.
                    let symbol = successor.raw.uuidString
                    let index = ready.firstIndex { $0.raw.uuidString > symbol } ?? ready.count
                    ready.insert(successor, at: index)
                }
            }
        }
        return order
    }
}
