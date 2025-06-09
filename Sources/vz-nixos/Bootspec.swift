// https://github.com/NixOS/rfcs/blob/master/rfcs/0125-bootspec.md

struct Bootspec: Decodable {
  let bootspecV1: BootspecV1

  enum CodingKeys: String, CodingKey {
    case bootspecV1 = "org.nixos.bootspec.v1"
  }
}

struct BootspecV1: Decodable {
  let system: String
  let `init`: String
  let initrd: String?
  let initrdSecrets: String?
  let kernel: String
  let kernelParams: [String]
  let label: String
  let toplevel: String
}
