######################################################################
#
# Creates a development environment for Cabal builds or ghci sessions,
# with various build tools included.
#
# Short instructions are in ./cabal.project.
#
# Full instructions - https://github.com/The-Blockchain-Company/bcc-wallet/wiki/Building#cabalnix-build
#
# If you need a nix-shell with Cabal, GHC, and system dependencies, but *without*
# Haskell dependencies, see ./nix/cabal-shell.nix.
#
######################################################################

{ walletPackages ? import ./default.nix { inherit system crossSystem config sourcesOverride; }
, system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
, pkgs ? walletPackages.private.pkgs
, profiling ? false  # enable profiling in haskell dependencies
, sourcesOverride ? {}  # see sourcesOverride in nix/default.nix
}:

let
  inherit (pkgs) lib;
  inherit (pkgs.haskell-nix.haskellLib) selectProjectPackages;

  mkShell = name: project: project.shellFor rec {
    inherit name;
    packages = ps: lib.attrValues (selectProjectPackages ps);
    nativeBuildInputs = (with walletPackages; [
        bcc-node
        bcc-cli
        bcc-address
        bech32
        project.hsPkgs.pretty-simple.components.exes.pretty-simple
      ]) ++ (with pkgs.buildPackages.buildPackages; [
        go-jira
        haskellPackages.ghcid
        niv
        pkgconfig
        python3Packages.openapi-spec-validator
        (ruby.withPackages (ps: [ ps.thor ]))
        sqlite-interactive
        curlFull
        jq
        yq
        cabalWrapped
      ] ++ lib.filter
        (drv: lib.isDerivation drv && drv.name != "regenerate-materialized-nix")
        (lib.attrValues haskell-build-tools));

    # fixme: this is needed to prevent Haskell.nix double-evaluating hoogle
    tools.hoogle = {
      inherit (pkgs.haskell-build-tools.hoogle) version;
      inherit (pkgs.haskell-build-tools.hoogle.project) index-state;
      checkMaterialization = false;
      materialized = ./nix/materialized/hoogle;
    };

    BCC_NODE_CONFIGS = pkgs.bcc-node-deployments;

    meta.platforms = lib.platforms.unix;
  };
in
  with walletPackages.private;
  if profiling
    then mkShell "bcc-wallet-shell-profiled" profiledProject
    else mkShell "bcc-wallet-shell" project
