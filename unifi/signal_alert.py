#!/usr/bin/env python3
"""Monitor UniFi client signal strength and send notifications via Apprise."""

import argparse
import logging
import sys
import time
from pathlib import Path

import apprise
import httpx
import yaml

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# UniFi controller interaction
# ---------------------------------------------------------------------------


class UnifiClient:
    """Minimal client for the UniFi controller API."""

    def __init__(self, host: str, port: int, username: str, password: str,
                 site: str = "default", verify_ssl: bool = False):
        self.base_url = f"{host.rstrip('/')}:{port}"
        self.site = site
        self.username = username
        self.password = password
        self.verify_ssl = verify_ssl
        self.session = httpx.Client(verify=verify_ssl)

    # ---- auth -------------------------------------------------------------

    def login(self) -> None:
        """Authenticate against the controller and store the session cookie."""
        # UDM / Cloud Key Gen2+ use /api/auth/login; legacy uses /api/login.
        for path in ("/api/auth/login", "/api/login"):
            resp = self.session.post(
                f"{self.base_url}{path}",
                json={"username": self.username, "password": self.password},
            )
            if resp.status_code == 200:
                log.info("Logged in to UniFi controller at %s", self.base_url)
                # Grab CSRF token if present (UDM-based controllers).
                csrf = resp.headers.get("X-CSRF-Token")
                if csrf:
                    self.session.headers["X-CSRF-Token"] = csrf
                return
        raise RuntimeError(
            f"Failed to log in to UniFi controller ({resp.status_code}): "
            f"{resp.text}"
        )

    def logout(self) -> None:
        self.session.post(f"{self.base_url}/api/logout")

    # ---- data -------------------------------------------------------------

    def _api_prefix(self) -> str:
        """Return the correct API prefix depending on controller type."""
        # UDM-based controllers proxy network API under /proxy/network.
        test = self.session.get(
            f"{self.base_url}/proxy/network/api/s/{self.site}/self",
        )
        if test.status_code == 200:
            return "/proxy/network"
        return ""

    def get_active_clients(self) -> list[dict]:
        """Return list of active wireless clients with signal information."""
        prefix = self._api_prefix()
        url = f"{self.base_url}{prefix}/api/s/{self.site}/stat/sta"
        resp = self.session.get(url)
        resp.raise_for_status()
        return resp.json().get("data", [])

    def get_devices(self) -> dict[str, str]:
        """Return a map of AP MAC -> AP name for friendly display."""
        prefix = self._api_prefix()
        url = f"{self.base_url}{prefix}/api/s/{self.site}/stat/device"
        resp = self.session.get(url)
        resp.raise_for_status()
        devices = resp.json().get("data", [])
        return {d["mac"]: d.get("name", d["mac"]) for d in devices}


# ---------------------------------------------------------------------------
# Monitoring loop
# ---------------------------------------------------------------------------


def load_config(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def build_apprise(global_urls: list[str],
                  device_urls: list[str] | None = None) -> apprise.Apprise:
    """Create an Apprise instance with global + per-device URLs."""
    ap = apprise.Apprise()
    for url in global_urls:
        ap.add(url)
    for url in (device_urls or []):
        ap.add(url)
    return ap


def monitor(config: dict) -> None:  # noqa: C901
    """Main polling loop."""
    uc = config["unifi"]
    client = UnifiClient(
        host=uc["host"],
        port=uc.get("port", 443),
        username=uc["username"],
        password=uc["password"],
        site=uc.get("site", "default"),
        verify_ssl=uc.get("verify_ssl", False),
    )
    client.login()

    # Build a lookup: mac (lowercase) -> device config
    watched = {
        d["mac"].lower(): d
        for d in config["devices"]
    }

    poll_interval = config.get("poll_interval", 30)
    cooldown = config.get("notifications", {}).get("cooldown", 300)
    notif_title = config.get("notifications", {}).get(
        "title", "UniFi Signal Alert"
    )
    global_urls = config.get("apprise_urls", [])

    # Track last alert time per (device_mac, ap_mac) to enforce cooldown.
    last_alert: dict[tuple[str, str], float] = {}

    # Cache AP names so we don't hit the API every cycle.
    ap_names: dict[str, str] = {}

    log.info(
        "Monitoring %d device(s), polling every %ds",
        len(watched),
        poll_interval,
    )

    while True:
        try:
            clients = client.get_active_clients()
            if not ap_names:
                ap_names = client.get_devices()
        except httpx.HTTPError:
            log.exception("Error fetching data from controller, retrying")
            try:
                client.login()
            except Exception:
                log.exception("Re-login failed")
            time.sleep(poll_interval)
            continue

        for cl in clients:
            mac = cl.get("mac", "").lower()
            if mac not in watched:
                continue

            dev_cfg = watched[mac]
            # rssi is the raw value reported by the AP (negative dBm).
            signal = cl.get("rssi") or cl.get("signal")
            if signal is None:
                continue

            ap_mac = cl.get("ap_mac", "unknown")
            ap_name = ap_names.get(ap_mac, ap_mac)

            # Filter by specific APs if configured.
            allowed_aps = dev_cfg.get("access_points") or []
            if allowed_aps and ap_name not in allowed_aps and ap_mac not in allowed_aps:
                continue

            threshold = dev_cfg["signal_threshold"]
            if signal >= threshold:
                key = (mac, ap_mac)
                now = time.time()
                if now - last_alert.get(key, 0) < cooldown:
                    continue

                body = (
                    f"{dev_cfg['name']} detected on AP \"{ap_name}\" "
                    f"with signal {signal} dBm "
                    f"(threshold: {threshold} dBm)."
                )
                log.info("ALERT: %s", body)

                ap = build_apprise(
                    global_urls, dev_cfg.get("apprise_urls")
                )
                ap.notify(title=notif_title, body=body)
                last_alert[key] = now

        time.sleep(poll_interval)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Monitor UniFi client signal strength and send alerts.",
    )
    parser.add_argument(
        "-c", "--config",
        default=str(Path(__file__).with_name("config.yaml")),
        help="Path to YAML config file (default: config.yaml next to script)",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    cfg_path = Path(args.config)
    if not cfg_path.exists():
        log.error("Config file not found: %s", cfg_path)
        sys.exit(1)

    config = load_config(str(cfg_path))

    try:
        monitor(config)
    except KeyboardInterrupt:
        log.info("Shutting down")


if __name__ == "__main__":
    main()
