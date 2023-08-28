#!/bin/bash

ARCH=amd64

# renovate: datasource=github-releases depName=mikefarah/yq
YQ_VERSION=v4.33.1

# renovate: datasource=github-releases depName=mozilla/sops
SOPS_VERSION=v3.7.3

# renovate: datasource=github-releases depName=FiloSottile/age
AGE_VERSION=v1.1.1

# renovate: datasource=golang-version
GO_VERSION=1.19.4

GOPATH=~/go

## ~/.config/Code/User
# COPY --chown=coder:coder config/code-server/settings.json ~/.local/share/code-server/User/settings.json
# # COPY --chown=coder:coder config/code-server/coder.json ~/.local/share/code-server/coder.json
# COPY --chown=coder:coder config/mc/ini ~/.config/mc/ini
# COPY --chown=coder:coder scripts/clone_git_repos.sh ~/entrypoint.d/clone_git_repos.sh
# COPY --chown=coder:coder --chmod=600 config/ssh/config ~/.ssh/config
# COPY --chown=coder:coder --chmod=600 config/supervisord/supervisord.conf /etc/supervisord.conf

mkdir -p ~/projects
mkdir -p ~/.ssh

# Ensure the contrib and non-free repositories are enabled
sudo apt-add-repository contrib non-free -y

# Installing common dependecies
sudo apt update -y
sudo apt install --assume-yes --no-install-recommends wget curl gnupg

# Adding 1password repo and debsig-verify policy
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" |
  sudo tee /etc/apt/sources.list.d/1password.list
sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
  sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol
sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

# Adding Lens repo
curl -fsSL https://downloads.k8slens.dev/keys/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/lens-archive-keyring.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/lens-archive-keyring.gpg] https://downloads.k8slens.dev/apt/debian stable main" | sudo tee /etc/apt/sources.list.d/lens.list > /dev/null

# Adding Vivaldi browser's repo
wget -qO- https://repo.vivaldi.com/archive/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/keyrings/vivaldi.gpg
sudo sh -c 'echo "deb [arch=amd64,armhf signed-by=/etc/apt/keyrings/vivaldi.gpg] https://repo.vivaldi.com/archive/deb stable main" > /etc/apt/sources.list.d/vivaldi.list' 

# VSC repo
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg

# Adding Hashicorp repo
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Adding Node.js repo
wget -qO- https://deb.nodesource.com/setup_19.x | sudo -E bash -

# Installing apps
sudo apt update -y
sudo apt install --assume-yes --no-install-recommends \
    nano \
    iftop \
    iotop \
    traceroute \
    nfs-common \
    autofs \
    1password \
    1password-cli \
    lens \
    code \
    terraform \
    nodejs \
    net-tools \
    iputils-ping \
    jq \
    software-properties-common \
    python3 \
    python3-pip \
    pipx \
    build-essential \
    python3-dev \
    mc \
    nautilus-admin \
    ca-certificates \
    unzip \
    bzr \
    sshpass \
    git-extras \
    apache2-utils \
    ttf-mscorefonts-installer \
    flatpak \
    gnome-software-plugin-flatpak \
    gnome-tweaks \
    ffmpeg \
    build-essential \
    vivaldi-stable

# Adding Flathub repository
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

flatpak install flathub \
    org.gimp.GIMP \
    com.github.PintaProject.Pinta \
    org.kde.kolourpaint \
    org.kde.digikam \
    org.kde.kdenlive \
    com.github.dail8859.NotepadNext \
    org.flameshot.Flameshot \
    io.freetubeapp.FreeTube \
    com.dropbox.Client \
    org.videolan.VLC

# NAS automount
echo '/net    -hosts -fstype=nfs,rw' | sudo tee --append /etc/auto.master
sudo systemctl restart autofs
ln --symbolic /net/nas/export ~/nas

# pipx path
pipx ensurepath

# Installing pypisearch, pre-commit, pre-commit-hooks, yamllint, ansible-core
pipx install pypisearch
pipx install pre-commit
pipx install pre-commit-hooks
pipx install python-Levenshtein
pipx install yamllint
pipx install ansible-core
pipx install gnome-extensions-cli --system-site-packages

pipx list

# Installing SOPS, a simple and flexible tool for managing secrets
sudo wget -q "https://github.com/mozilla/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux" -O /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Installing age, a simple, modern and secure encryption tool. Used with SOPS.
wget -q "https://github.com/FiloSottile/age/releases/latest/download/age-${AGE_VERSION}-linux-${ARCH}.tar.gz" -O /tmp/age.tar.gz
sudo tar -C /usr/local/bin -xzf /tmp/age.tar.gz --strip-components 1
sudo chmod +x /usr/local/bin/age
sudo chmod +x /usr/local/bin/age-keygen

# Installing yq, a command-line YAML, JSON and XML processor
sudo wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -O /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq

# Golang for Go-Task
GOPKG="go${GO_VERSION}.linux-${ARCH}.tar.gz"; wget -q "https://golang.org/dl/${GOPKG}" -O /tmp/${GOPKG}
sudo tar -C /usr/local -xzf "/tmp/${GOPKG}"
mkdir -p "${GOPATH}"
#go version
echo "export GOPATH=$GOPATH" | tee --append ~/.profile
echo "export PATH=$PATH:$HOME/bin:$HOME/.local/bin:$GOPATH/bin:/usr/local/go/bin" | tee --append ~/.profile
# shellcheck source=/dev/null
source ~/.profile

# Installing go-task
sudo sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Installing Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
sudo mv kubectl /usr/local/bin/kubectl
sudo chmod +x /usr/local/bin/kubectl

# Installing Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Installing Helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Adding github.com SSH keys to known_hosts
curl --silent https://api.github.com/meta \
  | jq --raw-output '"github.com "+.ssh_keys[]' >> ~/.ssh/known_hosts

# Installing vscode plugins
code \
    --install-extension equinusocio.vsc-material-theme \
    --install-extension PKief.material-icon-theme \
    --install-extension Rubymaniac.vscode-paste-and-indent \
    --install-extension redhat.vscode-yaml \
    --install-extension esbenp.prettier-vscode \
    --install-extension signageos.signageos-vscode-sops \
    --install-extension MichaelCurrin.auto-commit-msg \
    --install-extension hashicorp.terraform \
    --install-extension weaveworks.vscode-gitops-tools

# Install Gnome Extensions
gext install 779 307 5219 36 1262 2236 4269

gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.desktop.interface clock-show-weekday true
# gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true
gsettings set org.gnome.desktop.interface document-font-name 'Open Sans 11'
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
gsettings set org.gnome.desktop.interface font-hinting 'slight'
gsettings set org.gnome.desktop.interface monospace-font-name 'Fira Code weight=453 11'
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize-or-previews'
gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 40
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
gsettings set org.gnome.shell.extensions.dash-to-dock multi-monitor true

sh -c 'cat >> ~/.config/mimeapps.list << EOF
x-scheme-handler/http=vivaldi-stable.desktop
x-scheme-handler/https=vivaldi-stable.desktop
text/html=vivaldi-stable.desktop
application/xhtml+xml=vivaldi-stable.desktop
EOF'

echo "Please log in and set up 1password developer settings. Then run phase 2 script!"
