{
  description = "Minimal ROCKNIX Layer 10b bootable nspawn guest rootfs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # External package-only monorepo for SM8550 emulator packages.
    nix-sm8550.url = "github:simonwjackson/nix-sm8550";
  };

  outputs = { self, nixpkgs, nix-sm8550 }:
    let
      targetSystem = "aarch64-linux";
      hostSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllHostSystems = nixpkgs.lib.genAttrs hostSystems;
      configuration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [ ./rocknix-guest.nix ];
      };
      mainSpaceConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [
          ./profiles/main-space.nix
          ({ ... }: {
            # Make the package-only monorepo the Cemu source of truth for the
            # main-space guest while keeping ROCKNIX launch/storage/perf glue
            # downstream in this repository.
            nix.registry.nix-sm8550.flake = nix-sm8550;
            environment.systemPackages = [ nix-sm8550.packages.${targetSystem}.cemu ];
          })
        ];
      };
      devEnvConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [ ./profiles/dev-env.nix ];
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
          mkdir -p root/nix/store root/sbin root/usr/bin root/tmp root/proc root/sys root/dev root/run root/etc root/var root/var/lib $out/tarball
          chmod 1777 root/tmp
          while IFS= read -r store_path; do
            cp -a "$store_path" root/nix/store/
          done < ${closure}/store-paths
          ln -s ${toplevel}/init root/init
          ln -s ${toplevel}/init root/sbin/init
          ln -s /run/current-system/sw/bin/nix root/usr/bin/nix
          cp -a ${toplevel}/etc/. root/etc/
          chmod -R u+w root/etc
          if [ -e root/etc/static/ssh/sshd_config ]; then
            mkdir -p root/etc/ssh
            rm -f root/etc/ssh/sshd_config
            cp -L root/etc/static/ssh/sshd_config root/etc/ssh/sshd_config
            chmod u+w root/etc/ssh/sshd_config
          fi
          mkdir -p root/etc/ssh/authorized_keys.d
          rm -f root/etc/ssh/authorized_keys.d/root
          : > root/etc/ssh/authorized_keys.d/root
          chmod 600 root/etc/ssh/authorized_keys.d/root
          tar --sort=name --numeric-owner --owner=0 --group=0 --zstd \
            -cf $out/tarball/rocknix-layer10b-guest-rootfs-aarch64-linux.tar.zst \
            -C root .
        '';
    in {
      nixosConfigurations.rocknix-guest = configuration;
      nixosConfigurations.rocknix-guest-main-space = mainSpaceConfiguration;
      nixosConfigurations.rocknix-guest-dev-env = devEnvConfiguration;
      packages = forAllHostSystems (hostSystem:
        let
          rootfs = mkRootfs hostSystem;
        in {
          inherit rootfs;
          default = rootfs;
        });
    };
}
