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
        kq = (kqueue())
        if kq == -1 {
            return nil
        }
    }
    
    deinit {
        close(kq)
    }
    
    // MARK: -
    
    func run(timeout: RunLoopTimeout? = nil) -> [SelectableEvent] {
        var ready: Int32 = 0
        // this could potentially suck, probably should do this without the copy heh
        // var events: [kevent] = [kevent](repeating: kevent(ident: 0, filter: 0, flags: 0, fflags: 0, data: 0, udata: nil), count: 20)
        print("entering kqueue runloop")
        if let timeout = timeout {
            var t = timeout.toKTimespec
            ready = kevent(kq, nil, 0, events, Int32(eventCapacity), &t)
        } else {
            ready = kevent(kq, nil, 0, events, Int32(eventCapacity), nil)
        }
        
        guard ready != -1 else {
            return []
        }
        if ready > 0 {
            print("Events ready: \(ready)")
            var result: [Int32: [EventType]] = [:]
            for i in 0..<Int(ready) {
                let event = events[i]
                let fd = Int32(event.ident)
                let filter = Int32(event.filter)
                
                if filter & EVFILT_READ == 1 {
                    print("a real read maybe?")
                }

                switch filter {
                case EVFILT_READ:
                    print("[ EVENT ] READ")
                    var list = result[fd] ?? []
                    list.append(.read)
                    result[fd] = list
                    break
                case EVFILT_EXCEPT:
                    print("[ EVENT ] EXCEPT")
                    if filter & EV_EOF == 1 {
                        print("EOF")
                    }
                    var list = result[fd] ?? []
                    list.append(.except)
                    result[fd] = list
                    break
                case EVFILT_WRITE:
                    print("[ EVENT ] WRITE")
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
        update(selectable: selectable)
        print("Selectable registered")
    }
    
    func deregister(selectable: Selectable) {
        update(selectable: selectable, remove: true)
    }
    
    private func update(selectable: Selectable, remove: Bool = false) {
        let events = UnsafeMutablePointer<kevent>.allocate(capacity: selectable.eventTypes.count)
        var i = 0
        for eventType in selectable.eventTypes {
            var event = kevent()
            event.ident = UInt(selectable.fileDescriptor)
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
        _ = sysKevent(kq, events, Int32(selectable.eventTypes.count), nil, 0, nil)
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

/*
 /// Update a kevent for a given filter, file descriptor, and set of flags.
 mutating func setEvent(fileDescriptor fd: CInt, filter: CInt, flags: UInt16, registrationID: SelectorRegistrationID) {
     self.ident = UInt(fd)
     self.filter = Int16(filter)
     self.flags = flags
     self.udata = UnsafeMutableRawPointer(bitPattern: UInt(registrationID.rawValue))

     // On macOS, EVFILT_EXCEPT will fire whenever there is unread data in the socket receive
     // buffer. This is not a behaviour we want from EVFILT_EXCEPT: we only want it to tell us
     // about actually exceptional conditions. For this reason, when we set EVFILT_EXCEPT
     // we do it with NOTE_LOWAT set to Int.max, which will ensure that there is never enough data
     // in the send buffer to trigger EVFILT_EXCEPT. Thanks to the sensible design of kqueue,
     // this only affects our EXCEPT filter: EVFILT_READ behaves separately.
     if filter == EVFILT_EXCEPT {
         self.fflags = CUnsignedInt(NOTE_LOWAT)
         self.data = Int.max
     } else {
         self.fflags = 0
         self.data = 0
     }
 }
 */

//extension Selectable {
//    var kevent: kevent {
//        var event = Darwin.kevent()
//        event.ident = UInt(fileDescriptor)
//        event.flags = UInt16(EV_ADD | EV_ENABLE)
//        if eventTypes.contains(.read) {
//            event.filter |= Int16(EVFILT_READ)
//        }
//        if eventTypes.contains(.write) {
//            event.filter |= Int16(EVFILT_WRITE)
//        }
//        if eventTypes.contains(.except) {
//            event.filter |= Int16(EVFILT_EXCEPT)
//
//            // macOS fix picked up from swift-nio
//            // apparently macOS can toss EVFILT_EXCEPT when it has data available in the read buffer
//            // which is not something we want. Therefore we increase the size on when it throws that particular mesage
//            // to Int.max effectively disabling it
//            event.fflags = CUnsignedInt(NOTE_LOWAT)
//            event.data = Int.max
//        }
//        return event
//        // return Darwin.kevent(ident: UInt(fileDescriptor), filter: filter, flags: UInt16(EV_ADD | EV_ENABLE), fflags: 0, data: 0, udata: nil)
//    }
//
//    var deleteKevent: kevent {
//        var filter: Int16 = 0
//        if eventTypes.contains(.read) {
//            filter = Int16(EVFILT_READ)
//        }
//        if eventTypes.contains(.write) {
//            filter |= Int16(EVFILT_WRITE)
//        }
//        if eventTypes.contains(.except) {
//            filter |= Int16(EVFILT_EXCEPT)
//        }
//        return Darwin.kevent(ident: UInt(fileDescriptor), filter: filter, flags: UInt16(EV_DELETE), fflags: 0, data: 0, udata: nil)
//    }
//}

extension RunLoopTimeout {
    var toKTimespec: timespec {
        return timespec(tv_sec: seconds, tv_nsec: nanoSeconds)
    }
}
#endif
