import Darwin
import Foundation
import ParloqMenuCore

enum DictateClientError: LocalizedError {
    case pathTooLong
    case socket(Int32)
    case connect(Int32)
    case closed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .pathTooLong:
            return "Dictation socket path is too long"
        case let .socket(code):
            return "Could not create dictation socket: \(String(cString: strerror(code)))"
        case let .connect(code):
            return "Could not connect to dictation daemon: \(String(cString: strerror(code)))"
        case .closed:
            return "Dictation daemon closed the connection"
        case .invalidResponse:
            return "Dictation daemon returned an invalid response"
        }
    }
}

final class UnixSocketClient: @unchecked Sendable {
    private let socketPath: String
    private let subscriptionQueue = DispatchQueue(
        label: "net.attobop.parloq.subscription",
        qos: .userInitiated
    )
    private let commandQueue = DispatchQueue(
        label: "net.attobop.parloq.commands",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var cancelled = false
    private var subscriptionDescriptor: Int32 = -1

    var onEvent: (@MainActor @Sendable (DictateEvent) -> Void)?
    var onConnectionChange: (@MainActor @Sendable (Bool, String?) -> Void)?

    init(socketPath: String = UnixSocketClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    static var defaultSocketPath: String {
        if let override = ProcessInfo.processInfo.environment[
            "RECORDER_DICTATE_SOCK"
        ], !override.isEmpty {
            return override
        }
        return "/tmp/recorder-dictate-\(getuid()).sock"
    }

    func startSubscription() {
        subscriptionQueue.async { [weak self] in
            self?.subscriptionLoop()
        }
    }

    func cancel() {
        stateLock.lock()
        cancelled = true
        let descriptor = subscriptionDescriptor
        subscriptionDescriptor = -1
        stateLock.unlock()
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
        }
    }

    func send(_ command: DictateCommand) {
        send(DictateRequest(command: command))
    }

    func send(_ request: DictateRequest) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            do {
                let descriptor = try self.connectSocket()
                defer { Darwin.close(descriptor) }
                try self.sendRequest(request, to: descriptor)
                guard let line = try self.readLine(from: descriptor) else {
                    throw DictateClientError.invalidResponse
                }
                let event = try JSONDecoder().decode(
                    DictateEvent.self, from: line)
                Task { @MainActor [weak self] in
                    self?.onEvent?(event)
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.onConnectionChange?(false, error.localizedDescription)
                }
            }
        }
    }

    private func subscriptionLoop() {
        while !isCancelled {
            do {
                let descriptor = try connectSocket()
                setSubscriptionDescriptor(descriptor)
                defer { clearAndCloseSubscription(descriptor) }
                try sendRequest(
                    DictateRequest(command: .subscribe),
                    to: descriptor
                )
                Task { @MainActor [weak self] in
                    self?.onConnectionChange?(true, nil)
                }
                while !isCancelled,
                      let line = try readLine(from: descriptor) {
                    let event = try JSONDecoder().decode(
                        DictateEvent.self, from: line)
                    Task { @MainActor [weak self] in
                        self?.onEvent?(event)
                    }
                }
                if !isCancelled {
                    throw DictateClientError.closed
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.onConnectionChange?(false, error.localizedDescription)
                }
                if !isCancelled {
                    Thread.sleep(forTimeInterval: 1)
                }
            }
        }
    }

    private var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    private func setSubscriptionDescriptor(_ descriptor: Int32) {
        stateLock.lock()
        subscriptionDescriptor = descriptor
        stateLock.unlock()
    }

    private func clearAndCloseSubscription(_ descriptor: Int32) {
        stateLock.lock()
        if subscriptionDescriptor == descriptor {
            subscriptionDescriptor = -1
        }
        stateLock.unlock()
        Darwin.close(descriptor)
    }

    private func connectSocket() throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw DictateClientError.socket(errno)
        }
        var noSigPipe: Int32 = 1
        guard Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw DictateClientError.socket(code)
        }

        do {
            try withSocketAddress(path: socketPath) { address, length in
                guard Darwin.connect(descriptor, address, length) == 0 else {
                    throw DictateClientError.connect(errno)
                }
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func withSocketAddress<T>(
        path: String,
        body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
    ) throws -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(
            ofValue: address.sun_path)
        guard bytes.count <= capacity else {
            throw DictateClientError.pathTooLong
        }
        withUnsafeMutableBytes(
            of: &address.sun_path
        ) { (buffer: UnsafeMutableRawBufferPointer) -> Void in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = UInt8(bitPattern: byte)
            }
        }
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(
                to: sockaddr.self, capacity: 1
            ) { sockaddrPointer in
                try body(
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
    }

    private func sendRequest(
        _ request: DictateRequest,
        to descriptor: Int32
    ) throws {
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let count = Darwin.send(
                    descriptor,
                    base.advanced(by: sent),
                    rawBuffer.count - sent,
                    0
                )
                guard count > 0 else {
                    throw DictateClientError.closed
                }
                sent += count
            }
        }
    }

    private func readLine(from descriptor: Int32) throws -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < 65_536 {
            let count = Darwin.recv(descriptor, &byte, 1, 0)
            if count == 0 {
                return data.isEmpty ? nil : data
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw DictateClientError.closed
            }
            if byte == 0x0A {
                return data
            }
            data.append(byte)
        }
        throw DictateClientError.invalidResponse
    }
}
