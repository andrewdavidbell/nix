{
  description = "Manage macOS environment with nix-darwin and home-manager";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };
  outputs = inputs:
    let
      flakeContext = {
        inherit inputs;
      };
    in
    {
      darwinConfigurations = {
        Andrews-MacBook-Pro-M3 = import ./darwinConfigurations/Andrews-MacBook-Pro-M3.nix
          (flakeContext // { username = "adbell"; });
        Testers-Virtual-Machine = import ./darwinConfigurations/Testers-Virtual-Machine.nix
          (flakeContext // { username = "tester"; });
      };
      homeConfigurations = {
        adbell = import ./homeConfigurations/adbell.nix
          (flakeContext // { username = "adbell"; homeDirectory = "/Users/adbell"; });
        tester = import ./homeConfigurations/tester.nix
          (flakeContext // { username = "tester"; homeDirectory = "/Users/tester"; });
      };
    };
}
