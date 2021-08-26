#!/bin/bash

packages="podman git jq"
sudo dnf install -y ${packages}

git clone https://github.com/tinkerbell/sandbox.git
ORG_NAME=tinkerbell
REPO_NAME=sandbox
LATEST_VERSION=$(curl -s https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/releases/latest | grep "tag_name" | cut -d'v' -f2 | cut -d'"' -f1)
curl -L -o ${REPO_NAME}.tar.gz https://github.com/${ORG_NAME}/${REPO_NAME}/archive/v${LATEST_VERSION}.tar.gz
tar xf sandbox.tar.gz

rm -rf cmd CODEOWNERS go.mod go.sum LICENSE README.md script setup.sh shell.nix test

interface=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')
interface=$(echo ${interface} | awk '{ print $2 }')
# : ${interface=interface}

# echo $interface

cd sandbox-0.5.0 
./generate-envrc.sh ${interface} > .env

sed -i 's|export TINKERBELL_HOST_IP=.*|export TINKERBELL_HOST_IP=10.0.3.15|' .env

chmod 700 podman-setup.sh
./podman-setup.sh

chmod 700 start-tinkerbell.sh
./start-tinkerbell.sh
