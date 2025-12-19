1. Create a file called setup-speedtest-compose.sh, paste the following content into it, make it executable and run it:
```
chmod +x setup-speedtest-compose.sh
# Optionally set your domain now if you have one:
# DOMAIN=your.domain.com ./setup-speedtest-compose.sh
./setup-speedtest-compose.sh

```
2) Notes & important details

**Domain & DNS:** For automatic HTTPS you must set DOMAIN to a publicly routable hostname that points (A record) to the server IP before running the script (or set and re-run later). Example:
DOMAIN=speed.example.com ./setup-speedtest-compose.sh
Caddy will request Let's Encrypt certs automatically and serve https://speed.example.com/simple-speedtest.html.
**If DOMAIN** is not set: The script still brings up Caddy and speedtest. You can open the page via http://server-ip/simple-speedtest.html. Caddy will serve HTTP for convenience.
**Ports:** The script maps ports 80 and 443 to the host for Caddy. Make sure these are reachable from the internet for Let's Encrypt (incoming 80/443).
**testfile size:** Default 200 MB (TESTFILE_SIZE_MB=200). You can change this before running:
TESTFILE_SIZE_MB=400 ./setup-speedtest-compose.sh
**Storage:** The caddy_data and caddy_config volumes persist certificates & config between runs.
**Reverse proxy:** Caddy proxies requests to the speedtest service (internal Docker network), so the Node server only listens on container port 8000.
**Stopping:** From the created folder run docker compose down (or docker-compose down) to remove containers.
**Rebuild after changes:** If you edit the HTML or server, run docker compose build --no-cache then docker compose up -d.
