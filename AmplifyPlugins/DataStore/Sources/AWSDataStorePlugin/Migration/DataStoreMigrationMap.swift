//
//  DataStoreMigrationMap.swift
//  
//
//  Created by Raman Khilko on 1.11.23.
//

import Amplify
import Foundation

public class DataStoreMigrationMap {
    private var versions = [String]()
    private var migrations = [DataStoreIntermediateMigration]()
    
    public init() { }
    
    func migrations(fromVersion: String, toVersion: String) -> [DataStoreIntermediateMigration] {
        guard
            fromVersion != toVersion,
            let startIndex = versions.firstIndex(of: fromVersion),
            let endIndex = versions.firstIndex(of: toVersion)
        else {
            return []
        }
        
        var result = [DataStoreIntermediateMigration]()
        
        for index in startIndex..<endIndex {
            let from = versions[index]
            let to = versions[index + 1]
            
            if let migration = migrations.first(where: { $0.fromVersion == from && $0.toVersion == to }) {
                result.append(migration)
            }
        }
        
        return result
    }
    
    public func addMigration(fromVersion: String, toVersion: String, initClosure: (DataStoreIntermediateMigration) -> Void) {
        if versions.isEmpty {
            versions.append(fromVersion)
        } else if !versions.contains(fromVersion) {
            assertionFailure("Wrong version: \(fromVersion)")
        }
        
        versions.append(toVersion)
        
        let migration = DataStoreIntermediateMigration(fromVersion: fromVersion, toVersion: toVersion)
        
        initClosure(migration)
        migrations.append(migration)
    }
}
