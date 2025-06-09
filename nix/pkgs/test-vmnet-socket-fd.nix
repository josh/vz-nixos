{
  writers,
  writeShellApplication,
  darwin,
  vz-nixos,
  socket-vmnet,
  nixosToplevel,
}:
let
  config = writers.writeJSON "config.json" {
    bootspec = "${nixosToplevel}/boot.json";
    networkDevices = [
      {
        type = "socket";
        socketFileDescriptor = 3;
      }
    ];
    memorySize = 1024;
  };
in
writeShellApplication {
  name = "test-vmnet-socket-fd";
  runtimeInputs = [
    darwin.sudo
    socket-vmnet
    vz-nixos
  ];
  text = ''
    set -o xtrace
    socket_vmnet_client /var/run/socket_vmnet.test.sock vz-nixos ${config}
  '';
}
