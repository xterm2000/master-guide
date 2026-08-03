# System-Wide SDKMAN Installation (Rocky Linux 10)
## Shared SDKs for Multiple Users

---

## Overview

This guide sets up SDKMAN in a centralized location (`/opt/sdkman`) so that multiple developers can access the same Java, Gradle, Maven, and other SDKs. A single admin user manages all SDK installations, while all other users have read-only access.

**Benefits:**
- Single source of truth for SDK versions
- No version conflicts between users
- Easy to audit and manage
- Prevents accidental modifications

---

## Prerequisites

- Rocky Linux 10 system
- Root or sudo access
- One designated admin user to manage SDK installations
- bash or zsh shell
- `curl` installed

---

## Installation Steps

### Step 1: Create Shared Directory (as root)

Create the directory where SDKMAN will be installed:

```bash
sudo mkdir -p /opt/sdkman
sudo chmod 755 /opt/sdkman
```

### Step 2: Install SDKMAN (as admin user)

Switch to your admin user (or use `sudo -u adminuser`):

```bash
export SDKMAN_DIR="/opt/sdkman"
curl -s "https://get.sdkman.io" | bash
```

Reload your shell to activate SDKMAN:

```bash
source /opt/sdkman/bin/sdkman-init.sh
```

Verify installation:

```bash
sdk version
```

You should see output like:
```
SDKMAN!
script: 5.19.0
native: 0.5.0
```

### Step 3: Install Required SDKs (as admin user)

List available versions:

```bash
sdk list java
sdk list gradle
sdk list maven
# ... list other tools as needed
```

Install the versions your team needs:

```bash
sdk install java 21.0.1
sdk install gradle 8.5
sdk install maven 3.9.5
# Add any other SDKs your projects require
```

Verify installations:

```bash
java -version
gradle -version
mvn -version
```

### Step 4: Lock Down Permissions (as root)

Set read-only permissions so developers can use SDKs but cannot modify them:

```bash
sudo chown root:root /opt/sdkman
sudo chmod -R 555 /opt/sdkman
```

This prevents accidental (or intentional) modifications by other users.

### Step 5: Configure Each User's Shell (each user)

Each developer adds this to their `~/.bashrc`, `~/.bash_profile`, or `~/.zshrc`:

```bash
# SDKMAN initialization
export SDKMAN_DIR="/opt/sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
```

**Important:** Users must log out and back in for changes to take effect, or run:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

### Step 6: Verify User Access

Each user can now test:

```bash
java -version
gradle -version
mvn -version
```

---

## Managing SDKs Later

When you need to install or update SDKs after the initial lockdown:

### 1. Unlock the directory

```bash
sudo chmod -R 755 /opt/sdkman
```

### 2. Install/update SDKs (as admin user)

```bash
export SDKMAN_DIR="/opt/sdkman"
source /opt/sdkman/bin/sdkman-init.sh

sdk install java 21.0.2
sdk install gradle 8.6
# ... etc
```

### 3. Re-lock the directory

```bash
sudo chmod -R 555 /opt/sdkman
```

---

## Common Tasks

### Check what's installed

```bash
sdk list java
```

Shows installed versions with a `*` next to the current default.

### Set a default version (admin user only)

Unlock, change, re-lock:

```bash
sudo chmod -R 755 /opt/sdkman
export SDKMAN_DIR="/opt/sdkman"
source /opt/sdkman/bin/sdkman-init.sh

sdk default java 21.0.2

sudo chmod -R 555 /opt/sdkman
```

### Offline use (if needed)

Users can temporarily override the SDK path:

```bash
export JAVA_HOME="/opt/sdkman/candidates/java/current"
```

But normally the SDKMAN initialization handles this automatically.

---

## Troubleshooting

### `sdk: command not found`

**Cause:** SDKMAN not sourced in shell config.

**Fix:** Ensure this line is in `~/.bashrc` or `~/.zshrc`:
```bash
source /opt/sdkman/bin/sdkman-init.sh
```

Then log out and back in.

### `Permission denied` when trying to install (non-admin user)

**Expected behavior** — only the admin user can install SDKs. This is intentional.

If you need to add SDKs, ask the admin to unlock, install, and re-lock.

### `java: command not found` after installation

**Cause:** Shell hasn't reloaded after configuration change.

**Fix:**
```bash
source ~/.bashrc
# or
exec $SHELL
```

### Read-only file system errors

**Cause:** Directory is locked with `555` permissions (expected).

**Fix:** Admin user should unlock with `sudo chmod -R 755 /opt/sdkman` before making changes.

---

## Security Notes

- **Read-only installation** prevents accidental corruption or version mismatches
- **Single admin point of control** makes auditing SDK versions easy
- Users can still set local environment overrides if absolutely necessary, but the shared SDKs are the default
- SDKMAN's candidate cache (`~/.sdkman/etc/`) remains per-user; only the actual SDKs are shared

---

## Uninstallation

If you need to remove the system-wide SDKMAN:

```bash
# As root
sudo rm -rf /opt/sdkman

# Each user should remove from their shell config:
# - Remove the SDKMAN initialization lines from ~/.bashrc or ~/.zshrc
```

---

## References

- [SDKMAN Official Installation Docs](https://sdkman.io/install/)
- [SDKMAN Usage Guide](https://sdkman.io/usage/)

