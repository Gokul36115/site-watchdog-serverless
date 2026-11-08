import os
import socket
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request
from urllib.parse import urlparse

# ---- Settings (from environment variables, with safe defaults) ----
SITES = [s.strip() for s in os.environ.get("SITES", "https://github.com").split(",") if s.strip()]
SLOW_MS = int(os.environ.get("SLOW_MS", "3000"))
CERT_WARN_DAYS = int(os.environ.get("CERT_WARN_DAYS", "14"))
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID")
TOKEN_PARAM = os.environ.get("TELEGRAM_TOKEN_PARAM")   # SSM parameter name (used in AWS)


def get_token():
    """Locally: from the TELEGRAM_TOKEN env var. In AWS: from SSM Parameter Store (encrypted)."""
    if os.environ.get("TELEGRAM_TOKEN"):
        return os.environ["TELEGRAM_TOKEN"]
    if TOKEN_PARAM:
        import boto3   # the AWS SDK; already included in Lambda's Python runtime
        ssm = boto3.client("ssm")
        return ssm.get_parameter(Name=TOKEN_PARAM, WithDecryption=True)["Parameter"]["Value"]
    return None


def check_http(url):
    """Open the website. Return (status_code, response_ms, error)."""
    try:
        start = time.time()
        req = urllib.request.Request(url, headers={"User-Agent": "site-watchdog/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = resp.status
        return status, round((time.time() - start) * 1000), None
    except urllib.error.HTTPError as e:      # site answered, but with 4xx/5xx
        return e.code, None, None
    except urllib.error.URLError as e:       # no answer: DNS, TLS, connection
        return None, None, type(e.reason).__name__
    except Exception as e:
        return None, None, type(e).__name__


def cert_days_left(host):
    """Connect on port 443 and read how many days until the certificate expires."""
    try:
        context = ssl.create_default_context()
        with socket.create_connection((host, 443), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=host) as tls:
                cert = tls.getpeercert()
        expires = ssl.cert_time_to_seconds(cert["notAfter"])
        return int((expires - time.time()) / 86400)
    except Exception:
        return None


def send_telegram(text):
    """Send a message to my Telegram chat through the bot."""
    token = get_token()
    if not token or not TELEGRAM_CHAT_ID:
        print("Telegram not configured, skipping message")
        return
    data = urllib.parse.urlencode({"chat_id": TELEGRAM_CHAT_ID, "text": text}).encode()
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    with urllib.request.urlopen(url, data=data, timeout=10) as resp:
        resp.read()


def check_site(url):
    """Run all checks for one site. Return a list of problems (empty = healthy)."""
    host = urlparse(url).hostname
    status, ms, error = check_http(url)
    days = cert_days_left(host)

    problems = []
    if error:
        problems.append(f"DOWN ({error})")
    elif status != 200:
        problems.append(f"HTTP {status}")
    elif ms > SLOW_MS:
        problems.append(f"SLOW ({ms} ms)")

    if days is not None and days < CERT_WARN_DAYS:
        problems.append(f"CERT expires in {days} days")

    print(f"{'FAIL' if problems else 'OK  '}  {host:45} status={status}  time={ms} ms  cert={days} days  {problems}")
    return problems


def run_checks():
    """Check every site; send ONE Telegram message listing all problems."""
    alerts = []
    for site in SITES:
        problems = check_site(site)
        if problems:
            alerts.append(f"❌ {urlparse(site).hostname}: {', '.join(problems)}")

    if alerts:
        send_telegram("🚨 Site Watchdog alert\n\n" + "\n".join(alerts))
        print("Alert sent to Telegram")
    else:
        print("All sites healthy, no message sent")
    return alerts


def lambda_handler(event, context):
    """AWS Lambda calls this function on every scheduled run."""
    alerts = run_checks()
    return {"checked": len(SITES), "problems": len(alerts)}


if __name__ == "__main__":
    run_checks()