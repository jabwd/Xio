//
//  File.swift
//  
//
//  Created by Antwan van Houdt on 10/06/2022.
//

import Foundation

enum EventType {
    case read
    case write
    case except
}

struct Selectable: Hashable {
    let fileDescriptor: Int32
    let eventTypes: [EventType]
}

struct SelectableEvent {
    let fd: Int32
    let eventTypes: [EventType]
}

struct RunLoopTimeout {
    let seconds: Int
    let nanoSeconds: Int
}

protocol RunLoopProvider {
    func run(timeout: RunLoopTimeout?) -> [SelectableEvent]
    func register(selectable: Selectable)
    func deregister(selectable: Selectable)
}

// TODO: Replace this with actor / asyncawait
protocol RunLoopDelegate {
    func event(type: EventType)
}

actor RunLoop {
    let provider: RunLoopProvider
    var selectables: [Selectable: RunLoopDelegate] = [:]

    init(provider: RunLoopProvider) {
        self.provider = provider
    }
    
    // MARK: -
    
    func run() async throws {
        var i = 0
        while ( true ) {
            i += 1
            
            // Stop execution after 10 seconds
            if (i > 10) {
                break
            }
            let events = provider.run(timeout: RunLoopTimeout(seconds: 1, nanoSeconds: 0))
            for event in events {
                let selectable = selectables[event.fd]
                
            }
            print("events: \(events)")
        }
    }
    
    // MARK: -
    
    func register(selectable: Selectable, delegate: RunLoopDelegate) {
        provider.register(selectable: selectable)
        selectables[selectable] = delegate
    }
    
    func deregister(selectable: Selectable) {
        fatalError("Not implemented")
//        selectables.removeAll { sel in
//            sel.fileDescriptor == selectable.fileDescriptor
//        }
    }
}
