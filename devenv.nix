{ pkgs, config, lib, ... }:
let
  pnpm = pkgs.writeShellScriptBin "pnpm" ''
    exec ${pkgs.corepack}/bin/corepack pnpm "$@"
  '';
  fixtureTools = pkgs.buildEnv {
    name = "waybar-fixture-tools";
    paths = config.packages;
    pathsToLink = [ "/bin" ];
  };
  developmentRoot = pkgs.runCommand "waybar-development-root" { } ''
    mkdir -p "$out/env" "$out/usr/bin"
    # Merge individual links with the base image's existing /usr/bin/env.
    for tool in ${fixtureTools}/bin/*; do
      ln -s "$tool" "$out/usr/bin/$(basename "$tool")"
    done
  '';
in
{
  name = "waybar-config";
  cachix.enable = false;
  process.manager.implementation = "overmind";
  packages = with pkgs; [
    bashInteractive coreutils findutils gawk git gnugrep gnumake gnused diffutils
    perl python3 nodejs_24 pnpm jq dash curl cacert gnutar gzip unzip
    ruff shellcheck shfmt gitleaks actionlint zizmor
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.procps pkgs.util-linux ];
  env = {
    # Match the committed auto-calendar baseline while preserving UTF-8.
    LANG = "en_US.UTF-8";
    LC_ALL = config.env.LANG;
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
  } // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
  };
  scripts.repo-check.exec = "bash scripts/check-development.sh";
  enterTest = "repo-check";
  containers.shell = {
    name = "localhost/waybar-config-dev";
    version = "latest";
    copyToRoot = [ ];
    # Existing fixture tests deliberately use minimal /usr/bin PATHs.
    layers = lib.mkAfter [{
      copyToRoot = [ developmentRoot ];
      perms = [{ path = developmentRoot; regex = "/env"; mode = "1777"; }];
    }];
    entrypoint = [ (pkgs.writeShellScript "development-entrypoint" ''
      export PATH="${lib.makeBinPath config.packages}:$PATH"
      exec "$@"
    '') ];
    startupCommand = "bash";
  };
}
