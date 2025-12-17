{
  description = ''
    Pure and reproducible overlay for creating binary distributed rust toolchains.
  '';

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      overlay = import ./.;

      # Builder to construct `rust-bin` interface on an existing `pkgs`.
      # This would be immutable, non-intrusive and (hopefully) can benefit from
      # flake eval-cache.
      #
      # Note that this does not contain compatible attrs for mozilla-overlay.
      mkRustBin =
        pkgs:
        import ./lib/rust-bin.nix {
          inherit lib pkgs;
        };

    in
    {
      lib = {
        inherit mkRustBin;
      };

      overlays = {
        default = overlay;
        rust-overlay = overlay;
      };
    };
}
