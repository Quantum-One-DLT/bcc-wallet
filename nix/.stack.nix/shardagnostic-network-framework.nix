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
    flags = {};
    package = {
      specVersion = "1.10";
      identifier = {
        name = "shardagnostic-network-framework";
        version = "0.1.0.0";
        };
      license = "Apache-2.0";
      copyright = "2019 Input Output (Hong Kong) Ltd.";
      maintainer = "alex@well-typed.com, duncan@well-typed.com, marcin.szamotulski@blockchain-company.io";
      author = "Alexander Vieth, Duncan Coutts, Marcin Szamotulski";
      homepage = "";
      url = "";
      synopsis = "";
      description = "";
      buildType = "Simple";
      isLocal = true;
      };
    components = {
      "library" = {
        depends = [
          (hsPkgs."base" or (errorHandler.buildDepError "base"))
          (hsPkgs."async" or (errorHandler.buildDepError "async"))
          (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
          (hsPkgs."cborg" or (errorHandler.buildDepError "cborg"))
          (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
          (hsPkgs."dns" or (errorHandler.buildDepError "dns"))
          (hsPkgs."iproute" or (errorHandler.buildDepError "iproute"))
          (hsPkgs."hashable" or (errorHandler.buildDepError "hashable"))
          (hsPkgs."mtl" or (errorHandler.buildDepError "mtl"))
          (hsPkgs."nothunks" or (errorHandler.buildDepError "nothunks"))
          (hsPkgs."stm" or (errorHandler.buildDepError "stm"))
          (hsPkgs."text" or (errorHandler.buildDepError "text"))
          (hsPkgs."time" or (errorHandler.buildDepError "time"))
          (hsPkgs."quiet" or (errorHandler.buildDepError "quiet"))
          (hsPkgs."bcc-prelude" or (errorHandler.buildDepError "bcc-prelude"))
          (hsPkgs."contra-tracer" or (errorHandler.buildDepError "contra-tracer"))
          (hsPkgs."io-classes" or (errorHandler.buildDepError "io-classes"))
          (hsPkgs."monoidal-synchronisation" or (errorHandler.buildDepError "monoidal-synchronisation"))
          (hsPkgs."network" or (errorHandler.buildDepError "network"))
          (hsPkgs."network-mux" or (errorHandler.buildDepError "network-mux"))
          (hsPkgs."typed-protocols" or (errorHandler.buildDepError "typed-protocols"))
          (hsPkgs."Win32-network" or (errorHandler.buildDepError "Win32-network"))
          (hsPkgs."typed-protocols-examples" or (errorHandler.buildDepError "typed-protocols-examples"))
          ] ++ (pkgs.lib).optional (system.isWindows) (hsPkgs."Win32" or (errorHandler.buildDepError "Win32"));
        buildable = true;
        };
      exes = {
        "demo-ping-pong" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."async" or (errorHandler.buildDepError "async"))
            (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
            (hsPkgs."cborg" or (errorHandler.buildDepError "cborg"))
            (hsPkgs."directory" or (errorHandler.buildDepError "directory"))
            (hsPkgs."contra-tracer" or (errorHandler.buildDepError "contra-tracer"))
            (hsPkgs."io-classes" or (errorHandler.buildDepError "io-classes"))
            (hsPkgs."network-mux" or (errorHandler.buildDepError "network-mux"))
            (hsPkgs."shardagnostic-network-framework" or (errorHandler.buildDepError "shardagnostic-network-framework"))
            (hsPkgs."typed-protocols" or (errorHandler.buildDepError "typed-protocols"))
            (hsPkgs."typed-protocols-examples" or (errorHandler.buildDepError "typed-protocols-examples"))
            ] ++ (pkgs.lib).optionals (system.isWindows) [
            (hsPkgs."Win32-network" or (errorHandler.buildDepError "Win32-network"))
            (hsPkgs."Win32" or (errorHandler.buildDepError "Win32"))
            ];
          buildable = true;
          };
        };
      tests = {
        "test" = {
          depends = [
            (hsPkgs."base" or (errorHandler.buildDepError "base"))
            (hsPkgs."bytestring" or (errorHandler.buildDepError "bytestring"))
            (hsPkgs."cborg" or (errorHandler.buildDepError "cborg"))
            (hsPkgs."containers" or (errorHandler.buildDepError "containers"))
            (hsPkgs."directory" or (errorHandler.buildDepError "directory"))
            (hsPkgs."dns" or (errorHandler.buildDepError "dns"))
            (hsPkgs."iproute" or (errorHandler.buildDepError "iproute"))
            (hsPkgs."network" or (errorHandler.buildDepError "network"))
            (hsPkgs."serialise" or (errorHandler.buildDepError "serialise"))
            (hsPkgs."time" or (errorHandler.buildDepError "time"))
            (hsPkgs."QuickCheck" or (errorHandler.buildDepError "QuickCheck"))
            (hsPkgs."tasty" or (errorHandler.buildDepError "tasty"))
            (hsPkgs."tasty-quickcheck" or (errorHandler.buildDepError "tasty-quickcheck"))
            (hsPkgs."contra-tracer" or (errorHandler.buildDepError "contra-tracer"))
            (hsPkgs."io-sim" or (errorHandler.buildDepError "io-sim"))
            (hsPkgs."io-classes" or (errorHandler.buildDepError "io-classes"))
            (hsPkgs."network-mux" or (errorHandler.buildDepError "network-mux"))
            (hsPkgs."shardagnostic-network-framework" or (errorHandler.buildDepError "shardagnostic-network-framework"))
            (hsPkgs."typed-protocols" or (errorHandler.buildDepError "typed-protocols"))
            (hsPkgs."typed-protocols-examples" or (errorHandler.buildDepError "typed-protocols-examples"))
            ] ++ (pkgs.lib).optionals (system.isWindows) [
            (hsPkgs."Win32-network" or (errorHandler.buildDepError "Win32-network"))
            (hsPkgs."Win32" or (errorHandler.buildDepError "Win32"))
            ];
          buildable = true;
          };
        };
      };
    } // {
    src = (pkgs.lib).mkDefault (pkgs.fetchgit {
      url = "https://github.com/The-Blockchain-Company/shardagnostic-network";
      rev = "aa7bc087737edca29133844b14bb7cba2cd213f2";
      sha256 = "1rcjlj5z8igrfy07lkdrlm4xcx9a3g0jl69wvqk0vvff4hfr00ar";
      }) // {
      url = "https://github.com/The-Blockchain-Company/shardagnostic-network";
      rev = "aa7bc087737edca29133844b14bb7cba2cd213f2";
      sha256 = "1rcjlj5z8igrfy07lkdrlm4xcx9a3g0jl69wvqk0vvff4hfr00ar";
      };
    postUnpack = "sourceRoot+=/shardagnostic-network-framework; echo source root reset to \$sourceRoot";
    }