{ modulesPath, pkgs, lib, config, ... }@args:
let
  inherit (import ../../lib {
    nixpkgs-lib = args.lib;
  }) defaultFsType withDriveLetters;
in
{
  assertions = [
    {assertion = (config.microvm.writableStoreOverlay != null) -> (!config.nix.optimise.automatic && !config.nix.settings.auto-optimise-store);
     message = ''
       `nix.optimise.automatic` and `nix.settings.auto-optimise-store` do not work with `microvm.writableStoreOverlay`.
     '';}];

  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];

  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackages_latest.extend (_: _: {
    kernel = pkgs.microvm-kernel;
  });

  fileSystems = (
    # Volumes
    builtins.foldl' (result: { mountPoint, letter, fsType ? defaultFsType, ... }: result // {
      "${mountPoint}" = {
        inherit fsType;
        device = "/dev/vd${letter}";
        neededForBoot = mountPoint == config.microvm.writableStoreOverlay;
      };
    }) {} (withDriveLetters 1 config.microvm.volumes)
  ) // (
    # Shares
    builtins.foldl' (result: { mountPoint, tag, proto, source, ... }: result // {
      "${mountPoint}" = {
        device = tag;
        fsType = proto;
        options = {
          "virtiofs" = [ "defaults" ];
          "9p" = [ "trans=virtio" "version=9p2000.L"  "msize=65536" ];
        }.${proto};
        neededForBoot = (
          source == "/nix/store" ||
          mountPoint == config.microvm.writableStoreOverlay
        );
      };
    }) {} config.microvm.shares
  ) // (
    if config.microvm.storeOnBootDisk
    then {
      "/nix/store" = {
        device = "//nix/store";
        options = [ "bind" ];
        neededForBoot = true;
      };
    } else
      let
        hostStore = builtins.head (
          builtins.filter ({ source, ... }:
            source == "/nix/store"
          ) config.microvm.shares
        );
      in if config.microvm.writableStoreOverlay == null &&
            hostStore.mountPoint != "/nix/store"
         then {
           "/nix/store" = {
             device = hostStore.mountPoint;
             options = [ "bind" ];
             neededForBoot = true;
           };
         }
         else {}
  );

  # nix-daemon works only with a writable /nix/store
  systemd =
    let
      enableNixDaemon = config.microvm.writableStoreOverlay != null;
    in {
      services.nix-daemon.enable = lib.mkDefault enableNixDaemon;
      sockets.nix-daemon.enable = lib.mkDefault enableNixDaemon;

      # just fails in the usual usage of microvm.nix
      generators = { systemd-gpt-auto-generator = "/dev/null"; };
    };

}
