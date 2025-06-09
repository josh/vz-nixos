import Foundation
import Virtualization

guard CommandLine.arguments.count == 2 else {
  print("usage: \(CommandLine.arguments[0]) <config>")
  exit(EXIT_FAILURE)
}

let configFileURL = URL(fileURLWithPath: CommandLine.arguments[1])
let config = try! Configuration.load(from: configFileURL)
let configuration = try! config.createVirtualMachineConfiguration()

let virtualMachine = VZVirtualMachine(configuration: configuration)

let delegate = Delegate()
virtualMachine.delegate = delegate

virtualMachine.start { (result) in
  if case let .failure(error) = result {
    print("Failed to start the virtual machine. \(error)")
    exit(EXIT_FAILURE)
  }
}

if let timeout = config.timeout {
  RunLoop.main.run(until: Date(timeIntervalSinceNow: timeout))
} else {
  RunLoop.main.run(until: Date.distantFuture)
}

class Delegate: NSObject {
}

extension Delegate: VZVirtualMachineDelegate {
  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    print("The guest shut down. Exiting.")
    exit(EXIT_SUCCESS)
  }
}
