//
//  Item.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
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
