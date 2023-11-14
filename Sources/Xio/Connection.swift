//
//  Connection.swift
//  
//
//  Created by Antwan van Houdt on 15/06/2022.
//

import Foundation

class Connection: SocketHandler {
    func didRead(bytes: [UInt8]) {
        print("Read bytes: \(bytes.count)")
    }
    
    func send(bytes: [UInt8]) {
        
    }
}
