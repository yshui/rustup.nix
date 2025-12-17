final: prev:
let
  inherit (builtins) readFile fromTOML;

  rust-bin =
    (prev.rust-bin or { })
    // import ./lib/rust-bin.nix {
      inherit (final) lib;
      pkgs = final;
    };
in
{
  rustToolchainFromManifestFile = path: rust-bin.toolchainFromManifest (fromTOML (readFile path));
  rustToolchainFromRustcRev = rust-bin.fromRustcRev;
}
