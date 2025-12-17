{
  description = ''
    Pure and reproducible overlay for creating binary distributed rust toolchains.
  '';

  outputs =
    { self }:
    let
      overlay = import ./.;
    in
    {
      overlays = {
        default = overlay;
        rust-overlay = overlay;
      };
    };
}
