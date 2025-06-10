{
  writers,
  runCommand,
  jq,
  vz-nixos,
  nixosToplevel,
}:
let
  config = writers.writeJSON "minimal-boot-config.json" {
    bootspec = "${nixosToplevel}/boot.json";
    memorySize = 1024;
    timeout = 15;
  };
in
runCommand "minimal-boot"
  {
    nativeBuildInputs = [
      jq
      vz-nixos
    ];
    requiredSystemFeatures = [ "apple-virt" ];
    meta.platforms = [ "aarch64-darwin" ];
  }
  ''
    vz-nixos ${config} 2>&1 | tee boot.log || true
    grep "NixOS Stage 1" boot.log
    grep "NixOS Stage 2" boot.log
    grep "Welcome to NixOS" boot.log
    touch $out
  ''
