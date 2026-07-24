# setup  WSL 

## on windows 

`.wslconfig` file

```ini
# system defaults
[wsl2]
memory=8GB
swap=4GB
defaultVhdSize=20GB

# linux files premissions insteead of 777
[automount]
options = "metadata,umask=22,fmask=111"

```

- make dir for the distro
- download tar with system files 
install 

```bash
wsl --import RockyLinux <TARGET_DIR>\RockyLinux .\Rocky-9-Container-Base.latest.x86_64.tar.xz --version 2
```

after that as root :

```bash
useradd -m -G wheel mitek
passwd mitek
```

set the user as default:

```bash
cat >> /etc/wsl.conf << 'EOF'
[user]
default=mitek
EOF
```

reboot wsl
```bash
wsl --terminate RockyLinux
wsl -d RockyLinux
```

## install programs 
```bash
#!/bin/bash
set -e

pause() {
    echo
    read -rp ">>> Section done. Press Enter to continue (Ctrl+C to abort)..." _
    echo
}

## update
sudo dnf update -y
pause

## basics 
sudo dnf install ncurses util-linux procps-ng which -y 
pause

## epel
sudo dnf install epel-release -y
pause

## misc progs
sudo dnf install fastfetch vim jq wget curl bind-utils git -y
pause



#compilers
sudo dnf install gcc gcc-c++ gdb make -y
pause

# midnight commander
sudo dnf install mc -y
pause

## begin node

# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"
# Download and install Node.js:
nvm install 24
# Verify the Node.js version:
node -v # Should print "v24.18.0".
# Verify npm version:
npm -v # Should print "11.16.0".
## end  node
pause

## begin docker
sudo dnf remove docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine \
                  podman \
                  runc

sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo systemctl enable --now docker
sudo groupadd docker
sudo usermod -aG docker $USER

##  end docker
pause

echo "All sections complete."
```
