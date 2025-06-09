{
  lib,
  darwin,
  swiftPackages,
  swift,
  swiftpm,
}:
swiftPackages.stdenv.mkDerivation (_finalAttrs: {
  pname = "vz-nixos";
  version = "0.0.0";

  src = ../../.;

  nativeBuildInputs = [
    swift
    swiftpm
    darwin.sigtool
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 .build/release/vz-nixos $out/bin/vz-nixos
    runHook postInstall
  '';

  postFixup = ''
    codesign --entitlements ${../../signing/vz.entitlements} --force --sign - "$out/bin/vz-nixos"
  '';

  meta = {
    description = "TK";
    homepage = "https://github.com/josh/vz-nixos";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "vz-nixos";
  };
})
