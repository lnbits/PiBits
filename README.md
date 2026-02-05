# LNbits + Spark Sidecar (Pi 4)

This repo contains a NixOS configuration for Raspberry Pi 4 that:
- installs LNbits from the `sparkwallet` branch
- installs the Spark sidecar
- prompts on first boot for WiFi + SPARK_MNEMONIC

## Build

Use a machine with Nix and build an SD image for the Pi:

```
nix build .#nixosConfigurations.lnbits-pi.config.system.build.sdImage
```

Flash the resulting image to an SD card.

## First Boot

On first boot, the console will prompt for:
- WiFi SSID
- WiFi password
- `SPARK_MNEMONIC`

The SSH password for user `lnbits` is set to the first 3 words of the mnemonic.
This password includes spaces (e.g. `word1 word2 word3`).

## Services and Ports

- LNbits: `0.0.0.0:5000`
- Spark sidecar: `0.0.0.0:8765`
- SSH: `22`

Environment files:
- `/etc/lnbits.env`
- `/etc/spark.env`

## Notes

- Secrets are not stored in the Nix store.
- The first-boot setup runs once and writes the env files.
- To re-run the setup, delete `/var/lib/lnbits/.firstboot-complete` and reboot.
