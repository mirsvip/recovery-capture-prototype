import Foundation
import RecoveryCore

#if os(iOS) || os(watchOS)
@preconcurrency import WatchConnectivity

// Integration source for iPhone and Watch app targets. A macOS package build
// excludes this branch; paired-device validation is still required.
@MainActor
public final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    public enum Role { case watch, phone }

    private let role: Role
    private let store: CaptureStore
    private let session: WCSession
    public var onError: ((Error) -> Void)?

    public init(role: Role, store: CaptureStore, session: WCSession = .default) {
        self.role = role
        self.store = store
        self.session = session
        super.init()
    }

    public func start() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    // Returns after local persistence, without waiting for phone or cloud sync.
    public func capture(_ payload: CapturePayload) throws {
        guard role == .watch else { throw CaptureError.wrongTransportRole }
        try store.recordOnWatch(payload)
        flushOutbox()
        if session.activationState == .activated && session.isReachable {
            sendImmediately(payload)
        }
    }

    // Call on app activation as well as the delegate events below. No polling
    // timer: offline data remains persisted until an application-level ACK.
    public func flushOutbox() {
        guard role == .watch, session.activationState == .activated else { return }
        do {
            let outstanding = Set(session.outstandingUserInfoTransfers.compactMap {
                transfer -> UUID? in
                guard let message = try? WireCodec.decode(transfer.userInfo),
                      case .capture(let payload) = message else { return nil }
                return payload.eventID
            })
            for payload in try store.pendingCaptures()
            where !outstanding.contains(payload.eventID) {
                session.transferUserInfo(try WireCodec.encode(.capture(payload)))
            }
        } catch { onError?(error) }
    }

    private func sendImmediately(_ payload: CapturePayload) {
        do {
            session.sendMessage(
                try WireCodec.encode(.capture(payload)),
                replyHandler: { [weak self] reply in
                    do {
                        let message = try WireCodec.decode(reply)
                        guard case .acknowledgement(let eventID) = message,
                              eventID == payload.eventID else {
                            throw CaptureError.invalidPayload
                        }
                        Task { @MainActor [weak self] in
                            do { try self?.store.acknowledge(eventID) }
                            catch { self?.onError?(error) }
                        }
                    } catch {
                        Task { @MainActor [weak self] in self?.onError?(error) }
                    }
                },
                errorHandler: { [weak self] error in
                    // Queued transfer and durable outbox remain the fallback.
                    Task { @MainActor [weak self] in self?.onError?(error) }
                }
            )
        } catch { onError?(error) }
    }

    private func process(_ message: WireMessage) throws -> WireMessage? {
        switch message {
        case .capture(let payload):
            guard role == .phone else { throw CaptureError.wrongTransportRole }
            try store.ingestOnPhone(payload)
            // Duplicate delivery is acknowledged too, after checking content.
            return .acknowledgement(payload.eventID)
        case .acknowledgement(let eventID):
            guard role == .watch else { throw CaptureError.wrongTransportRole }
            try store.acknowledge(eventID)
            return nil
        }
    }

    nonisolated public func session(
        _ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        let decoded = Result { try WireCodec.decode(userInfo) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let reply = try self.process(decoded.get()) {
                    guard self.session.activationState == .activated else {
                        throw CaptureError.sessionNotActivated
                    }
                    self.session.transferUserInfo(try WireCodec.encode(reply))
                }
            } catch { self.onError?(error) }
        }
    }

    nonisolated public func session(
        _ session: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let decoded = Result { try WireCodec.decode(message) }
        Task { @MainActor [weak self] in
            guard let self else {
                replyHandler(["error": "receiver-unavailable"])
                return
            }
            do {
                if let response = try self.process(decoded.get()) {
                    replyHandler(try WireCodec.encode(response))
                } else {
                    replyHandler(["received": true])
                }
            } catch {
                replyHandler(["error": "capture-not-acknowledged"])
                self.onError?(error)
            }
        }
    }

    nonisolated public func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            if let error { self?.onError?(error) }
            else { self?.flushOutbox() }
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.flushOutbox() }
    }

    nonisolated public func session(
        _ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        // Transfer completion is not a persistence ACK. Never delete outbox
        // entries here, and never start a tight retry loop after an error.
        if let error {
            Task { @MainActor [weak self] in self?.onError?(error) }
        }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
