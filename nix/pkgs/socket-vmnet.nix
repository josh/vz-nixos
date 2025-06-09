{ stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation (finalAttrs: {
  name = "socket-vmnet";
  version = "1.2.1";
  src = fetchurl {
    url = "https://github.com/lima-vm/socket_vmnet/releases/download/v${finalAttrs.version}/socket_vmnet-${finalAttrs.version}-arm64.tar.gz";
    sha256 = "sha256-fJfKz1NTvawSkuHTcciKArWVb1zTGHMvpR7HiRg2QQ8=";
  };
  installPhase = ''
    cp -R ./socket_vmnet $out
  '';
})
