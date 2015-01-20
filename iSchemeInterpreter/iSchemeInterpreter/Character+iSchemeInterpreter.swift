//
//  Character+iSchemeInterpreter.swift
//  iSchemeInterpreter
//
//  Created by Yan Zhang on 1/15/15.
//  Copyright (c) 2015 Yan Zhang. All rights reserved.
//

import Foundation
extension Character {
    func isMemberOf(set: NSCharacterSet) -> Bool {
        let bridgedCharacter = (String(self) as NSString).characterAtIndex(0)
        return set.characterIsMember(bridgedCharacter)
    }
}