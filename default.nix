{ pkgs ? import <nixpkgs> {} }:

with pkgs;

stdenv.mkDerivation rec {
  name = "zigfd";

  src = ./.;

  nativeBuildInputs = [ zig ];

  buildPhase = ''
    export HOME=$TMPDIR
    zig build
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp zig-cache/bin/zigfd $out/bin
  '';
}
