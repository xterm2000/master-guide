# Gitea Local Setup & Git Tracking

## Table of Contents
-[[#Gitea Instance]]
[[#Create Repo via CLI]]
[[#Add Gitea as Remote]]
[[#Push & Pull]]
[[#SSH Alternative]]
[[#Git Tracking Explained]]
[[#Fix Tracking Branch]]

---

## Gitea Instance

| Detail | Value |
|--------|-------|
| URL | `http://192.168.68.200:8085` |
| SSH port | `222` |
| Container | `docker.gitea.com/gitea:latest` |

---

## Create Repo via CLI

```bash
# Using username/password
curl -X POST http://192.168.68.200:8085/api/v1/user/repos \
  -H "Content-Type: application/json" \
  -u YOUR_USER:YOUR_PASS \
  -d '{"name": "master-guide", "private": false, "auto_init": false}'

# Using API token (safer - no password in shell history)
# Generate token at: http://192.168.68.200:8085/user/settings/applications
curl -X POST http://192.168.68.200:8085/api/v1/user/repos \
  -H "Content-Type: application/json" \
  -H "Authorization: token YOUR_API_TOKEN" \
  -d '{"name": "master-guide", "private": false, "auto_init": false}'
```

---

## Add Gitea as Remote

```bash
# Add gitea as a second remote (keep origin pointing to GitHub)
git remote add gitea http://YOUR_USER:YOUR_PASS@192.168.68.200:8085/YOUR_USER/master-guide.git

# Verify both remotes exist
git remote -v
```

Expected output:
```
origin   https://github.com/xterm2000/master-guide.git (fetch)
origin   https://github.com/xterm2000/master-guide.git (push)
gitea    http://192.168.68.200:8085/YOUR_USER/master-guide.git (fetch)
gitea    http://192.168.68.200:8085/YOUR_USER/master-guide.git (push)
```

---

## Push & Pull

```bash
# Push/pull to GitHub
git push origin master
git pull origin master

# Push/pull to Gitea
git push gitea master
git pull gitea master

# Optional: push to BOTH with a single git push
git remote set-url --add --push origin http://192.168.68.200:8085/YOUR_USER/master-guide.git
git remote set-url --add --push origin https://github.com/xterm2000/master-guide.git
```

---

## SSH Alternative

Avoids passwords entirely — recommended for daily use.

```bash
# Add your public key in Gitea UI: Settings → SSH Keys → Add Key

# Switch remote to SSH
git remote set-url gitea ssh://git@192.168.68.200:222/YOUR_USER/master-guide.git

# Test the connection
ssh -T git@192.168.68.200 -p 222
```

---

## Git Tracking Explained

A **tracking branch** is the link between your local branch and a remote branch. It tells Git:
- Where to push when you run `git push` (no arguments)
- Where to pull from when you run `git pull` (no arguments)
- What to compare against for `git status`

| Without Tracking | With Tracking |
|-----------------|---------------|
| Must specify remote every time: `git push origin master` | `git push` just works |
| `git status` shows no ahead/behind info | `git status` shows `ahead by 2 commits` |
| Easy to push to wrong remote by mistake | Relationship is explicit and visible |

---

## Fix Tracking Branch

```bash
# Set local master to track origin/master (GitHub)
git branch --set-upstream-to=origin/master master

# Verify — look for [origin/master] in the output
git branch -vv

# Check all remotes
git remote -v
```

Expected output after fix:
```
* master  abc1234 [origin/master] your commit message
```