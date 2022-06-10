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

class Socket {
    let fd: Int32

    fileprivate init() {
        fd = socket(AF_INET, SOCK_STREAM, 0)
    }
    
    deinit {
        close(fd)
    }

    static func forListening(address: String) -> Socket {
        let socket = Socket()
        socket.bindSocket(to: address)
        socket.startListening()
        socket.setNonBlocking()
        
        return socket
    }
    
    static func connect(to address: String) {
        
    }
    
    // MARK: -
    
    private func startListening() {
        var option = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &option, UInt32(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, TCP_NODELAY, &option, UInt32(MemoryLayout<Int32>.size))
        
        // A sensible backlog, can break on ubuntu if no backlog is provided and the firewall is turned on
        // there was some sysctl option you can set to fix that as well but forgot about it
        let rc = listen(fd, 128)
        guard rc == 0 else {
            if let err = strerror(errno) {
                let str = String(cString: err)
                fatalError("Unable to bind: \(str)")
            }
            fatalError("Unable to bind socket, err \(errno)")
        }
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
    
    private func setNonBlocking() {
        let flags = fcntl(fd, F_GETFL, 0)
        assert(flags != -1)
        // As far as I know fcntl should work the same accross
        // POSIX compliant systems, bsd linux mach etc.
        // no clue whether this is avaliable on windooms, probably not
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
}
