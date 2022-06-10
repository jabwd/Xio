@main
struct Xio {
    static func main() async -> Void {
        print("Async main!")
        let socket = Socket.forListening(address: "0.0.0.0:7050")
        guard let kq = KQueue() else {
            fatalError("Unable to set up kqueue")
        }
        let runloop = RunLoop(provider: kq)
        let sel = Selectable(fileDescriptor: socket.fd, eventTypes: [.read, .write])
        let dele = ListeningDelegate()
        await runloop.register(selectable: sel, delegate: dele)
        print("Socket registered, starting runloop")
        do {
            try await runloop.run()
        } catch {
            print("Err: \(error)")
        }
        print("Runloop done")
    }
}

class ListeningDelegate: RunLoopDelegate {
    func event(type eventType: EventType) {
        print("Received eventtype: \(eventType)")
    }
}
