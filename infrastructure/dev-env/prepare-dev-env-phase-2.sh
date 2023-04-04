#!/bin/bash

# Configure 1password
sudo mkdir /etc/1password
echo "vivaldi-bin" | sudo tee /etc/1password/custom_allowed_browsers
sudo chown root:root /etc/1password/custom_allowed_browsers
sudo chmod 755 /etc/1password/custom_allowed_browsers

cat <<EOF > /home/zhorvath83/.ssh/config
Host *
    IdentityAgent ~/.1password/agent.sock
    ForwardAgent yes
EOF

op read -o /home/zhorvath83/.config/sops/age/keys.txt op://g5kjo4p7of2ecxtfgtly4hckji/homelab-age-key/keys.txt

kubectl create secret generic onepassword-connect-secret -n kube-system \
 --from-literal=1password-credentials.json=$(op read op://2mq4lqi5lyw6c4yghls5nilcti/1p-kubernetes-credentials-file/1password-credentials-base64.json) \
 --from-literal=token=$(op read op://2mq4lqi5lyw6c4yghls5nilcti/1p-kubernetes-access-token/credential)

# Git config
export GIT_USERNAME=$(op read op://g5kjo4p7of2ecxtfgtly4hckji/github.com/username)
export GIT_EMAIL=$(op read op://g5kjo4p7of2ecxtfgtly4hckji/github.com/email)

git config --global --add pull.rebase false
git config --global --add user.name $GIT_USERNAME
git config --global --add user.email $GIT_EMAIL
git config --global init.defaultBranch main
git config --global alias.pullall '!git pull && git submodule update --init --recursive'

