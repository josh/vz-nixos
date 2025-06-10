import Foundation
import Virtualization

extension Configuration {
  enum Error: Swift.Error {
    case unsupportedSystem
    case invalidMACAddress(String)
    case missingInterfaceIdentifier
    case invalidInterfaceIdentifier(String)
    case missingSocketPath
    case invalidSocketPath(String)
    case socketCreationFailed
    case socketConnectionFailed
  }

  static func load(from url: URL) throws -> Configuration {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(Configuration.self, from: data)
  }

  func createVirtualMachineConfiguration() throws -> VZVirtualMachineConfiguration {
    let configuration = VZVirtualMachineConfiguration()
    if let cpuCount {
      configuration.cpuCount = cpuCount
    }
    configuration.memorySize = UInt64(memorySize) * 1024 * 1024
    configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
    configuration.serialPorts = [createConsoleConfiguration()]
    configuration.bootLoader = try createBootLoader()
    configuration.networkDevices = try createNetworkDeviceConfigurations()
    configuration.directorySharingDevices = [createNixStoreSharingConfiguration()]
    try configuration.validate()
    return configuration
  }

  func createBootLoader() throws -> VZLinuxBootLoader {
    let data = try Data(contentsOf: URL(fileURLWithPath: self.bootspec))
    let decoder = JSONDecoder()
    let bootspec = try decoder.decode(Bootspec.self, from: data)
    let bootspecV1 = bootspec.bootspecV1

    guard bootspecV1.system == "aarch64-linux" else {
      throw Error.unsupportedSystem
    }

    let bootLoader = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: bootspecV1.kernel))

    if let initrd = bootspecV1.initrd {
      bootLoader.initialRamdiskURL = URL(fileURLWithPath: initrd)
    }

    let kernelParams =
      [
        "console=hvc0",
        "init=\(bootspecV1.`init`)",
      ] + bootspecV1.kernelParams
    bootLoader.commandLine = kernelParams.joined(separator: " ")

    return bootLoader
  }

  func createNetworkDeviceConfigurations() throws -> [VZNetworkDeviceConfiguration] {
    // Default to NAT if no network devices are configured
    guard let networkDevices else {
      let configuration = VZVirtioNetworkDeviceConfiguration()
      configuration.attachment = VZNATNetworkDeviceAttachment()
      return [configuration]
    }

    return try networkDevices.map { deviceConfiguration in
      var macAddress: VZMACAddress?
      if let macAddressString = deviceConfiguration.macAddress {
        if let validMACAddress = VZMACAddress(string: macAddressString) {
          macAddress = validMACAddress
        } else {
          throw Error.invalidMACAddress(macAddressString)
        }
      }

      switch deviceConfiguration.type {
      case .nat:
        let configuration = VZVirtioNetworkDeviceConfiguration()
        configuration.attachment = VZNATNetworkDeviceAttachment()
        if let macAddress {
          configuration.macAddress = macAddress
        }
        return configuration

      case .bridged:
        guard let interfaceIdentifier = deviceConfiguration.interfaceIdentifier else {
          throw Error.missingInterfaceIdentifier
        }
        guard
          let interface = VZBridgedNetworkInterface.networkInterfaces.first(where: {
            $0.identifier == interfaceIdentifier
          })
        else {
          throw Error.invalidInterfaceIdentifier(interfaceIdentifier)
        }

        let configuration = VZVirtioNetworkDeviceConfiguration()
        configuration.attachment = VZBridgedNetworkDeviceAttachment(interface: interface)
        if let macAddress {
          configuration.macAddress = macAddress
        }
        return configuration

      case .socket:
        guard let socketPath = deviceConfiguration.socketPath else {
          throw Error.missingSocketPath
        }

        let fileHandle = try createQEMUSocketBridge(socketPath: socketPath)
        let configuration = VZVirtioNetworkDeviceConfiguration()
        configuration.attachment = VZFileHandleNetworkDeviceAttachment(fileHandle: fileHandle)
        if let macAddress {
          configuration.macAddress = macAddress
        }
        return configuration
      }
    }
  }

  func createNixStoreSharingConfiguration() -> VZVirtioFileSystemDeviceConfiguration {
    let configuration = VZVirtioFileSystemDeviceConfiguration(tag: "nix-store")
    let directory = VZSharedDirectory(url: URL(fileURLWithPath: "/nix/store"), readOnly: true)
    let share = VZSingleDirectoryShare(directory: directory)
    configuration.share = share
    return configuration
  }

  func createConsoleConfiguration() -> VZSerialPortConfiguration {
    let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()

    let inputFileHandle = FileHandle.standardInput
    let outputFileHandle = FileHandle.standardOutput

    var attributes = termios()
    tcgetattr(inputFileHandle.fileDescriptor, &attributes)
    attributes.c_iflag &= ~tcflag_t(ICRNL)
    attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

    let stdioAttachment = VZFileHandleSerialPortAttachment(
      fileHandleForReading: inputFileHandle,
      fileHandleForWriting: outputFileHandle
    )

    consoleConfiguration.attachment = stdioAttachment

    return consoleConfiguration
  }

  private func createQEMUSocketBridge(socketPath: String) throws -> FileHandle {
    var sockets: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_DGRAM, 0, &sockets) == 0 else {
      throw Error.socketCreationFailed
    }
    
    let vzSocket = sockets[0]
    let bridgeSocket = sockets[1]
    
    let qemuSocket = socket(AF_UNIX, SOCK_STREAM, 0)
    guard qemuSocket != -1 else {
      close(vzSocket)
      close(bridgeSocket)
      throw Error.socketCreationFailed
    }
    
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
      close(vzSocket)
      close(bridgeSocket)
      close(qemuSocket)
      throw Error.invalidSocketPath(socketPath)
    }
    
    withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
      pathBytes.withUnsafeBytes { pathPtr in
        ptr.copyMemory(from: pathPtr)
      }
    }
    
    let addrSize = MemoryLayout<sa_family_t>.size + pathBytes.count
    let connectResult = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        connect(qemuSocket, sockPtr, socklen_t(addrSize))
      }
    }
    
    guard connectResult == 0 else {
      close(vzSocket)
      close(bridgeSocket)
      close(qemuSocket)
      throw Error.socketConnectionFailed
    }
    
    Task {
      await bridgeQEMUProtocol(vzSocket: bridgeSocket, qemuSocket: qemuSocket)
    }
    
    return FileHandle(fileDescriptor: vzSocket, closeOnDealloc: true)
  }
  
  private func bridgeQEMUProtocol(vzSocket: Int32, qemuSocket: Int32) async {
    await withTaskGroup(of: Void.self) { group in
      // VZ -> QEMU (add length header)
      group.addTask {
        var buffer = Data(count: 65536)
        while true {
          let bytesRead = buffer.withUnsafeMutableBytes { ptr in
            recv(vzSocket, ptr.baseAddress, ptr.count, 0)
          }
          
          guard bytesRead > 0 else { break }
          
          let packet = buffer.prefix(bytesRead)
          
          // Send length header (4 bytes, big endian)
          var length = UInt32(bytesRead).bigEndian
          let headerSent = withUnsafeBytes(of: &length) { ptr in
            send(qemuSocket, ptr.baseAddress, ptr.count, 0)
          }
          
          guard headerSent == 4 else { break }
          
          // Send packet data
          let dataSent = packet.withUnsafeBytes { ptr in
            send(qemuSocket, ptr.baseAddress, ptr.count, 0)
          }
          
          guard dataSent == bytesRead else { break }
        }
      }
      
      // QEMU -> VZ (remove length header)
      group.addTask {
        while true {
          // Read length header
          var lengthBuffer = Data(count: 4)
          let headerBytes = lengthBuffer.withUnsafeMutableBytes { ptr in
            recv(qemuSocket, ptr.baseAddress, ptr.count, MSG_WAITALL)
          }
          
          guard headerBytes == 4 else { break }
          
          let length = lengthBuffer.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self).bigEndian
          }
          
          guard length > 0 && length <= 65536 else { break }
          
          // Read packet data
          var packetBuffer = Data(count: Int(length))
          let packetBytes = packetBuffer.withUnsafeMutableBytes { ptr in
            recv(qemuSocket, ptr.baseAddress, ptr.count, MSG_WAITALL)
          }
          
          guard packetBytes == length else { break }
          
          // Send to VZ (without header)
          let sent = packetBuffer.withUnsafeBytes { ptr in
            send(vzSocket, ptr.baseAddress, ptr.count, 0)
          }
          
          guard sent == length else { break }
        }
      }
      
      // Wait for either direction to complete (indicating connection closed)
      await group.next()
      group.cancelAll()
    }
    
    // Cleanup
    close(vzSocket)
    close(qemuSocket)
  }
}
