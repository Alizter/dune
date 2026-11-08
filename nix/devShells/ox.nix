# Release tests use the opam-published compiler. The latest tag and
# trunk smoke tests build OxCaml with Dune from this source tree.
{
  pkgs,
  makeDuneDevShell,
  sourceDune,
  INSIDE_NIX,
}:

let
  oxcaml-setup = import ../oxcaml.nix { inherit pkgs; };
  duneVersion =
    let
      versionLine =
        pkgs.lib.findFirst (line: pkgs.lib.strings.hasPrefix "  let latest = " line)
          (throw "could not determine the Dune version")
          (pkgs.lib.strings.splitString "\n" (builtins.readFile ../../otherlibs/dune-rpc/types.ml));
      match = builtins.match "  let latest = ([0-9]+), ([0-9]+)" versionLine;
    in
    if match == null then
      throw "could not parse the Dune version from '${versionLine}'"
    else
      "${builtins.elemAt match 0}.${builtins.elemAt match 1}.0";
  sourceDuneForOx = sourceDune.overrideAttrs (old: {
    __intentionallyOverridingVersion = true;
    version = duneVersion;
    postPatch = (old.postPatch or "") + ''
      sed -i '/^(name dune)$/i(version ${duneVersion})' dune-project
    '';
  });
  compilerWithSourceDune =
    compiler:
    (compiler.override {
      withMerlin = false;
      withAstDependentLibs = false;
      withJsoo = false;
    }).overrideAttrs
      (old: {
        NIX_CFLAGS_COMPILE = "-std=gnu17";
        patches = (old.patches or [ ]) ++ [ ../patches/oxcaml-test-paths.patch ];
        passthru = (old.passthru or { }) // pkgs.ocamlPackages.ocaml.passthru;
        meta = (old.meta or { }) // pkgs.ocamlPackages.ocaml.meta;
        nativeBuildInputs = [
          sourceDuneForOx
        ]
        ++ builtins.filter (input: pkgs.lib.getName input != "dune") old.nativeBuildInputs;
        postFixup = ''
          remove-references-to -t ${sourceDuneForOx} $out/lib/ocaml/Makefile.config
        '';
      });
in
{
  bootstrap-ox = pkgs.mkShell {
    inherit INSIDE_NIX;
    buildInputs = [
      pkgs.gnumake
      oxcaml-setup.compiler
    ];
    meta.description = ''
      Provides a minimal shell environment with OxCaml in order to
      test the bootstrapping script.
    '';
  };

  bootstrap-ox-latest = pkgs.mkShell {
    inherit INSIDE_NIX;
    buildInputs = [
      pkgs.gnumake
      (compilerWithSourceDune oxcaml-setup.latestCompiler)
    ];
    meta.description = ''
      Builds the latest tagged OxCaml with this Dune, then tests
      bootstrapping Dune with that compiler.
    '';
  };

  ox-minimal = makeDuneDevShell {
    includeTestDeps = false;
    packageOverrides =
      oself: osuper:
      (oxcaml-setup.packageSet oself osuper)
      // {
        ocaml = oxcaml-setup.compiler;
      };
    meta.description = ''
      Provides a minimal shell environment with OxCaml in order to
      run the OxCaml tests.
    '';
  };

  # Like ox-minimal but with the OxCaml compiler rebuilt from the
  # `main` branch. Doubles as the trunk-build smoke test:
  # `.github/workflows/revdeps-dev-build.yml` runs
  #   nix develop .#ox-minimal-trunk --impure -c true
  # which forces the trunk compiler to build while keeping the rest
  # of the closure to the same minimal set as `ox-minimal`. Requires
  # `--impure` because the fetchGit ref moves.
  ox-minimal-trunk = makeDuneDevShell {
    includeTestDeps = false;
    packageOverrides =
      oself: osuper:
      (oxcaml-setup.packageSet oself osuper)
      // {
        ocaml =
          let
            oxcamlFlake = builtins.getFlake "github:oxcaml/oxcaml/main";
          in
          compilerWithSourceDune oxcamlFlake.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
    meta.description = ''
      Like ox-minimal but with the OxCaml trunk compiler.
    '';
  };

  ox = makeDuneDevShell {
    excludeTestNativeBuildInputs = [ "opam" ];
    excludeOcamlLibs = [
      "mdx"
      "merlin"
      "ocaml-index"
      "ocaml-lsp-server"
      "ppx_quick_test"
    ];
    extraBuildInputs =
      pkgs:
      [ pkgs.tree ]
      ++ (with pkgs.ocamlPackages; [
        js_of_ocaml
        js_of_ocaml-compiler
        wasm_of_ocaml-compiler
      ]);
    packageOverrides =
      oself: osuper:
      (oxcaml-setup.packageSet oself osuper)
      // {
        ocaml = oxcaml-setup.compiler;
      };
    meta.description = ''
      Provides a full shell environment with the OxCaml compiler to
      develop with Dune.
    '';
  };
}
