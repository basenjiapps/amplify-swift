//
//  SQLStatement+AddColumn.swift
//
//
//  Created by Raman Khilko on 1.11.23.
//

import Amplify
import Foundation
import SQLite

struct AlterTableAddColumnStatement: SQLStatement {
    var modelSchema: ModelSchema
    var field: ModelField

    var stringValue: String {
        return "ALTER TABLE \"\(modelSchema.name)\" ADD \"\(field.sqlName)\" \(field.sqlType)"
    }

    init(modelSchema: ModelSchema, field: ModelField) {
        self.modelSchema = modelSchema
        self.field = field
    }
}
