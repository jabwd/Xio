//
//  File.swift
//  
//
//  Created by Antwan van Houdt on 10/06/2022.
//

import Foundation

enum RunLoopProviderError: Error {
    case failed
}

enum EventType {
    case read
    case write
    case except
}

protocol Selectable {
    var fileDescriptor: Int32 { get }
    var eventTypes: [EventType] { get }
    
    func event(type: EventType) async
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
    func run(timeout: RunLoopTimeout?) throws -> [SelectableEvent]
    func register(selectable: Selectable)
    func deregister(selectable: Selectable)
}

// TODO: Replace this with actor / asyncawait
protocol RunLoopDelegate {
    func event(type: EventType)
}

enum RunLoopError: Error {
    case unknownFD
}

actor RunLoop {
    let provider: RunLoopProvider
    var selectables: [Int32: Selectable] = [:]

    init(provider: RunLoopProvider) {
        self.provider = provider
    }
    
    // MARK: -
    
    func run() async throws {
        var i = 0
        while ( true ) {
            i += 1
            
            if Task.isCancelled {
                break
            }
            
            // Stop execution after 10 seconds
            if (i > 10) {
                break
            }
            let events = try provider.run(timeout: RunLoopTimeout(seconds: 10, nanoSeconds: 0))
            for event in events {
                guard let selectable = selectables[event.fd] else {
                    throw RunLoopError.unknownFD
                }
                for eventType in event.eventTypes {
                    await selectable.event(type: eventType)
                }
            }
        }
    }
    
    func run2() async throws {
        let events = try provider.run(timeout: RunLoopTimeout(seconds: 10, nanoSeconds: 0))
        for event in events {
            guard let selectable = selectables[event.fd] else {
                throw RunLoopError.unknownFD
            }
            for eventType in event.eventTypes {
                await selectable.event(type: eventType)
            }
        }
    }
    
    // MARK: -
    
    func register(selectable: Selectable) {
        print("Should register with run loop?")
        provider.register(selectable: selectable)
        selectables[selectable.fileDescriptor] = selectable
    }
    
    func deregister(selectable: Selectable) {
        provider.deregister(selectable: selectable)
        selectables.removeValue(forKey: selectable.fileDescriptor)
    }
}
