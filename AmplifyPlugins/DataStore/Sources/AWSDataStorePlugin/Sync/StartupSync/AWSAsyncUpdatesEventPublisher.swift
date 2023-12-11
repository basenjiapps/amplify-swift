//
//  AWSAsyncUpdatesEventPublisher.swift
//
//
//  Created by Alex Lednik on 01/12/2023.
//

import Amplify
import AWSPluginsCore
import Combine
import Foundation

class AWSAsyncUpdatesEventPublisher: AmplifyCancellable {
    typealias Payload = UpdatesList<MutationSyncResult>
    typealias Operation = GraphQLOperation<Payload>
    typealias UpdatesResult = Result<Operation.Success, Operation.Failure>
    typealias CompletionHandler = (UpdatesResult)->()
    
    private var updateOperation: RetryableGraphQLOperation<Payload>?
    
    private let awsAuthService: AWSAuthServiceBehavior


    private let modelName: ModelName
    
    var completionHandler: CompletionHandler?

    init(modelSchema: ModelSchema,
         api: APICategoryGraphQLBehaviorExtended,
         modelPredicate: QueryPredicate,
         auth: AuthCategoryBehavior?,
         authModeStrategy: AuthModeStrategy,
         awsAuthService: AWSAuthServiceBehavior? = nil) async {
        self.modelName = modelSchema.name
        self.awsAuthService = awsAuthService ?? AWSAuthService()
        
        // update operation
        let updateAuthTypeProvider = await authModeStrategy.authTypesFor(schema: modelSchema,
                                                                     operation: .create)
        updateOperation = RetryableGraphQLOperation<Payload>(
            requestFactory: AWSAsyncUpdatesEventPublisher.apiRequestFactoryFor(
                for: modelSchema,
                modelPredicate: modelPredicate,
                api: api,
                auth: auth,
                awsAuthService: self.awsAuthService,
                authTypeProvider: updateAuthTypeProvider),
            maxRetries: updateAuthTypeProvider.count,
            resultListener: resultListener) { nextRequest, wrappedCompletion in
                api.query(request: nextRequest, listener: wrappedCompletion)
                
        }
        updateOperation?.main()
    }
    
    func resultListener(_ result: UpdatesResult) {
        log.verbose("resultListener: \(result)")
        print("resultListener: \(result)")
        completionHandler?(result)
    }
    
    static func makeAPIRequest(for modelSchema: ModelSchema,
                               modelPredicate: QueryPredicate,
                               api: APICategoryGraphQLBehaviorExtended,
                               auth: AuthCategoryBehavior?,
                               authType: AWSAuthorizationType?,
                               awsAuthService: AWSAuthServiceBehavior) async -> GraphQLRequest<Payload> {
        
        return GraphQLRequest<Payload>.startupQuery(
            modelSchema: modelSchema,
            where: modelPredicate,
            authType: authType,
            limit: 1000)
    }
    
    
    func cancel() {
        updateOperation?.cancel()
    }
    
    
}

// MARK: - AWSAsyncUpdatesEventPublisher + API request factory
extension AWSAsyncUpdatesEventPublisher {
    static func apiRequestFactoryFor(for modelSchema: ModelSchema,
                                     modelPredicate: QueryPredicate,
                                     api: APICategoryGraphQLBehaviorExtended,
                                     auth: AuthCategoryBehavior?,
                                     awsAuthService: AWSAuthServiceBehavior,
                                     authTypeProvider: AWSAuthorizationTypeIterator) -> RetryableGraphQLOperation<Payload>.RequestFactory {
        var authTypes = authTypeProvider
        return {
            return await AWSAsyncUpdatesEventPublisher.makeAPIRequest(for: modelSchema,
                                                                      modelPredicate: modelPredicate,
                                                                      api: api,
                                                                      auth: auth,
                                                                      authType: authTypes.next(),
                                                                      awsAuthService: awsAuthService)
        }
    }
}

extension AWSAsyncUpdatesEventPublisher: DefaultLogger {
    public static var log: Logger {
        Amplify.Logging.logger(forCategory: CategoryType.dataStore.displayName, forNamespace: String(describing: self))
    }
    public var log: Logger {
        Self.log
    }
}
