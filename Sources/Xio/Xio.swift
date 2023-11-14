@main
struct Xio {
    static func main() async -> Void {
        print("Async main!")
        let server = Server(address: "0.0.0.0:7050") { clientSocket in
            print("New client needed: \(clientSocket)")
            return Test()
        }
        do {
            let result = try await server.run()
            print("Shutdown reason: \(result)")
        } catch {
            print("\(error)")
        }
    }
}

struct Test: SocketHandler {
    func didRead(bytes: [UInt8]) {
        print("read bytes of length: \(bytes.count)")
    }
}
