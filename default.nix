{pkgs ? import <nixpkgs> {}}:
pkgs.lib.packagesFromDirectoryRecursive {
  inherit (pkgs) callPackage newScope;
  directory = ./pkgs;
}
