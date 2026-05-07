{
  description = "Minimal ROCKNIX Layer 10b bootable nspawn guest rootfs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      targetSystem = "aarch64-linux";
      hostSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllHostSystems = nixpkgs.lib.genAttrs hostSystems;
      configuration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [ ./rocknix-guest.nix ];
      };
      toplevel = configuration.config.system.build.toplevel;
      mkRootfs = hostSystem:
        let
          pkgs = import nixpkgs { system = hostSystem; };
          closure = pkgs.closureInfo {
            rootPaths = [ toplevel ];
          };
        in pkgs.runCommand "rocknix-layer10b-guest-rootfs" {
          nativeBuildInputs = [ pkgs.coreutils pkgs.gnutar pkgs.zstd ];
        } ''
          mkdir -p root/nix/store root/sbin root/tmp root/proc root/sys root/dev root/run root/etc root/var root/var/lib $out/tarball
          chmod 1777 root/tmp
          while IFS= read -r store_path; do
            cp -a "$store_path" root/nix/store/
          done < ${closure}/store-paths
          ln -s ${toplevel}/init root/init
          ln -s ${toplevel}/init root/sbin/init
          cp -a ${toplevel}/etc/. root/etc/
          chmod -R u+w root/etc
          tar --sort=name --numeric-owner --owner=0 --group=0 --zstd \
            -cf $out/tarball/rocknix-layer10b-guest-rootfs-aarch64-linux.tar.zst \
            -C root .
        '';
    in {
      nixosConfigurations.rocknix-guest = configuration;
      packages = forAllHostSystems (hostSystem:
        let
          rootfs = mkRootfs hostSystem;
        in {
          inherit rootfs;
          default = rootfs;
        });
    };
}
