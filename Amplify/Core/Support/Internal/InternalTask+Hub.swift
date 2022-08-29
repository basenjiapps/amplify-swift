//
// Copyright Amazon.com Inc. or its affiliates.
// All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public extension InternalTaskIdentifiable {

    var idFilter: HubFilter {
        let filter: HubFilter = { payload in
            guard let context = payload.context as? AmplifyOperationContext<Request> else {
                return false
            }

            return context.operationId == id
        }

        return filter
    }

}

public extension InternalTaskHubResult {

    func unsubscribe(_ token: UnsubscribeToken) {
        Amplify.Hub.removeListener(token)
    }

}

public extension InternalTaskHubInProcess {

    func unsubscribe(_ token: UnsubscribeToken) {
        Amplify.Hub.removeListener(token)
    }

}

public extension InternalTaskHubResult where Self: InternalTaskIdentifiable & InternalTaskResult {

    func subscribe(resultListener: @escaping ResultListener) -> UnsubscribeToken {
        let channel = HubChannel(from: categoryType)

        var unsubscribe: (() -> Void)?
        let resultHubListener: HubListener = { payload in
            guard let result = payload.data as? TaskResult else {
                return
            }
            resultListener(result)
            // Automatically unsubscribe when event is received
            unsubscribe?()
        }
        let token = Amplify.Hub.listen(to: channel,
                                       isIncluded: idFilter,
                                       listener: resultHubListener)
        unsubscribe = {
            Amplify.Hub.removeListener(token)
        }
        return token
    }

    func dispatch(result: TaskResult) {
        let channel = HubChannel(from: categoryType)
        let context = AmplifyOperationContext(operationId: id, request: request)
        let payload = HubPayload(eventName: eventName, context: context, data: result)
        Amplify.Hub.dispatch(to: channel, payload: payload)
    }

}

public extension InternalTaskHubInProcess where Self: InternalTaskIdentifiable & InternalTaskInProcess {

    func subscribe(inProcessListener: @escaping InProcessListener) -> UnsubscribeToken {
        let channel = HubChannel(from: categoryType)

        let inProcessHubListener: HubListener = { payload in
            if let inProcessData = payload.data as? InProcess {
                inProcessListener(inProcessData)
                return
            }
        }
        let token = Amplify.Hub.listen(to: channel,
                                       isIncluded: idFilter,
                                       listener: inProcessHubListener)
        return token
    }

    func dispatch(inProcess: InProcess) {
        let channel = HubChannel(from: categoryType)
        let context = AmplifyOperationContext(operationId: id, request: request)
        let payload = HubPayload(eventName: eventName, context: context, data: inProcess)
        Amplify.Hub.dispatch(to: channel, payload: payload)
    }

}

public extension InternalTaskHubInProcess where Self: InternalTaskIdentifiable & InternalTaskResult & InternalTaskInProcess {

    func subscribe(inProcessListener: @escaping InProcessListener) -> UnsubscribeToken {
        let channel = HubChannel(from: categoryType)

        var unsubscribe: (() -> Void)?
        let inProcessHubListener: HubListener = { payload in
            if let inProcessData = payload.data as? InProcess {
                inProcessListener(inProcessData)
                return
            }

            // Remove listener if we see a result come through
            if payload.data is TaskResult {
                unsubscribe?()
            }
        }
        let token = Amplify.Hub.listen(to: channel,
                                       isIncluded: idFilter,
                                       listener: inProcessHubListener)
        unsubscribe = {
            Amplify.Hub.removeListener(token)
        }
        return token
    }

}

public extension InternalTaskHubInProcess where Self: InternalTaskIdentifiable {

    func subscribe(inProcessListener: @escaping InProcessListener) -> UnsubscribeToken {
        let channel = HubChannel(from: categoryType)
        let filterById = idFilter

        let inProcessHubListener: HubListener = { payload in
            if let inProcessData = payload.data as? InProcess {
                inProcessListener(inProcessData)
                return
            }
        }
        let token = Amplify.Hub.listen(to: channel,
                                       isIncluded: filterById,
                                       listener: inProcessHubListener)
        return token
    }

    func dispatch(inProcess: InProcess) {
        let channel = HubChannel(from: categoryType)
        let context = AmplifyOperationContext(operationId: id, request: request)
        let payload = HubPayload(eventName: eventName, context: context, data: inProcess)
        Amplify.Hub.dispatch(to: channel, payload: payload)
    }
}

public extension InternalTaskHubInProcess where Self: InternalTaskIdentifiable & InternalTaskResult {

    func subscribe(inProcessListener: @escaping InProcessListener) -> UnsubscribeToken {
        let channel = HubChannel(from: categoryType)
        let filterById = idFilter

        var unsubscribe: (() -> Void)?
        let inProcessHubListener: HubListener = { payload in
            if let inProcessData = payload.data as? InProcess {
                inProcessListener(inProcessData)
                return
            }

            // Remove listener if we see a result come through
            if payload.data is TaskResult {
                unsubscribe?()
            }
        }
        let token = Amplify.Hub.listen(to: channel,
                                       isIncluded: filterById,
                                       listener: inProcessHubListener)
        unsubscribe = {
            Amplify.Hub.removeListener(token)
        }
        return token
    }

}
