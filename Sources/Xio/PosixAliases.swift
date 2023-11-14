//
//  PosixAliases.swift
//  
//
//  Created by Antwan van Houdt on 10/06/2022.
//

import Foundation
import System

#if os(Linux)
// TODO: Linux support is currently not a goal, first get shit to work
#else
let systemRead = Darwin.read
#endif
