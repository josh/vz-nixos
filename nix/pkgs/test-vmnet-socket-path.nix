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
        socketPath = "/var/run/socket_vmnet.test.sock";
      }
    ];
    memorySize = 1024;
  };
in
writeShellApplication {
  name = "test-vmnet-socket-path";
  runtimeInputs = [
    darwin.sudo
    socket-vmnet
    vz-nixos
  ];
  text = ''
    set -o xtrace
    vz-nixos ${config}
  '';
}
