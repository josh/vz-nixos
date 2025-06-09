{
  system.stateVersion = "25.05";
  boot.loader.systemd-boot.enable = true;
  boot.initrd.kernelModules = [ "virtiofs" ];
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=256M" ];
  };
  fileSystems."/nix/store" = {
    device = "nix-store";
    fsType = "virtiofs";
    options = [ "ro" ];
  };
  users.mutableUsers = false;
  users.users.root.hashedPassword = "";
}
