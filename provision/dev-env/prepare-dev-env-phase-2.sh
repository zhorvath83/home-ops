#!/bin/bash

# Configure 1password
sudo mkdir /etc/1password
echo "vivaldi-bin" | sudo tee /etc/1password/custom_allowed_browsers
sudo chown root:root /etc/1password/custom_allowed_browsers
sudo chmod 755 /etc/1password/custom_allowed_browsers

echo "export SSH_AUTH_SOCK=~/.1password/agent.sock" | sudo tee /etc/profile.d/1password-ssh-auth-sock.sh

cat <<EOF > /home/zhorvath83/.ssh/config
Host *
    IdentityAgent ~/.1password/agent.sock
    ForwardAgent yes
EOF

mkdir -p ~/.config/autostart \
  && cp /etc/xdg/autostart/gnome-keyring-ssh.desktop ~/.config/autostart/gnome-keyring-ssh.desktop \
  && echo "Hidden=true" >> ~/.config/autostart/gnome-keyring-ssh.desktop

# Configure age for Mozilla Sops

mkdir -p /home/zhorvath83/.config/sops/age \
  && op read -o /home/zhorvath83/.config/sops/age/keys.txt op://HomeOps/homelab-age-key/keys.txt

# Git config
GIT_USERNAME=$(op read op://Personal/github.com/username)
export GIT_USERNAME

GIT_EMAIL=$(op read op://Personal/github.com/email)
export GIT_EMAIL

git config --global --add pull.rebase false
git config --global --add user.name "$GIT_USERNAME"
git config --global --add user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global alias.pullall '!git pull && git submodule update --init --recursive'

pipx upgrade-all
