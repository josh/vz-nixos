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
        guard let socketFileDescriptor = deviceConfiguration.socketFileDescriptor else {
          throw Error.missingSocketPath
        }

        let fileHandle = FileHandle(fileDescriptor: socketFileDescriptor, closeOnDealloc: true)
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
}
