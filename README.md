# rustup.nix

*Pure and reproducible* packaging of binary distributed rust toolchains.
Derived from [oxalica/rust-overlay], with all manifests removed.

This flake provides only a mechanism for creating a rust toolchain from a manifest file.

This approach has some advantages:

- The whole repository becomes tiny because we don't need to include many years' worth of manifest files.
- Much more flexibility in how the manifest file is supplied.
- Manifest file becomes an overridable flake input. Downstream flakes can choose to override the rust compiler used by an upstream flake.

## Usage

See [example](https://github.com/yshui/rustup.nix-examples/blob/next/flake.nix)

## License

MIT

## Acknowledgement

- [oxalica/rust-overlay]
- [nixpkgs-mozilla]
- [fenix]

[oxalica/rust-overlay]: https://github.com/oxalica/rust-overlay
[nixpkgs-mozilla]: https://github.com/mozilla/nixpkgs-mozilla
[fenix]: https://github.com/nix-community/fenix
