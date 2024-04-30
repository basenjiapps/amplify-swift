//
//  DataStoreIntermediateMigration.swift
//  
//
//  Created by Raman Khilko on 31.10.23.
//

import Amplify
import Foundation

public class DataStoreIntermediateMigration {
    let fromVersion: String
    let toVersion: String
    private var statements: [any SQLStatement] = []
    
    public init(fromVersion: String, toVersion: String) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
    }
    
    public func addColumn(_ key: any ModelKey, to modelSchema: ModelSchema) {
        guard let field = modelSchema.field(withName: key.stringValue) else {
            return
        }
        
        let statement = AlterTableAddColumnStatement(modelSchema: modelSchema, field: field)
        
        statements.append(statement)
    }
    
    func apply(with storageAdapter: SQLiteStorageEngineAdapter) throws {
        guard let connection = storageAdapter.connection else {
            throw DataStoreError.nilSQLiteConnection()
        }
        
        try storageAdapter.transaction {
            for statement in statements {
                try connection.execute(statement.stringValue)
            }
        }
    }
}


