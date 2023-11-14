//
//  Server.swift
//  
//
//  Created by Antwan van Houdt on 10/06/2022.
//

import Foundation

typealias NewClientCallback = (_ client: Socket) -> Void

extension SocketHandler {
    func send(bytes: [UInt8]) {}
    func newConnection(socket: Socket) {}
    func didRead(bytes: [UInt8]) {}
}

typealias CreateSocketHandlerCallback = (_ client: Socket) -> SocketHandler

actor Server: SocketHandler {
    private var tasks: [Task<Bool, Error>] = []
    private let socket: Socket
    private let newClientCallback: CreateSocketHandlerCallback

    init(address: String, newClientCallback: @escaping CreateSocketHandlerCallback) {
        socket = Socket.forListening(address: address)
        self.newClientCallback = newClientCallback
    }
    
    func run() async throws -> String {
        info("Starting server…")
        
        let runloop = RunLoop(provider: KQueue()!)

        await runloop.register(selectable: self.socket)
        print("Socket registered")
        while !Task.isCancelled {
            info("task is not cancelled, checking again for new connections")
            while let newSocket = self.socket.acceptNew() {
                print("Accepting new connection")
                newSocket.handler = self.newClientCallback(newSocket)
                await runloop.register(selectable: newSocket)
                print("New socket should be registered as well")
            }
            print("Checking runloop")
            try await runloop.run2()
        }
        
        
//        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
//            guard let kq = KQueue() else {
//                fatalError("Unable to start kqueue polling")
//            }
//            let runloop = RunLoop(provider: kq)
//
//            info("Entering task group")
////            taskGroup.addTask {
////                info("Registering socket to RunLoop")
////                await runloop.register(selectable: self.socket)
////                info("Starting runloop")
////                
////            }
//            taskGroup.addTask {
//                print("Starting?")
//                await runloop.register(selectable: self.socket)
//                print("should be registered :/")
//                while ( Task.isCancelled == false ) {
//                    info("task is not cancelled, checking again for new connections")
//                    let newConnection = try await self.socket.accept()
//                    let handler = self.newClientCallback(newConnection)
//                    print("Handler: \(handler)", handler)
//                    
//                    // TODO: How the fuck do i properly clean this up
//                    print("Never calling the run loop? \(runloop)")
//                    await runloop.register(selectable: newConnection)
//                }
//            }
//            try await runloop.run()
//            try await taskGroup.waitForAll()
//        }
        // await runloop.register(selectable: socket)
        // try await runloop.run()
        return "shutdown"
    }
    
    func shutdown() {
        for task in tasks {
            task.cancel()
        }
    }
    
    // MARK: -
    
    nonisolated func newConnection(socket: Socket) {
        let handler = newClientCallback(socket)
        info("New handler: \(handler)")
    }
}
