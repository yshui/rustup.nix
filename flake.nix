{
  description = ''
    Pure and reproducible overlay for creating binary distributed rust toolchains.
  '';

  outputs =
    _:
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
