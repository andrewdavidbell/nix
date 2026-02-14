{ inputs, username, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config.nix-homebrew = {
    autoMigrate = true;
    enable = true;
    enableRosetta = false;
    user = username;
  };
}
