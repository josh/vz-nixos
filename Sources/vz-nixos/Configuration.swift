import Foundation

struct Configuration: Decodable {
  var cpuCount: Int?
  var memorySize: Int
  var bootspec: String
  var networkDevices: [NetworkDeviceConfiguration]?
  var timeout: TimeInterval?
}

struct NetworkDeviceConfiguration: Decodable {
  let type: NetworkDeviceConfigurationType
  let macAddress: String?
  let interfaceIdentifier: String?
  let socketPath: String?
  let socketFileDescriptor: Int32?
}

enum NetworkDeviceConfigurationType: String, Decodable {
  case nat
  case bridged
  case socket
}
