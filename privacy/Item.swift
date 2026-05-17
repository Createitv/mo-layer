//
//  Item.swift
//  privacy
//
//  Created by PangHuang on 5/17/26.
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
