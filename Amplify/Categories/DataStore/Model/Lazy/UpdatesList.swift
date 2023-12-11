//
//  UpdatesList.swift
//
//
//  Created by Alex Lednik on 06/12/2023.
//

import Foundation

private enum ResponseKey {
    static let data = "data"
    static let items = "items"
}

public class UpdatesList<ModelType: Decodable>: Codable, ModelListMarker {
    private typealias ResponseDict = [String: JSONValue]
    
    enum CodingKeys: String, CodingKey {
        case graphQLData
    }
    
    public private(set) var items: [ModelType]?
    public private(set) var nextToken: String?
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let dynamicKey = container.allKeys.first { _ in true }
        
        let nestedContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: dynamicKey!)
        print(nestedContainer.allKeys.description)
        items = try? nestedContainer.decode([ModelType].self, forKey: DynamicCodingKey(stringValue: "items"))
//        data = try nestedContainer.decode(TestResultsData.self, forKey: DynamicCodingKey(stringValue: "listAmplifyTestResults")!)
        
//        let json = try JSONValue(from: decoder)
//        if case .object(let dict) = json, let data = dict[ResponseKey.data] {
//            if case .object(let responseDict) = data, let response = responseDict.values.first {
//                if case .object(let itemsDict) = response, let rawItemsArray = itemsDict[ResponseKey.items] {
//                    if case .array(let itamsArray) = rawItemsArray {
//
//                    }
//                }
//                
//            }
//        }
    }
    
    public func encode(to encoder: Encoder) throws {
        throw NSError(domain: "UpdatesList encode not implemented", code: -111)
    }
}

fileprivate struct DynamicCodingKey: CodingKey {
    var stringValue: String

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    var intValue: Int?

    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}
