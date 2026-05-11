{ lib, pkgs, modules ? [ ] }:

let
  evaluated = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ../modules/base.nix
      ../modules/storage-files.nix
      ../modules/package-env.nix
      ../modules/guest-ssh.nix
      ../modules/bridges.nix
    ] ++ modules;
  };
  cfg = evaluated.config.rocknix;
  fileLines =
    lib.mapAttrsToList (name: spec:
      "file|bin|${name}|${toString spec.source}|${spec.mode}") cfg.files.bin
    ++ lib.mapAttrsToList (name: spec:
      "file|profile.d|${name}|${toString spec.source}|${spec.mode}") cfg.files.profile;
  packageLines = lib.mapAttrsToList (name: spec:
    "file|bin|${name}|${toString spec.wrapper}|0755") cfg.packageEnvs;
  bridgeLines = lib.mapAttrsToList (name: spec:
    "bridge|${name}|${lib.concatStringsSep " " spec.command}") cfg.bridges;
  sshLines = lib.optional cfg.guest.ssh.enable
    "guest-ssh|${toString cfg.guest.ssh.port}|${cfg.guest.ssh.authorizedKeys}";
  activationLines = fileLines ++ packageLines ++ bridgeLines ++ sshLines;
in {
  inherit evaluated;
  config = cfg;
  activationLines = activationLines;
  activationManifest = lib.concatStringsSep "\n" activationLines + lib.optionalString (activationLines != [ ]) "\n";
}
