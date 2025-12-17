# rustup.nix

*Pure and reproducible* packaging of binary distributed rust toolchains.
Forked from [oxalica/rust-overlay], with all manifests removed.
This flake only provides a mechanism for creating a rust toolchain from a manifest file.
This approach has some advantages:

- The whole repository becomes a lot smaller because we don't need to include many years' worth of manifest files.

- Manifest file becomes an overridable flake input. Downstream flakes can choose to override the rust compiler used by an upstream flake.

## TODO

- Documentation

## License

MIT licensed.

[oxalica/rust-overlay]: https://github.com/oxalica/rust-overlay
[nixpkgs-mozilla]: https://github.com/mozilla/nixpkgs-mozilla
[rust-toolchain]: https://rust-lang.github.io/rustup/overrides.html#the-toolchain-file
[rust-profiles]: https://rust-lang.github.io/rustup/concepts/profiles.html
[miri]: https://github.com/rust-lang/miri
[`examples/cross-aarch64`]: https://github.com/oxalica/rust-overlay/tree/master/examples/cross-aarch64
