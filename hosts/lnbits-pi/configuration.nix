{ config, pkgs, lib, ... }:
let
  lnbitsUser = "lnbits";
  lnbitsDataDir = "/var/lib/lnbits";
  sparkDataDir = "/var/lib/spark-sidecar";
  lnbitsEnvFile = "/etc/lnbits.env";
  sparkEnvFile = "/etc/spark.env";
  firstBootMarker = "${lnbitsDataDir}/.firstboot-complete";

  firstBootScript = pkgs.writeShellScript "lnbits-first-boot" ''
    set -euo pipefail

    if [ -f "${firstBootMarker}" ]; then
      exit 0
    fi

    mkdir -p ${lnbitsDataDir} ${sparkDataDir}

    ask() {
      ${pkgs.systemd}/bin/systemd-ask-password "$1"
    }

    SSID="$(ask 'WiFi SSID')"
    WIFI_PASS="$(ask 'WiFi Password')"
    MNEMONIC="$(ask 'SPARK_MNEMONIC (12 or 24 words)')"

    # Configure WiFi via NetworkManager.
    ${pkgs.networkmanager}/bin/nmcli dev wifi connect "$SSID" password "$WIFI_PASS" ifname wlan0 || true

    # Write env files (root-readable only).
    umask 077
    cat > ${sparkEnvFile} <<EOF
SPARK_MNEMONIC=$MNEMONIC
SPARK_NETWORK=MAINNET
SPARK_SIDECAR_PORT=8765
SPARK_PAY_WAIT_MS=20000
EOF

    cat > ${lnbitsEnvFile} <<EOF
LNBITS_DATA_FOLDER=${lnbitsDataDir}/data
LNBITS_DATABASE_URL=sqlite:///${lnbitsDataDir}/data/lnbits.sqlite
LNBITS_HOST=0.0.0.0
LNBITS_PORT=5000
EOF

    mkdir -p ${lnbitsDataDir}/data
    chown -R ${lnbitsUser}:${lnbitsUser} ${lnbitsDataDir} ${sparkDataDir}

    # Set SSH password to first 3 mnemonic words (space-separated).
    PASS="$(printf '%s' "$MNEMONIC" | awk '{print $1" "$2" "$3}')"
    echo "${lnbitsUser}:$PASS" | ${pkgs.shadow}/bin/chpasswd

    touch ${firstBootMarker}
  '';

  lnbitsSetupScript = pkgs.writeShellScript "lnbits-setup" ''
    set -euo pipefail
    mkdir -p ${lnbitsDataDir}
    chown -R ${lnbitsUser}:${lnbitsUser} ${lnbitsDataDir}

    if [ ! -d ${lnbitsDataDir}/src/.git ]; then
      ${pkgs.git}/bin/git clone --branch sparkwallet https://github.com/lnbits/lnbits.git ${lnbitsDataDir}/src
    else
      ${pkgs.git}/bin/git -C ${lnbitsDataDir}/src fetch --all
      ${pkgs.git}/bin/git -C ${lnbitsDataDir}/src checkout sparkwallet
      ${pkgs.git}/bin/git -C ${lnbitsDataDir}/src pull
    fi

    if [ ! -d ${lnbitsDataDir}/venv ]; then
      ${pkgs.python3}/bin/python -m venv ${lnbitsDataDir}/venv
    fi

    ${lnbitsDataDir}/venv/bin/pip install --upgrade pip
    ${lnbitsDataDir}/venv/bin/pip install -e ${lnbitsDataDir}/src
  '';

  sparkSetupScript = pkgs.writeShellScript "spark-sidecar-setup" ''
    set -euo pipefail
    mkdir -p ${sparkDataDir}
    chown -R ${lnbitsUser}:${lnbitsUser} ${sparkDataDir}

    if [ ! -d ${sparkDataDir}/src/.git ]; then
      ${pkgs.git}/bin/git clone https://github.com/lnbits/spark_sidecar.git ${sparkDataDir}/src
    else
      ${pkgs.git}/bin/git -C ${sparkDataDir}/src pull
    fi

    ${pkgs.nodejs_20}/bin/npm --prefix ${sparkDataDir}/src install --omit=dev
  '';
in
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.hostName = "lnbits-pi";
  time.timeZone = "Europe/London";

  networking.networkmanager.enable = true;
  networking.wireless.enable = false;

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.KbdInteractiveAuthentication = true;

  users.mutableUsers = true;
  users.users.${lnbitsUser} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  # First-boot prompt for WiFi + mnemonic.
  systemd.services.first-boot-setup = {
    description = "First boot setup for WiFi + Spark mnemonic";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" "systemd-user-sessions.service" "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    before = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = firstBootScript;
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
    };
  };

  systemd.services.lnbits-setup = {
    description = "Fetch and install LNbits";
    wantedBy = [ "multi-user.target" ];
    after = [ "first-boot-setup.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "first-boot-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = lnbitsUser;
      Group = lnbitsUser;
      ExecStart = lnbitsSetupScript;
    };
  };

  systemd.services.spark-sidecar-setup = {
    description = "Fetch and install Spark sidecar";
    wantedBy = [ "multi-user.target" ];
    after = [ "first-boot-setup.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    requires = [ "first-boot-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = lnbitsUser;
      Group = lnbitsUser;
      ExecStart = sparkSetupScript;
    };
  };

  systemd.services.lnbits = {
    description = "LNbits";
    wantedBy = [ "multi-user.target" ];
    after = [ "lnbits-setup.service" "network-online.target" ];
    requires = [ "lnbits-setup.service" ];
    serviceConfig = {
      User = lnbitsUser;
      Group = lnbitsUser;
      WorkingDirectory = "${lnbitsDataDir}/src";
      EnvironmentFile = lnbitsEnvFile;
      ExecStart = "${lnbitsDataDir}/venv/bin/uvicorn lnbits.app:app --host 0.0.0.0 --port 5000";
      Restart = "on-failure";
    };
  };

  systemd.services.spark-sidecar = {
    description = "Spark sidecar";
    wantedBy = [ "multi-user.target" ];
    after = [ "spark-sidecar-setup.service" "network-online.target" ];
    requires = [ "spark-sidecar-setup.service" ];
    serviceConfig = {
      User = lnbitsUser;
      Group = lnbitsUser;
      WorkingDirectory = "${sparkDataDir}/src";
      EnvironmentFile = sparkEnvFile;
      ExecStart = "${pkgs.nodejs_20}/bin/node ${sparkDataDir}/src/server.mjs";
      Restart = "on-failure";
    };
  };

  services.caddy = {
    enable = true;
    configFile = "/etc/caddy/Caddyfile";
  };

  environment.etc."caddy/Caddyfile".text = ''
    127.0.0.1:8080 {
      reverse_proxy 127.0.0.1:5000
    }
  '';

  systemd.tmpfiles.rules = [
    "L+ /root/Caddyfile - - - - /etc/caddy/Caddyfile"
  ];

  networking.firewall.allowedTCPPorts = [ 22 5000 8765 ];

  environment.systemPackages = with pkgs; [
    git
    nodejs_20
    python3
    python3Packages.pip
    python3Packages.virtualenv
    networkmanager
    gcc
    pkg-config
    openssl
    libffi
  ];

  system.stateVersion = "24.11";
}
