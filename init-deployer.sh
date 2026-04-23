#!/bin/sh
sudo -E apt install git -y
sudo -E apt install vim -y
sudo -E apt install ansible -y
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
export https_proxy=http://proxy.esl.cisco.com:80
git clone https://github.com/tbachman/kolla-openstack.git

