//
//  AWSOnetimeSyncQueue.swift
//
//
//  Created by Alex Lednik on 04/12/2023.
//

import Amplify
import AWSPluginsCore
import Combine
import Foundation

class AWSOnetimeSyncQueue {
//    private let incomingSubscriptionEvents: IncomingSubscriptionEventPublisher
    private let incomingUpdatesEvents: AWSAsyncUpdatesEventPublisher

    private let modelSchema: ModelSchema
    weak var storageAdapter: StorageEngineAdapter?
    private let modelPredicate: QueryPredicate?

    /// A buffer queue for incoming subsscription events, waiting for this ReconciliationQueue to be `start`ed. Once
    /// the ReconciliationQueue is started, each event in the `incomingRemoveEventQueue` will be submitted to the
    /// `reconcileAndSaveQueue`.
//    private let incomingSubscriptionEventQueue: OperationQueue

    /// Applies incoming mutation or subscription events serially to local data store for this model type. This queue
    /// is always active.
    private let reconcileAndSaveQueue: ReconcileAndSaveOperationQueue
    var reconcileAndLocalSaveOperationSink: AnyCancellable?

//    private var incomingEventsSink: AnyCancellable?
//    private var reconcileAndLocalSaveOperationSinks: AtomicValue<Set<AnyCancellable?>>

    private let modelReconciliationQueueSubject: CurrentValueSubject<ModelReconciliationQueueEvent, DataStoreError>
    var publisher: AnyPublisher<ModelReconciliationQueueEvent, DataStoreError> {
        return modelReconciliationQueueSubject.eraseToAnyPublisher()
    }

    init(modelSchema: ModelSchema,
         storageAdapter: StorageEngineAdapter?,
         api: APICategoryGraphQLBehaviorExtended,
         reconcileAndSaveQueue: ReconcileAndSaveOperationQueue,
         modelPredicate: QueryPredicate,
         auth: AuthCategoryBehavior?,
         authModeStrategy: AuthModeStrategy) async {

        self.modelSchema = modelSchema
        self.storageAdapter = storageAdapter

        self.modelPredicate = modelPredicate
        self.modelReconciliationQueueSubject = CurrentValueSubject<ModelReconciliationQueueEvent, DataStoreError>(.idle)

        self.reconcileAndSaveQueue = reconcileAndSaveQueue

        let resolvedIncomingUpdatesEvents: AWSAsyncUpdatesEventPublisher = await AWSAsyncUpdatesEventPublisher(
            modelSchema: modelSchema,
            api: api,
            modelPredicate: modelPredicate,
            auth: auth,
            authModeStrategy: authModeStrategy)
        
        self.incomingUpdatesEvents = resolvedIncomingUpdatesEvents
    }
    
    func enqueue(_ result: AWSAsyncUpdatesEventPublisher.UpdatesResult) {//_ remoteModels: [MutationSync<AnyModel>]) {
//        guard !remoteModels.isEmpty else {
//            log.debug("\(#function) skipping reconciliation, no models to enqueue.")
//            return
//        }
        guard let success = try? result.get().get() else {
            log.debug("\(#function) skipping reconciliation, no models to enqueue.")
            return
        }
        let remoteModels = success//[success]

        let reconcileOp = ReconcileAndLocalSaveOperation(modelSchema: modelSchema,
                                                         remoteModels: [],//remoteModels,
                                                         storageAdapter: storageAdapter)
//        var reconcileAndLocalSaveOperationSink: AnyCancellable?
        reconcileAndLocalSaveOperationSink = reconcileOp
            .publisher
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else {
                    return
                }
//                self.reconcileAndLocalSaveOperationSinks.with { $0.remove(reconcileAndLocalSaveOperationSink) }
                if case .failure = completion {
                    self.modelReconciliationQueueSubject.send(completion: completion)
                }
            }, receiveValue: { [weak self] value in
                guard let self = self else {
                    return
                }
                switch value {
                case .mutationEventDropped(let modelName, let error):
                    self.modelReconciliationQueueSubject.send(.mutationEventDropped(modelName: modelName, error: error))
                case .mutationEvent(let event):
                    self.modelReconciliationQueueSubject.send(.mutationEvent(event))
                }
            })
//        reconcileAndLocalSaveOperationSinks.with { $0.insert(reconcileAndLocalSaveOperationSink) }
        reconcileAndSaveQueue.addOperation(reconcileOp, modelName: modelSchema.name)
    }
}

extension AWSOnetimeSyncQueue: DefaultLogger {
    public static var log: Logger {
        Amplify.Logging.logger(forCategory: CategoryType.dataStore.displayName, forNamespace: String(describing: self))
    }
    public var log: Logger {
        Self.log
    }
}

// MARK: Resettable
extension AWSOnetimeSyncQueue: Resettable {

    func reset() async {
        log.verbose("Resetting updates for: \(modelSchema.name)")
        reconcileAndLocalSaveOperationSink?.cancel()
        log.verbose("Resetting updates for \(modelSchema.name): finished")
    }
}
