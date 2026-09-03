# Chromebook

## SQLite  
SQLite ships *inside* Python's standard library.

**The Python module**
```bash
python3 -c "import sqlite3; print('py sqlite3 lib:', sqlite3.sqlite_version)"
```
Expect something like `py sqlite3 lib: 3.45.1`. If that prints a version, ZOE's schema will run — nothing to install.

**The optional CLI (`sqlite3` command, handy for inspecting the .db file by hand):**
```bash
sqlite3 --version
```
If that returns "command not found" and you want it, install just the CLI:
```bash
sudo apt update && sudo apt install -y sqlite3
```
This is a §27 dependency decision: the CLI is optional convenience for you, not a runtime requirement for ZOE. The module is what matters.

## Node — check first, install only if missing

```bash
node --version && npm --version
```
Debian's default channel is usually old, and n8n wants a current LTS. If Node is missing or old, don't `apt install nodejs` (§27 — you'd get a stale version and a maintenance headache). Use nvm so Node lives in your Linux home dir, no root, easy to change later:Important safety note from those results: there's a recent nvm security advisory (CVE-2026-10796) fixed in the latest release, so you want a current tagged version, not an old pinned one and not `master` (which the maintainers say is often broken). Rather than have me guess the exact tag, pull it from nvm's own release API so you always get the patched latest:

## Node install via nvm

**1. Prerequisites** (curl is needed to fetch the installer):
```bash
sudo apt update && sudo apt install -y curl
```

**2. Fetch the latest nvm tag and run its installer** — this avoids hard-coding a version that could be stale or vulnerable:
```bash
NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo "Installing nvm $NVM_VERSION"
curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
```

A word on `curl … | bash`: you're piping a script straight into a shell. It's the documented install path and it's fetching a signed tagged release over HTTPS from the official repo, so it's the normal risk everyone accepts here — but if you'd rather inspect first (reasonable, and in the spirit of §35's "understand before you run"), download it, read it, then run it:
```bash
curl -o /tmp/nvm-install.sh "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
less /tmp/nvm-install.sh   # inspect
bash /tmp/nvm-install.sh
```

**3. Load nvm into the current shell** (or just close and reopen the terminal):
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

**4. Install the current LTS and make it default:**
```bash
nvm install --lts
nvm alias default 'lts/*'
```

## Verify everything

Run this block — it confirms all three pieces in one shot:
```bash
echo "Python : $(python3 --version)"
echo "SQLite : $(python3 -c 'import sqlite3; print(sqlite3.sqlite_version)')"
echo "Node   : $(node --version)"
echo "npm    : $(npm --version)"
```

Expected shape:
```
Python : Python 3.13.5
SQLite : 3.4x.x
Node   : v22.x.x   (or whatever the current LTS is)
npm    : 10.x.x
```

If all four print versions, ZOE's schema layer (SQLite via Python) and the n8n orchestration layer (Node) both have their runtimes satisfied.

One thing I'd flag per §5 and §28 before you go further: n8n itself is a meaningful resource commitment on a Chromebook. Your sandbox check earlier showed ~3.9 GiB RAM. n8n via `npm` (not Docker — lighter, avoids the container overhead §28 warns about) is the sensible route there, but let's confirm the real Chromebook's free memory before installing it.

Want to run `free -h` and `df -h ~` on the actual machine and paste the output? That tells us whether n8n runs comfortably or whether we need to think about a lighter scheduler.