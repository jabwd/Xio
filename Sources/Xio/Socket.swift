//
//  Socket.swift
//  
//
//  Created by Antwan van Houdt on 09/06/2022.
//

import Foundation
import System

public extension sockaddr_in {
    /// Cast to sockaddr
    ///
    /// - Returns: sockaddr
    func asAddr() -> sockaddr {
        var temp = self
        let addr = withUnsafePointer(to: &temp) {
            return UnsafeRawPointer($0)
        }
        return addr.assumingMemoryBound(to: sockaddr.self).pointee
    }
}

typealias AcceptCallback = (_ newSocket: Socket?) -> Void

// TODO: I probably don't need this protocol
protocol SocketHandler {
    func didRead(bytes: [UInt8])
    func send(bytes: [UInt8])
    func newConnection(socket: Socket)
}

public enum SocketError: Error {
    case unknown
}

// TODO: Probably need to be an actor, to prevent a data race on the onAccept callback, for now im just experimenting
class Socket: Selectable {
    let fd: Int32
    let mode: Mode
    var handler: SocketHandler?
    weak var runLoop: RunLoop? = nil
    private var newSockets: [Socket] = []
    
    enum Mode {
        case listening
        case client
    }
    
    var fileDescriptor: Int32 {
        fd
    }
    
    var eventTypes: [EventType] {
        if mode == .listening {
            return [.read]
        }
        return [.read]
    }

    fileprivate init(mode: Mode = .client) {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        self.mode = mode
    }
    
    private init(fd: Int32) {
        self.fd = fd
        self.mode = .client
    }
    
    deinit {
        print("I am closing now \(self)")
        if mode == .client {
            _ = shutdown(fd, Int32(SHUT_RDWR))
        }
        close(fd)
    }

    static func forListening(address: String) -> Socket {
        let socket = Socket(mode: .listening)
        socket.bindSocket(to: address)
        socket.startListening()
        socket.setNonBlocking()
        
        return socket
    }
    
    static func connect(to address: String) {
        fatalError("Not implemented")
    }
    
    // MARK: -
    
    private func startListening() {
        var option = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &option, UInt32(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, TCP_NODELAY, &option, UInt32(MemoryLayout<Int32>.size))
        
        // A sensible backlog, can break on ubuntu if no backlog is provided and the firewall is turned on
        // there was some sysctl option you can set to fix that as well but forgot which one it is
        let rc = listen(fd, 128)
        guard rc == 0 else {
            if let err = strerror(errno) {
                let str = String(cString: err)
                fatalError("Unable to bind: \(str)")
            }
            fatalError("Unable to bind socket, err \(errno)")
        }
    }
    
    public func acceptNew() -> Socket? {
        return newSockets.popLast()
    }
    
    private func accept() -> Socket? {
        print("[ INFO ] Accepting new client")
        let clientFD = Darwin.accept(fd, nil, nil)
        guard clientFD != -1 else {
            print("failed to accept new client \(errno)")
            return nil
        }
        return Socket(fd: clientFD)
    }
    
    private func bindSocket(to address: String) {
        let parts = address.split(separator: ":")
        guard parts.count > 0 else {
            fatalError("Invalid address string")
        }
        let ip = parts[0]
        var port: UInt16 = 7050
        if parts.count > 1 {
            port = UInt16(parts[1]) ?? 7050
        }
        
        var address = sockaddr_in()
        address.sin_family = UInt8(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, String(ip), &address.sin_addr.s_addr)
        
        let rc = withUnsafePointer(to: address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                bind(fd, pointer, UInt32(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard rc == 0 else {
            if let err = strerror(errno) {
                let str = String(cString: err)
                fatalError("Unable to bind: \(str)")
            }
            fatalError("Unable to bind socket, err \(errno)")
        }
    }
    
    // MARK: -
    
    func event(type event: EventType) async {
        switch event {
        case .read:
            if mode == .listening {
                guard let newSocket = accept() else {
                    return
                }
                newSockets.append(newSocket)
                return
            }
            print("Performing read")
            var buff: [UInt8] = [UInt8](repeating: 0, count: 4096)
            let rc = Darwin.read(self.fd, &buff, 4096)
            if rc == 0 {
                print("Socket should be closed")
                await self.runLoop?.deregister(selectable: self)
                return
            }
            let result = buff[0..<rc]
            self.handler?.didRead(bytes: buff)
            print("Read rc: \(rc)")
            break
        case .write:
            print("Can continue writing more data")
            break
        case .except:
            print("Except event recv")
            break
        }
    }
    
    func read() -> [UInt8] {
        return []
    }
    
    func write(bytes: [UInt8]) {
        // TODO: Need a write buffer as we can't push everything in one go through the socket
    }
    
    // MARK: - Socket utils
    
    private func setNonBlocking() {
        let flags = fcntl(fd, F_GETFL, 0)
        assert(flags != -1)
        // As far as I know fcntl should work the same accross
        // POSIX compliant systems, bsd linux mach etc.
        // no clue whether this is avaliable on windooms, probably not
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
}
