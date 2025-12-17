# Component resolution, aggregation and other utility functions.
# Provide the content of `rust-bin`.
{
  lib,
  pkgs,
}:
let
  inherit (builtins)
    match
    ;

  inherit (lib)
    any
    attrNames
    attrValues
    concatStringsSep
    elem
    elemAt
    filter
    flatten
    isString
    listToAttrs
    makeOverridable
    mapAttrs
    mapAttrsToList
    optional
    optionalAttrs
    replaceStrings
    substring
    unique
    ;

  inherit (pkgs) stdenv callPackage fetchurl;

  # Remove keys from attrsets whose value is null.
  removeNulls = set: removeAttrs set (filter (name: set.${name} == null) (attrNames set));

  toRustTarget = platform: platform.rust.rustcTarget;

  # The platform where `rustc` is running.
  rustHostPlatform = toRustTarget stdenv.hostPlatform;
  # The platform of binary which `rustc` produces.
  rustTargetPlatform = toRustTarget stdenv.targetPlatform;

  mkComponentSet = callPackage ./mk-component-set.nix {
    inherit removeNulls toRustTarget;
  };

  mkAggregated = callPackage ./mk-aggregated.nix { };

  mkComponentSrc =
    { url, sha256 }:
    let
      url' = replaceStrings [ " " ] [ "%20" ] url; # This is required or download will fail.
      # Filter names like `llvm-tools-1.34.2 (6c2484dc3 2019-05-13)-aarch64-unknown-linux-gnu.tar.xz`
      matchParenPart = match ".*/([^ /]*) [(][^)]*[)](.*)" url;
    in
    # NB: This seems verbose, but we do not know the default special-cased `name` is.
    # It used to be "", but changed to `null` later. We also do not know the exact
    # revision of nixpkgs we are currently using.
    # See: <http://github.com/NixOS/nixpkgs/commit/1ec0227cc062251c36140ef1e7c37b1cd1b370f1>
    if matchParenPart != null then
      fetchurl {
        name = (elemAt matchParenPart 0) + (elemAt matchParenPart 1);
        inherit sha256;
        url = url';
      }
    else
      fetchurl {
        inherit sha256;
        url = url';
      };

  # Resolve final components to install from mozilla-overlay style `extensions`, `targets` and `targetExtensions`.
  #
  # `componentSet` has a layout of `componentSet.<name>.<rust-target> : Derivation`.
  # `targetComponentsList` is a list of all component names for target platforms.
  # `name` is only used for error message.
  #
  # Returns a list of component derivations, or throw if failed.
  resolveComponents =
    {
      name,
      componentSet,
      allComponentSet,
      allPlatformSet,
      targetComponentsList,
      profileComponents,
      extensions,
      targets,
      targetExtensions,
    }:
    let
      # Components for target platform like `rust-std`.
      collectTargetComponents =
        allowMissing: name:
        let
          targetSelected = flatten (map (tgt: componentSet.${tgt}.${name} or [ ]) targets);
        in
        if !allowMissing -> targetSelected != [ ] then
          targetSelected
        else
          "Component `${name}` doesn't support any of targets: ${concatStringsSep ", " targets}";

      collectComponents =
        allowMissing: name:
        if elem name targetComponentsList then
          collectTargetComponents allowMissing name
        else
          # Components for host platform like `rustc`.
          componentSet.${rustHostPlatform}.${name}
            or (if allowMissing then [ ] else "Host component `${name}` doesn't support `${rustHostPlatform}`");

      # Profile components can be skipped silently when missing.
      # Eg. `rust-mingw` on non-Windows platforms, or `rust-docs` on non-tier1 platforms.
      result =
        flatten (map (collectComponents true) profileComponents)
        ++ flatten (map (collectComponents false) extensions)
        ++ flatten (map (collectTargetComponents false) targetExtensions);

      isTargetUnused =
        target:
        !any (name: componentSet ? ${target}.${name})
          # FIXME: Get rid of the legacy component `rust`.
          (
            filter (name: name == "rust" || elem name targetComponentsList) (profileComponents ++ extensions)
            ++ targetExtensions
          );

      # Fail-fast for typo in `targets`, `extensions`, `targetExtensions`.
      fastErrors = flatten (
        map (
          tgt:
          optional (
            !(allPlatformSet ? ${tgt})
          ) "Unknown target `${tgt}`, typo or not supported by this version?"
        ) targets
        ++ map (
          name:
          optional (
            !(allComponentSet ? ${name})
          ) "Unknown component `${name}`, typo or not support by this version?"
        ) (profileComponents ++ extensions ++ targetExtensions)
      );

      errors =
        if fastErrors != [ ] then
          fastErrors
        else
          filter isString result
          ++ map (tgt: "Target `${tgt}` is not supported by any components or extensions") (
            filter isTargetUnused targets
          );

      notes = [
        "note: profile components: ${toString profileComponents}"
      ]
      ++ optional (targets != [ ]) "note: selected targets: ${toString targets}"
      ++ optional (extensions != [ ]) "note: selected extensions: ${toString extensions}"
      ++ optional (
        targetExtensions != [ ]
      ) "note: selected targetExtensions: ${toString targetExtensions}"
      ++ flatten (
        map (
          platform:
          optional (componentSet ? ${platform})
            "note: components available for ${platform}: ${toString (attrNames componentSet.${platform})}"
        ) (unique ([ rustHostPlatform ] ++ targets))
      )
      ++ [
        ''
          note: check here to see all targets and which components are available on each targets:
                https://rust-lang.github.io/rustup-components-history
        ''
      ];

    in
    if errors == [ ] then
      result
    else
      throw ''
        Component resolution failed for ${name}
        ${concatStringsSep "\n" (errors ++ notes)}
      '';

  # Generate the toolchain set from a parsed manifest.
  #
  # Manifest files are organized as follow:
  #
  # ```
  # manifest-version = "2"
  # date = "2017-03-03";
  # [pkg.cargo]
  # version= "0.18.0-nightly (5db6d64 2017-03-03)";
  #
  # [pkg.cargo.target.x86_64-unknown-linux-gnu]
  # available = true;
  # hash = "abce..."; # sha256
  # url = "https://static.rust-lang.org/dist/....tar.gz";
  # xz_hash = "abce..."; # sha256
  # xz_url = "https://static.rust-lang.org/dist/....tar.xz";
  # ```
  #
  # The packages available usually are:
  #   cargo, rust-analysis, rust-docs, rust-src, rust-std, rustc, and
  #   rust, which aggregates them in one package.
  #
  # For each package the following options are available:
  #   extensions        - The extensions that should be installed for the package.
  #                       For example, install the package rust and add the extension rust-src.
  #   targets           - The package will always be installed for the host system, but with this option
  #                       extra targets can be specified, e.g. "mips-unknown-linux-musl". The target
  #                       will only apply to components of the package that support being installed for
  #                       a different architecture. For example, the rust package will install rust-std
  #                       for the host system and the targets.
  #   targetExtensions  - If you want to force extensions to be installed for the given targets, this is your option.
  #                       All extensions in this list will be installed for the target architectures.
  #                       *Attention* If you want to install an extension like rust-src, that has no fixed architecture (arch *),
  #                       you will need to specify this extension in the extensions options or it will not be installed!
  toolchainFromManifest =
    manifest:
    let
      # platform -> true
      # For fail-fast test.
      allPlatformSet = listToAttrs (
        flatten (
          mapAttrsToList (
            compName:
            { target, ... }:
            map (platform: {
              name = platform;
              value = true;
            }) (attrNames target)
          ) manifest.pkg
        )
      );

      # componentName -> true
      # May also contains unavailable components. Just for fail-fast test.
      allComponentSet = mapAttrs (compName: _: true) (manifest.pkg // manifest.renames);

      # componentSet.x86_64-unknown-linux-gnu.cargo = <derivation>;
      componentSet = mapAttrs (
        platform: _:
        mkComponentSet {
          inherit (manifest) renames;
          inherit platform;
          srcs = removeNulls (
            mapAttrs (
              compName:
              { target, version, ... }:
              let
                content = target.${platform} or target."*" or null;
              in
              if content == null then
                null
              else
                {
                  src = mkComponentSrc {
                    url = content.xz_url;
                    sha256 = content.xz_hash;
                  };
                  inherit version;
                }
            ) manifest.pkg
          );
        }
      ) allPlatformSet;

      mkProfile =
        name: profileComponents:
        makeOverridable
          (
            {
              extensions,
              targets,
              targetExtensions,
            }:
            mkAggregated {
              pname = "rust-${name}";
              inherit (manifest) date;
              availableComponents = componentSet.${rustHostPlatform};
              selectedComponents = resolveComponents {
                name = "rust-${name}-${manifest.date}";
                inherit
                  allPlatformSet
                  allComponentSet
                  componentSet
                  profileComponents
                  targetExtensions
                  ;
                targetComponentsList = [
                  "rust-std"
                  "rustc-dev"
                  "rustc-docs"
                ];
                extensions = extensions;
                targets = unique (
                  [
                    rustHostPlatform # Build script requires host std.
                    rustTargetPlatform
                  ]
                  ++ targets
                );
              };
            }
          )
          {
            extensions = [ ];
            targets = [ ];
            targetExtensions = [ ];
          };

      profiles = mapAttrs mkProfile manifest.profiles;

      result =
        # Individual components.
        componentSet.${rustHostPlatform}
        //
          # Profiles.
          profiles;

    in
    # If the platform is not supported for the current version, return nothing here,
    # so others can easily check it by `toolchain ? default`.
    optionalAttrs (componentSet ? ${rustHostPlatform}) result
    // {
      # Internal use.
      _components = componentSet;
      _profiles = profiles;
      _date = manifest.date;
      _manifest = manifest;
    };

  # From a git revision of rustc.
  # This does the same thing as crate `rustup-toolchain-install-master`.
  # But you need to manually provide component hashes.
  fromRustcRev =
    {
      # Package name of the derivation.
      pname ? "rust-custom",
      # Git revision of rustc.
      rev,
      # Version of the built package.
      version ? substring 0 7 rev,
      # Attrset with component name as key and its SRI hash as value.
      components,
      # Rust target to download.
      target ? rustTargetPlatform,
    }:
    let
      hashToSrc = compName: hash: {
        src = fetchurl {
          url =
            if compName == "rust-src" then
              "https://ci-artifacts.rust-lang.org/rustc-builds/${rev}/${compName}-nightly.tar.xz"
            else
              "https://ci-artifacts.rust-lang.org/rustc-builds/${rev}/${compName}-nightly-${target}.tar.xz";
          inherit hash;
        };
        inherit version;
      };
      components' = mkComponentSet {
        platform = target;
        srcs = mapAttrs hashToSrc components;
        # We cannot know aliases in this case.
        renames = { };
      };
    in
    mkAggregated {
      inherit pname version;
      date = null;
      selectedComponents = attrValues components';
    };

in
{
  inherit fromRustcRev toolchainFromManifest;
}
