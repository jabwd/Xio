//
//  kqueue.swift
//  
//
//  Created by Antwan van Houdt on 09/06/2022.
//

import Foundation
import System

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
private let sysKevent = kevent

class KQueue: RunLoopProvider {
    let kq: Int32
    
    var events: UnsafeMutablePointer<kevent>
    let eventCapacity: Int = 64

    init?() {
        events = UnsafeMutablePointer<kevent>.allocate(capacity: eventCapacity)
        events.initialize(to: kevent())
        kq = kqueue()
        if kq == -1 {
            return nil
        }
    }
    
    deinit {
        close(kq)
    }
    
    // MARK: -
    
    func run(timeout: RunLoopTimeout? = nil) throws -> [SelectableEvent] {
        var ready: Int32 = 0
        if let timeout = timeout {
            var t = timeout.toKTimespec
            ready = kevent(kq, nil, 0, events, Int32(eventCapacity), &t)
        } else {
            ready = kevent(kq, nil, 0, events, Int32(eventCapacity), nil)
        }
        
        guard ready != -1 else {
            // I don't actually know what to call this error yet lmao
            throw RunLoopProviderError.failed
        }
        if ready > 0 {
            print("Events ready: \(ready)")
            var result: [Int32: [EventType]] = [:]
            for i in 0..<Int(ready) {
                let event = events[i]
                let fd = Int32(event.ident)
                let filter = Int32(event.filter)

                switch filter {
                case EVFILT_READ:
                    var list = result[fd] ?? []
                    list.append(.read)
                    result[fd] = list
                    break
                case EVFILT_EXCEPT:
                    if filter & EV_EOF == 1 {
                        print("EOF")
                    }
                    var list = result[fd] ?? []
                    list.append(.except)
                    result[fd] = list
                    break
                case EVFILT_WRITE:
                    var list = result[fd] ?? []
                    list.append(.write)
                    result[fd] = list
                    break
                default:
                    print("Unknown event filter found")
                    break
                }
            }
            var finalEvents: [SelectableEvent] = []
            for (f, l) in result {
                finalEvents.append(SelectableEvent(fd: f, eventTypes: l))
            }
            return finalEvents
        }
        print("No events ready")
        return []
    }
    
    func register(selectable: Selectable) {
        update(fd: selectable.fileDescriptor, eventTypes: selectable.eventTypes, remove: false)
    }
    
    func deregister(selectable: Selectable) {
        update(fd: selectable.fileDescriptor, eventTypes: selectable.eventTypes, remove: true)
    }
    
    func update(fd: Int32, eventTypes: [EventType], remove: Bool = false) {
        let events = UnsafeMutablePointer<kevent>.allocate(capacity: eventTypes.count)
        var i = 0
        for eventType in eventTypes {
            var event = kevent()
            event.ident = UInt(fd)
            event.filter = eventType.kFilter
            event.flags = remove ? UInt16(EV_DELETE | EV_DISABLE) : UInt16(EV_ADD | EV_ENABLE)
            event.fflags = 0
            event.udata = nil
            event.data = 0
            
            // macOS fix picked up from swift-nio
            // apparently macOS can toss EVFILT_EXCEPT when it has data available in the read buffer
            // which is not something we want. Therefore we increase the size on when it throws that particular mesage
            // to Int.max effectively disabling it
            if eventType == .except {
                print("Adding macOS fix")
                event.fflags = CUnsignedInt(NOTE_LOWAT)
                event.data = Int.max
            }
            
            events[i] = event
            i += 1
        }
        
        // TODO: Handle potential error states here, i really need to add some throwing functions XD
        // Although I haven't tested this its most likely cheaper to do the allocation for
        // the events rather than context switch 3 times for the syscalls on each
        _ = sysKevent(kq, events, Int32(eventTypes.count), nil, 0, nil)
        print("New selectable should be registered")
    }
}

extension EventType {
    var kFilter: Int16 {
        switch self {
        case .except:
            return Int16(EVFILT_EXCEPT)
        case .read:
            return Int16(EVFILT_READ)
        case .write:
            return Int16(EVFILT_WRITE)
        }
    }
}

extension RunLoopTimeout {
    var toKTimespec: timespec {
        return timespec(tv_sec: seconds, tv_nsec: nanoSeconds)
    }
}
#endif
