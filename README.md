# mrtg-container

A Docker image for running [MRTG](https://oss.oetiker.ch/mrtg/) (Multi Router Traffic Grapher) to collect interface traffic statistics over SNMP.

Every 5 minutes, a host cron job starts a short-lived container. The container polls your devices and writes HTML pages and PNG graphs to `/opt/mrtg/data` on the host. Those files can be served directly or published through [mrtg-api](https://github.com/SingAREN/mrtg-api).

## Contents

- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Setup](#setup)
  - [1. Build the container](#1-build-the-container)
  - [2. Add your MRTG configuration](#2-add-your-mrtg-configuration)
  - [3. Set up the cron job](#3-set-up-the-cron-job)
- [How it works](#how-it-works)
- [Using with mrtg-api](#using-with-mrtg-api)
- [Troubleshooting](#troubleshooting)

## Repository layout

```
.
├── .gitignore                 # ignores config/mrtg.cfg and mrtg_lib/
├── Dockerfile                 # Ubuntu 24.04 image with MRTG
├── mrtg_cron                  # cron entry that runs MRTG every 5 minutes
├── config/
│   └── mrtg.cfg.example       # example configuration; copy to mrtg.cfg and edit
└── data/                      # MRTG output (HTML, PNG, logs)
    └── .gitignore             # keeps the folder in git but ignores everything written to it
```

Site-specific files are ignored by git, so they are never committed:

- `config/mrtg.cfg`, your real configuration, which contains SNMP community strings
- everything MRTG writes to `data/`; only the empty folder is kept in the repository
- `mrtg_lib/`, MRTG's config cache

## Requirements

- A Linux host with Docker and cron
- SNMP (v2c) read access from the host to the devices you want to monitor

## Setup

The commands below assume the repository lives at `/opt/mrtg`. That is where `mrtg_cron` and mrtg-api expect it.

```bash
sudo git clone https://github.com/SingAREN/mrtg-container.git /opt/mrtg
```

### 1. Build the container

```bash
cd /opt/mrtg && sudo docker build -t mrtg:latest .
```

The image must be tagged `mrtg:latest`, because that is the name `mrtg_cron` runs. Rebuild whenever you change the `Dockerfile`, or to pick up Ubuntu security updates.

### 2. Add your MRTG configuration

Replace the example configuration with your own:

```bash
sudo cp /opt/mrtg/config/mrtg.cfg.example /opt/mrtg/config/mrtg.cfg
```

Edit `/opt/mrtg/config/mrtg.cfg`. Keep the global settings at the top, especially `WorkDir: /opt/mrtg/data`. Replace the example `DEVICE1` targets with your own devices and interfaces:

```
Target[CORE1-ETH1]: \Ethernet1/1:YOUR_COMMUNITY@10.0.0.1:::::2
Title[CORE1-ETH1]: CORE1: Traffic Analysis for CORE1 Ethernet1/1
PageTop[CORE1-ETH1]: <h1>CORE1: Traffic Analysis for CORE1 Ethernet1/1</h1>
```

| Part | Meaning |
|---|---|
| `CORE1-ETH1` | Target name. Output files use it in lower case, e.g. `core1-eth1.html` and `core1-eth1-day.png`. |
| `\Ethernet1/1` | Selects the interface by its description, so the target survives renumbering of interface indexes. |
| `YOUR_COMMUNITY@10.0.0.1` | SNMP read community and the device address |
| `:::::2` | SNMP v2c, which provides the 64-bit counters needed for fast links |

You can also generate targets from a device with `cfgmaker`, then copy the ones you want into `mrtg.cfg`:

```bash
sudo docker run --rm mrtg:latest cfgmaker --snmp-options=:::::2 --ifref=descr YOUR_COMMUNITY@10.0.0.1
```

> `mrtg.cfg` contains SNMP community strings. It is listed in `.gitignore`, so `git add` skips it. Only `git add -f` would commit it.

### 3. Set up the cron job

**Create the directories the container writes to.** The container runs as `mrtg-user` (UID 222), so that user needs write access:

```bash
sudo mkdir -p /opt/mrtg/data /opt/mrtg/mrtg_lib
```

```bash
sudo chown 222 /opt/mrtg/data /opt/mrtg/mrtg_lib
```

**Test one run by hand.** This is the same command that `mrtg_cron` runs, without `-d`, so you can see the output:

```bash
sudo docker run --rm -e TZ=Asia/Singapore -v /opt/mrtg/config:/opt/mrtg/config:ro -v /opt/mrtg/data:/opt/mrtg/data -v /opt/mrtg/mrtg_lib:/var/lib/mrtg mrtg:latest /usr/bin/mrtg /opt/mrtg/config/mrtg.cfg --lock-file /var/lock/mrtg/mrtg_l --confcache-file /var/lib/mrtg/mrtg.ok
```

The first two or three runs print `Rateup WARNING` messages because MRTG has no history yet. Afterwards, `/opt/mrtg/data` should contain a `.html`, `.log` and `-day/-week/-month/-year.png` files for each target.

**Install the cron job:**

```bash
sudo install -o root -g root -m 644 /opt/mrtg/mrtg_cron /etc/cron.d/mrtg
```

`mrtg_cron` runs MRTG every 5 minutes, as root, with these settings:

| Option | Purpose |
|---|---|
| `-d --rm` | Run in the background and remove the container when it finishes |
| `-e TZ=Asia/Singapore` | Time zone for graph timestamps. **Change this** if your site uses a different zone. |
| `-v /opt/mrtg/config:...:ro` | Your configuration, mounted read-only |
| `-v /opt/mrtg/data:...` | Output directory |
| `-v /opt/mrtg/mrtg_lib:/var/lib/mrtg` | Keeps MRTG's config cache (`mrtg.ok`) between runs |

If you deploy somewhere other than `/opt/mrtg`, or use a different image tag, edit `/etc/cron.d/mrtg` to match. cron picks up changes in `/etc/cron.d` automatically.

## How it works

```
/etc/cron.d/mrtg  (every 5 min)
   └─► docker run --rm mrtg:latest mrtg /opt/mrtg/config/mrtg.cfg
          ├─ reads   /opt/mrtg/config/mrtg.cfg   (read-only)
          ├─ polls   devices over SNMP v2c
          └─ writes  /opt/mrtg/data/<target>.{html,log,png}
```

The image has no long-running process. Each run is a fresh container that exits once polling is done, so all state lives in the mounted host directories.

## Using with mrtg-api

[mrtg-api](https://github.com/SingAREN/mrtg-api) reads this container's output from the same paths:

- `MRTG_CONFIG = /opt/mrtg/config/mrtg.cfg`
- `MRTG_BASE_DIR = /opt/mrtg/data/`

Its `docker-compose.yml` mounts `/opt/mrtg` read-only, so no extra configuration is needed. Make sure the mrtg-api user (UID 225) can read `/opt/mrtg/config/mrtg.cfg` and `/opt/mrtg/data`.

mrtg-api expects MRTG's default page layout: day, week, month and year graphs, each with an in/out table. Avoid `Suppress[]` and custom page templates on targets you want to publish through it.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Nothing in `/opt/mrtg/data` | Run the test command from step 3 by hand and check its output. Check that `/etc/cron.d/mrtg` exists, is owned by root and is not group- or world-writable. |
| `Unable to find image 'mrtg:latest'` | The image was built under a different tag. Rebuild with `docker build -t mrtg:latest .`. |
| `Permission denied` under `/opt/mrtg/data` or `/var/lib/mrtg` | Run `sudo chown 222 /opt/mrtg/data /opt/mrtg/mrtg_lib`. |
| `SNMP Error: no response received` | Check that the host can reach the device on UDP 161, and check the community string and the device's SNMP ACLs. |
| Graph times are off by some hours | Set `TZ` in `/etc/cron.d/mrtg` to your local time zone. |
| Graphs flat at the top on fast links | Use SNMP v2c (`:::::2`) for 64-bit counters, and check that `MaxBytes` is high enough. |
