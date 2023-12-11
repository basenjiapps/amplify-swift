//
//  NoIncomingSubscriptionEventPublisher.swift
//  
//
//  Created by Raman Khilko on 9.12.23.
//

import Amplify
import AWSPluginsCore
import Combine
import Foundation

final class NoIncomingSubscriptionEventPublisher: IncomingSubscriptionEventPublisher {
    private let subscriptionEventSubject = PassthroughSubject<IncomingSubscriptionEventPublisherEvent, DataStoreError>()
    
    var publisher: AnyPublisher<IncomingSubscriptionEventPublisherEvent, DataStoreError> {
        subscriptionEventSubject.eraseToAnyPublisher()
    }
    
    init() {
        Task {
            try await Task.sleep(seconds: 1)
            subscriptionEventSubject.send(.connectionConnected)
        }
    }
    
    func cancel() {
        subscriptionEventSubject.send(completion: .finished)
    }
}
