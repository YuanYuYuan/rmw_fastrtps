{
  description = "rmw_fastrtps_cpp: a buffer-aware publisher stops writing to a legacy subscriber that joins after a buffer-aware one left";

  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };

  inputs.nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/44623a4d46459f9b58a046851004bd3a0c57f115";

  outputs = { self, nix-ros-overlay }:
    let
      system = "x86_64-linux";
      pkgs = import nix-ros-overlay.inputs.nixpkgs {
        inherit system;
        overlays = [ nix-ros-overlay.overlays.default ];
      };
    in
    {
      packages.${system} = import ./nix/ab.nix { inherit pkgs; rosPackages = pkgs.rosPackages.rolling; };
    };
}
