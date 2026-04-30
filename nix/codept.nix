{ pkgs }:

let
  src = pkgs.fetchFromGitHub {
    owner = "Octachron";
    repo = "codept";
    rev = "0.12.2";
    hash = "sha256-kfz650H0sU0xBXKgWnoqPMTHnJYhV3ozsT5b9KKYpsg=";
  };

  codept-lib = pkgs.ocamlPackages.buildDunePackage {
    pname = "codept-lib";
    version = "0.12.2";
    inherit src;
    nativeBuildInputs = with pkgs.ocamlPackages; [ menhir ];
    doCheck = false;
  };
in

pkgs.ocamlPackages.buildDunePackage {
  pname = "codept";
  version = "0.12.2";
  inherit src;
  nativeBuildInputs = with pkgs.ocamlPackages; [ menhir ];
  buildInputs = [ codept-lib ];
  doCheck = false;
}
