# Problems I hit and how I fixed them

Real issues from building this project: symptom, root cause, fix, and what I took away.

---

## 1. Telegram API returned `404 Not Found`
- **Symptom:** `curl https://api.telegram.org/<token>/getUpdates` → `{"ok":false,"error_code":404,"description":"Not Found"}`
- **Root cause:** The Bot API URL format is `https://api.telegram.org/bot<TOKEN>/<method>`. The word `bot` must sit directly in front of the token, and it was missing.
- **Fix:** Used `.../bot<TOKEN>/getUpdates` → `{"ok":true,...}`, then read the chat ID from `"chat":{"id":...}`.
- **Lesson:** A 404 from an API usually means a wrong path, not a wrong credential (that would be 401).

## 2. Keeping the bot token out of shell history and code
- **Risk:** Commands containing the token were saved in `~/.bash_history`.
- **Fix:**
  - Commands with secrets are prefixed with a space; Ubuntu's `HISTCONTROL=ignoreboth` skips them.
  - Old entries were removed with `history -d <n>`.
  - In AWS the token lives only in SSM Parameter Store (`SecureString`); locally it's an environment variable, never in a file.
- **Rotation procedure:** `/revoke` in @BotFather → `aws ssm put-parameter ... --overwrite` with the new token. No code or Terraform change needed.
- **Lesson:** A secret's place is a secret store; the code only knows the secret's name.

## 3. `python: command not found`
- **Symptom:** `python check.py` failed; `python3 check.py` worked.
- **Root cause:** The virtual environment wasn't activated. Ubuntu only ships `python3`; the venv provides `python` and `pip`.
- **Fix:** `source .venv/bin/activate` (the prompt shows `(.venv)`).

## 4. `git mv`: "not under version control"
- **Symptom:** `git mv check.py watchdog.py` → `fatal: not under version control`
- **Root cause:** The file had never been committed, so git wasn't tracking it.
- **Fix:** A plain `mv`, then the first commit. Also found that `.gitignore` didn't exist yet, so `.venv/` showed as untracked. Created `.gitignore` before any `git add`.
- **Lesson:** Create `.gitignore` before the first commit, and verify it with `git check-ignore -v <path>`.

## 5. Lambda's Python has no `requests`
- **Problem:** The local version used `requests`, which isn't part of the Lambda runtime. Using it would mean building a deployment package with dependencies.
- **Fix:** Rewrote the HTTP calls with the standard library (`urllib.request`). The whole function is now one file that Terraform zips with `archive_file`.
- **Bonus:** Error reasons got more precise: `SSLCertVerificationError` (expired certificate) and `gaierror` (DNS failure) instead of generic names.

## 6. Okta free plan rejected a personal email
- **Symptom:** The Okta Integrator Free Plan signup said "Business email is required" for a Gmail address. (The old Okta Developer Edition has been retired.)
- **Decision:** Used **Auth0**, Okta's customer-identity product, which accepts personal accounts. The standards are identical (OIDC, Authorization Code + PKCE, RS256 JWTs, JWKS), so the AWS side (API Gateway JWT authorizer) is the same either way.
- **Lesson:** Design against standards (OIDC/JWT), not one vendor; the identity provider becomes a swappable part.

## 7. Old test users and open login methods in the Auth0 tenant
- **Found:** The tenant was reused from an earlier sample project:
  - old test users (`abc@...`, `agent47@...`, `bro@...`) in the shared database connection
  - an extra `test1` database
  - Google, GitHub, Facebook and Microsoft logins all enabled for the new app
- **Risk:** Connections are shared across apps, so those old users, or anyone with a social account, could have logged in to the new dashboard.
- **Fix:**
  - deleted the old users
  - enabled only Username-Password-Authentication for the app
  - turned on **Disable Sign Ups**
  - created the single dashboard user by hand
- **Lesson:** Review an identity provider's existing users and connections before trusting it; least privilege applies to *who can log in*, not only to permissions.

## 8. GitHub Pages showed 404 right after enabling it
- **Symptom:** `https://gokul36115.github.io/site-watchdog-serverless/` → "There isn't a GitHub Pages site here."
- **Root cause:** Pages builds and deploys asynchronously (the "pages build and deployment" workflow), and the browser had cached the 404.
- **Fix:** Waited for the deployment to finish (Actions tab), then hard-refreshed (Ctrl+Shift+R).

## 9. Auto-created test app could get API tokens without a user login
- **Found while reviewing Auth0 logs:** a "Success Exchange: Client Credentials" event for **"Site Watchdog API (Test Application)"**, a machine-to-machine app Auth0 creates automatically when the API's *Test* tab is opened.
- **Risk:** A client-credentials token has the right issuer and audience, so API Gateway would accept it. That's a path around the SSO login.
- **Fix:** Deleted the test application and set the API's client (machine-to-machine) access to **No apps allowed**. Only user-delegated tokens from the dashboard app remain possible.
- **Lesson:** Read the identity provider's logs, not just your own. A JWT authorizer checks *who issued* the token and *for which API*, so control **which clients** can obtain tokens in the first place.