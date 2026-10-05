import SwiftUI

@MainActor final class MerchantNPCSessionOwner {
    private final class Chat { weak var value: MerchantNPCChatCoordinator?; init(_ value: MerchantNPCChatCoordinator) { self.value = value } }
    private final class Resource { weak var value: MerchantNPCResourcesCoordinator?; init(_ value: MerchantNPCResourcesCoordinator) { self.value = value } }
    private final class Samples { weak var value: MerchantNPCVoiceSamplesCoordinator?; init(_ value: MerchantNPCVoiceSamplesCoordinator) { self.value = value } }
    private var samples: [Samples] = []
    func register(_ value: MerchantNPCVoiceSamplesCoordinator) { samples.removeAll { $0.value == nil }; samples.append(Samples(value)) }
    private var chats: [Chat] = []
    private var resources: [Resource] = []
    func register(_ value: MerchantNPCChatCoordinator) { chats.removeAll { $0.value == nil }; chats.append(Chat(value)) }
    func register(_ value: MerchantNPCResourcesCoordinator) { resources.removeAll { $0.value == nil }; resources.append(Resource(value)) }
    func invalidate() {
        samples.forEach { $0.value?.invalidate() }; samples.removeAll()
        chats.forEach { $0.value?.invalidate() }; resources.forEach { $0.value?.invalidate() }
        chats.removeAll(); resources.removeAll()
    }
}
