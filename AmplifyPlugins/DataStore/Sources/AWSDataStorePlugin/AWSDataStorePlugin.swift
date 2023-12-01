//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Amplify
import Combine
import AWSPluginsCore
import Foundation

enum DataStoreState {
    case start(storageEngine: StorageEngineBehavior)
    case stop
    case clear
}

final public class AWSDataStorePlugin: DataStoreCategoryPlugin {

    public var key: PluginKey = "awsDataStorePlugin"

    /// The Publisher that sends mutation events to subscribers
    var dataStorePublisher: ModelSubcriptionBehavior?
    
    var dataStoreStateSubject = PassthroughSubject<DataStoreState, DataStoreError>()

    var dispatchedModelSyncedEvents: [ModelName: AtomicValue<Bool>]

    let modelRegistration: AmplifyModelRegistration
    
    let migrationMap: DataStoreMigrationMap?

    /// The DataStore configuration
    var configuration: InternalDatastoreConfiguration

    var storageEngine: StorageEngineBehavior!

    /// A queue to allow synchronize access to the storage engine for start/stop/clear operations.
    var storageEngineInitQueue = DispatchQueue(label: "AWSDataStorePlugin.storageEngineInitQueue")

    /// A queue used for async callback out from`storageEngineInitQueue`
    var queue = DispatchQueue(label: "AWSDataStorePlugin.queue", target: DispatchQueue.global())

    var storageEngineBehaviorFactory: StorageEngineBehaviorFactory

    var iStorageEngineSink: Any?
    var storageEngineSink: AnyCancellable? {
        get {
            if let iStorageEngineSink = iStorageEngineSink as? AnyCancellable {
                return iStorageEngineSink
            }
            return nil
        }
        set {
            iStorageEngineSink = newValue
        }
    }

    /// No-argument init that uses defaults for all providers
    public init(modelRegistration: AmplifyModelRegistration,
                migrationMap: DataStoreMigrationMap? = nil,
                configuration dataStoreConfiguration: DataStoreConfiguration = .default) {
        self.modelRegistration = modelRegistration
        self.migrationMap = migrationMap
        self.configuration = InternalDatastoreConfiguration(
            isSyncEnabled: false,
            validAPIPluginKey: "awsAPIPlugin",
            validAuthPluginKey: "awsCognitoAuthPlugin",
            pluginConfiguration: dataStoreConfiguration)

        self.storageEngineBehaviorFactory =
        StorageEngine.init(
            isSyncEnabled:
                dataStoreConfiguration:
                validAPIPluginKey:
                validAuthPluginKey:
                modelRegistryVersion:
                userDefault:
                migratingEnabled:
        )
        self.dataStorePublisher = DataStorePublisher()
        self.dispatchedModelSyncedEvents = [:]
    }

    /// Internal initializer for testing
    init(modelRegistration: AmplifyModelRegistration,
         migrationMap: DataStoreMigrationMap? = nil,
         configuration dataStoreConfiguration: DataStoreConfiguration = .default,
         storageEngineBehaviorFactory: StorageEngineBehaviorFactory? = nil,
         dataStorePublisher: ModelSubcriptionBehavior,
         operationQueue: OperationQueue = OperationQueue(),
         validAPIPluginKey: String,
         validAuthPluginKey: String) {
        self.modelRegistration = modelRegistration
        self.migrationMap = migrationMap
        self.configuration = InternalDatastoreConfiguration(
            isSyncEnabled: false,
            validAPIPluginKey: validAPIPluginKey,
            validAuthPluginKey: validAuthPluginKey,
            pluginConfiguration: dataStoreConfiguration)

        self.storageEngineBehaviorFactory = storageEngineBehaviorFactory ??
        StorageEngine.init(
            isSyncEnabled:
                dataStoreConfiguration:
                validAPIPluginKey:
                validAuthPluginKey:
                modelRegistryVersion:
                userDefault:
                migratingEnabled:
        )
        self.dataStorePublisher = dataStorePublisher
        self.dispatchedModelSyncedEvents = [:]
    }

    /// By the time this method gets called, DataStore will already have invoked
    /// `AmplifyModelRegistration.registerModels`, so we can inspect those models to derive isSyncEnabled, and pass
    /// them to `StorageEngine.setUp(modelSchemas:)`
    public func configure(using amplifyConfiguration: Any?) throws {
        modelRegistration.registerModels(registry: ModelRegistry.self)
        
        for modelSchema in ModelRegistry.modelSchemas {
            dispatchedModelSyncedEvents[modelSchema.name] = AtomicValue(initialValue: false)
            configuration.updateIsEagerLoad(modelSchema: modelSchema)
        }
        resolveSyncEnabled()
        ModelListDecoderRegistry.registerDecoder(DataStoreListDecoder.self)
        ModelProviderRegistry.registerDecoder(DataStoreModelDecoder.self)
    }
    
    /// Initializes the underlying storage engine
    /// - Returns: success if the engine is successfully initialized or
    ///            a failure with a DataStoreError
    func initStorageEngine() -> Result<StorageEngineBehavior, DataStoreError> {
        if storageEngine != nil {
            return .success(storageEngine)
        }

        do {
            if self.dataStorePublisher == nil {
                self.dataStorePublisher = DataStorePublisher()
            }
            try resolveStorageEngine(dataStoreConfiguration: configuration.pluginConfiguration)
            try storageEngine.setUp(modelSchemas: ModelRegistry.modelSchemas)
            try storageEngine.applyModelMigrations(modelSchemas: ModelRegistry.modelSchemas)
            
            if let migrationMap {
                try storageEngine.applyIntermediateMigrations(migrationMap: migrationMap)
            }

            return .success(storageEngine)
        } catch {
            log.error(error: error)
            return .failure(.invalidOperation(causedBy: error))
        }
    }

    /// Initializes the underlying storage engine and starts the syncing process
    /// - Parameter completion: completion handler called with a success if the sync process started
    ///                         or with a DataStoreError in case of failure
    func initStorageEngineAndStartSync(completion: @escaping DataStoreCallback<Void> = { _ in }) {
        storageEngineInitQueue.sync {
            completion(
                initStorageEngine().flatMap { $0.startSync() }.flatMap { result in
                    switch result {
                    case .alreadyInitialized:
                        return .successfulVoid
                    case .successfullyInitialized:
                        self.dataStoreStateSubject.send(.start(storageEngine: self.storageEngine))
                        return .successfulVoid
                    case .failure(let error):
                        return .failure(error)
                    }
                }
            )
        }
    }

    func resolveStorageEngine(dataStoreConfiguration: DataStoreConfiguration) throws {
        guard storageEngine == nil else {
            return
        }

        storageEngine = try storageEngineBehaviorFactory(
            configuration.isSyncEnabled,
            dataStoreConfiguration,
            configuration.validAPIPluginKey,
            configuration.validAuthPluginKey,
            modelRegistration.version,
            UserDefaults.standard,
            migrationMap != nil
        )

        setupStorageSink()
    }

    // MARK: Private

    private func resolveSyncEnabled() {
        configuration.updateIsSyncEnabled(ModelRegistry.hasSyncableModels)
    }

    private func setupStorageSink() {
        storageEngineSink = storageEngine
            .publisher
            .sink(
                receiveCompletion: { [weak self] in self?.onReceiveCompletion(completed: $0) },
                receiveValue: { [weak self] in self?.onReceiveValue(receiveValue: $0) }
            )
    }

    private func onReceiveCompletion(completed: Subscribers.Completion<DataStoreError>) {
        switch completed {
        case .failure(let dataStoreError):
            log.error("StorageEngine completed with error: \(dataStoreError)")
        case .finished:
            log.debug("StorageEngine completed without error")
        }
    }

    func onReceiveValue(receiveValue: StorageEngineEvent) {
        guard let dataStorePublisher = self.dataStorePublisher else {
            log.error("Data store publisher not initalized")
            return
        }

        switch receiveValue {
        case .started:
            break
        case .mutationEvent(let mutationEvent):
            dataStorePublisher.send(input: mutationEvent)
        case .modelSyncedEvent(let modelSyncedEvent):
            log.verbose("Emitting DataStore event: modelSyncedEvent \(modelSyncedEvent)")
            dispatchedModelSyncedEvents[modelSyncedEvent.modelName]?.set(true)
            let modelSyncedEventPayload = HubPayload(eventName: HubPayload.EventName.DataStore.modelSynced,
                                                     data: modelSyncedEvent)
            Amplify.Hub.dispatch(to: .dataStore, payload: modelSyncedEventPayload)
        case .syncQueriesReadyEvent:
            log.verbose("[Lifecycle event 4]: syncQueriesReady")
            let syncQueriesReadyEventPayload = HubPayload(eventName: HubPayload.EventName.DataStore.syncQueriesReady)
            Amplify.Hub.dispatch(to: .dataStore, payload: syncQueriesReadyEventPayload)
        case .readyEvent:
            log.verbose("[Lifecycle event 6]: ready")
            let readyEventPayload = HubPayload(eventName: HubPayload.EventName.DataStore.ready)
            Amplify.Hub.dispatch(to: .dataStore, payload: readyEventPayload)
        }
    }

    public func reset() async {
        dispatchedModelSyncedEvents = [:]
        dataStorePublisher?.sendFinished()
        if let resettable = storageEngine as? Resettable {
            log.verbose("Resetting storageEngine")
            await resettable.reset()
            self.log.verbose("Resetting storageEngine: finished")
        }
    }

}

extension AWSDataStorePlugin: AmplifyVersionable { }
