{ system
  , compiler
  , flags
  , pkgs
  , hsPkgs
  , pkgconfPkgs
  , errorHandler
  , config
  , ... }:
  {
    flags = { development = false; };
    package = {
      specVersion = "1.10";
      identifier = { name = "measures"; version = "0.1.0.0"; };
      license = "Apache-2.0";
      copyright = "IOHK";
      maintainer = "operations@tbco.io";
      author = "IOHK";
      homepage = "";
      url = "";
      synopsis = "An abstraction for (tuples of) measured quantities";
      description = "";
      buildType = "Simple";
      isLocal = true;
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."base-deriving-via" or (errorHandler.buildDepError "base-deriving-via"))
          ];
        buildable = true;
        };
      tests = {
        "test" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."QuickCheck" or (errorHandler.buildDepError "QuickCheck"))
            (hsPkgs."tasty" or (errorHandler.buildDepError "tasty"))
            (hsPkgs."tasty-quickcheck" or (errorHandler.buildDepError "tasty-quickcheck"))
            (hsPkgs."measures" or (errorHandler.buildDepError "measures"))
            ];
          buildable = true;
          };
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/The-Blockchain-Company/bcc-base";
      rev = "e8a48cf0500b03c744c7fc6f2fedb86e8bdbe055";
      sha256 = "0s3w796y4bgjidg5iwapdq88cq9ipy346gagbip6xlqxdvpp99xj";
      }) // {
      url = "https://github.com/The-Blockchain-Company/bcc-base";
      rev = "e8a48cf0500b03c744c7fc6f2fedb86e8bdbe055";
      sha256 = "0s3w796y4bgjidg5iwapdq88cq9ipy346gagbip6xlqxdvpp99xj";
      };
    postUnpack = "sourceRoot+=/measures; echo source root reset to \$sourceRoot";
    }