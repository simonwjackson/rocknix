{
  description = "Minimal ROCKNIX Layer 10b bootable nspawn guest rootfs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };
      configuration = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./rocknix-guest.nix ];
      };
      toplevel = configuration.config.system.build.toplevel;
      closure = pkgs.closureInfo {
        rootPaths = [ toplevel ];
      };
      rootfs = pkgs.runCommand "rocknix-layer10b-guest-rootfs" {
        nativeBuildInputs = [ pkgs.coreutils pkgs.gnutar pkgs.zstd ];
      } ''
        mkdir -p root/nix/store root/sbin root/tmp root/proc root/sys root/dev root/run $out/tarball
        chmod 1777 root/tmp
        while IFS= read -r store_path; do
          cp -a "$store_path" root/nix/store/
        done < ${closure}/store-paths
        ln -s ${toplevel}/init root/init
        ln -s ${toplevel}/init root/sbin/init
        ln -s ${toplevel}/etc root/etc
        tar --sort=name --numeric-owner --owner=0 --group=0 --zstd \
          -cf $out/tarball/rocknix-layer10b-guest-rootfs-aarch64-linux.tar.zst \
          -C root .
      '';
    in {
      nixosConfigurations.rocknix-guest = configuration;
      packages.${system} = {
        rootfs = rootfs;
        default = self.packages.${system}.rootfs;
      };
    };
}
