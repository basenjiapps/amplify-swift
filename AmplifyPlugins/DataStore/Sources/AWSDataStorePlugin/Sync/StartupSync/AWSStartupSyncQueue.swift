//
//  AWSStartupSyncQueue.swift
//
//
//  Created by Alex Lednik on 05/12/2023.
//

import Amplify
import AWSPluginsCore
import Combine
import Foundation

final class AWSStartupSyncQueue: IncomingEventReconciliationQueue {
    private var modelReconciliationQueueSinks: AtomicValue<[String: AnyCancellable]> = AtomicValue(initialValue: [:])

    private let eventReconciliationQueueTopic: CurrentValueSubject<IncomingEventReconciliationQueueEvent, DataStoreError>
    var publisher: AnyPublisher<IncomingEventReconciliationQueueEvent, DataStoreError> {
        return eventReconciliationQueueTopic.eraseToAnyPublisher()
    }

    private let connectionStatusSerialQueue: DispatchQueue
    private var reconcileAndSaveQueue: ReconcileAndSaveOperationQueue
    private var reconciliationQueues: AtomicValue<[ModelName: AWSOnetimeSyncQueue]> = AtomicValue(initialValue: [:])
    private var reconciliationQueueConnectionStatus: [ModelName: Bool]

    private var isInitialized: Bool {
        log.verbose("[AWSStartupSyncQueue.5] \(reconciliationQueueConnectionStatus.count)/\(modelSchemasCount) initialized")
        return modelSchemasCount == reconciliationQueueConnectionStatus.count
    }
    private let modelSchemasCount: Int
    
    init(modelSchemas: [ModelSchema],
         api: APICategoryGraphQLBehaviorExtended,
         storageAdapter: StorageEngineAdapter,
         syncExpressions: [DataStoreSyncExpression],
         auth: AuthCategoryBehavior? = nil,
         authModeStrategy: AuthModeStrategy) async {
        self.modelSchemasCount = modelSchemas.count
        self.modelReconciliationQueueSinks.set([:])
        self.eventReconciliationQueueTopic = CurrentValueSubject<IncomingEventReconciliationQueueEvent, DataStoreError>(.idle)
        self.reconciliationQueues.set([:])
        self.reconciliationQueueConnectionStatus = [:]
        self.reconcileAndSaveQueue = ReconcileAndSaveQueue(modelSchemas)
        
        // TODO: Add target for SyncEngine system to help prevent thread explosion and increase performance
        // https://github.com/aws-amplify/amplify-ios/issues/399
        self.connectionStatusSerialQueue
            = DispatchQueue(label: "com.amazonaws.DataStore.AWSStartupSyncQueue")

        for modelSchema in modelSchemas {
            let modelName = modelSchema.name
            let syncExpression = syncExpressions.first(where: {
                $0.modelSchema.name == modelName
            })
            guard reconciliationQueues.get()[modelName] == nil,
                    let modelPredicate = syncExpression?.modelPredicate() ?? nil else {
                log.warn("Duplicate model name found: \(modelName), not subscribing")
                continue
            }
            let queue = await AWSOnetimeSyncQueue(
                modelSchema: modelSchema,
                storageAdapter: storageAdapter,
                api: api, 
                reconcileAndSaveQueue: reconcileAndSaveQueue,
                modelPredicate: modelPredicate,
                auth: auth,
                authModeStrategy: authModeStrategy)
//            let queue = await self.modelReconciliationQueueFactory(modelSchema,
//                                                             storageAdapter,
//                                                             api,
//                                                             reconcileAndSaveQueue,
//                                                             modelPredicate,
//                                                             auth,
//                                                             authModeStrategy,
//                                                             nil)
//            
            reconciliationQueues.with { reconciliationQueues in
                reconciliationQueues[modelName] = queue
            }
            log.verbose("[AWSStartupSyncQueue.5] Sink reconciliationQueues \(modelName) \(reconciliationQueues.get().count)")
            let modelReconciliationQueueSink = queue.publisher.sink(receiveCompletion: onReceiveCompletion(completed:),
                                                                    receiveValue: onReceiveValue(receiveValue:))
//            modelReconciliationQueueSinks.with { modelReconciliationQueueSinks in
//                modelReconciliationQueueSinks[modelName] = modelReconciliationQueueSink
//            }
//            log.verbose("[InitializeSubscription.5] Sink done reconciliationQueues \(modelName) \(reconciliationQueues.get().count)")
        }
    }

    func start() {
//        reconciliationQueues.get().values.forEach { $0.start() }
//        eventReconciliationQueueTopic.send(.started)
    }

    func pause() {
//        reconciliationQueues.get().values.forEach { $0.pause() }
//        eventReconciliationQueueTopic.send(.paused)
    }

    func offer(_ remoteModels: [MutationSync<AnyModel>], modelName: ModelName) {
        guard let queue = reconciliationQueues.get()[modelName] else {
            // TODO: Error handling
            return
        }

//        queue.enqueue(remoteModels)
    }

    private func onReceiveCompletion(completed: Subscribers.Completion<DataStoreError>) {
//        connectionStatusSerialQueue.async {
//            self.reconciliationQueueConnectionStatus = [:]
//        }
//        switch completed {
//        case .failure(let error):
//            eventReconciliationQueueTopic.send(completion: .failure(error))
//        case .finished:
//            eventReconciliationQueueTopic.send(completion: .finished)
//        }
    }

    private func onReceiveValue(receiveValue: ModelReconciliationQueueEvent) {
        switch receiveValue {
        case .mutationEvent(let event):
            eventReconciliationQueueTopic.send(.mutationEventApplied(event))
        case .mutationEventDropped(let modelName, let error):
            eventReconciliationQueueTopic.send(.mutationEventDropped(modelName: modelName, error: error))
        case .connected(modelName: let modelName):
            connectionStatusSerialQueue.async {
                self.log.verbose("[AWSStartupSyncQueue.4] .connected \(modelName)")
                self.reconciliationQueueConnectionStatus[modelName] = true
                if self.isInitialized {
                    self.log.verbose("[AWSStartupSyncQueue.6] connected isInitialized")
                    self.eventReconciliationQueueTopic.send(.initialized)
                }
            }
        case .disconnected(modelName: let modelName, reason: .operationDisabled),
             .disconnected(modelName: let modelName, reason: .unauthorized):
            connectionStatusSerialQueue.async {
                self.log.verbose("[AWSStartupSyncQueue.4] subscription disconnected [\(modelName)] reason: [\(receiveValue)]")
                // A disconnected subscription due to operation disabled or unauthorized will still contribute
                // to the overall state of the reconciliation queue system on sending the `.initialized` event
                // since subscriptions may be disabled and have to reconcile locally sourced mutation evemts.
                self.reconciliationQueueConnectionStatus[modelName] = true
                if self.isInitialized {
                    self.log.verbose("[AWSStartupSyncQueue.6] disconnected isInitialized")
                    self.eventReconciliationQueueTopic.send(.initialized)
                }
            }
        default:
            break
        }
    }

    func cancel() {
        modelReconciliationQueueSinks.get().values.forEach { $0.cancel() }
//        reconciliationQueues.get().values.forEach { $0.cancel()}
        connectionStatusSerialQueue.sync {
            self.reconciliationQueues.set([:])
            self.modelReconciliationQueueSinks.set([:])
        }
    }

    private func dispatchSyncQueriesReady() {
        let syncQueriesReadyPayload = HubPayload(eventName: HubPayload.EventName.DataStore.syncQueriesReady)
        Amplify.Hub.dispatch(to: .dataStore, payload: syncQueriesReadyPayload)
    }
}

extension AWSStartupSyncQueue: DefaultLogger {
    public static var log: Logger {
        Amplify.Logging.logger(forCategory: CategoryType.analytics.displayName, forNamespace: String(describing: self))
    }
    public var log: Logger {
        Self.log
    }
}
