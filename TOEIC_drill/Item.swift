//
//  Item.swift
//  TOEIC_drill
//
//  Created by klm923 on 2026/02/19.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
