{
  description = "Manage macOS environment with nix-darwin and home-manager";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
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
        Tests-Virtual-Machine = import ./darwinConfigurations/Tests-Virtual-Machine.nix
          (flakeContext // { username = "testaccount"; });
      };
      homeConfigurations = {
        adbell = import ./homeConfigurations/adbell.nix
          (flakeContext // { username = "adbell"; homeDirectory = "/Users/adbell"; });
        testaccount = import ./homeConfigurations/testaccount.nix
          (flakeContext // { username = "testaccount"; homeDirectory = "/Users/testaccount"; });
      };
    };
}
