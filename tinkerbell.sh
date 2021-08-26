#!/bin/bash

packages="podman git jq"
sudo dnf install -y ${packages}

git clone https://github.com/tinkerbell/sandbox.git
ORG_NAME=tinkerbell
REPO_NAME=sandbox
LATEST_VERSION=$(curl -s https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/releases/latest | grep "tag_name" | cut -d'v' -f2 | cut -d'"' -f1)
curl -L -o ${REPO_NAME}.tar.gz https://github.com/${ORG_NAME}/${REPO_NAME}/archive/v${LATEST_VERSION}.tar.gz
tar xf sandbox.tar.gz

interface=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')
interface=$(echo ${interface} | awk '{ print $2 }')
# : ${interface=interface}

# echo $interface

cd sandbox-0.5.0 
rm -rf cmd CODEOWNERS go.mod go.sum LICENSE README.md script setup.sh shell.nix test

./generate-envrc.sh ${interface} > .env

sed -i 's|export TINKERBELL_HOST_IP=.*|export TINKERBELL_HOST_IP=192.168.1.86|' .env
#!/bin/bash

manual_interface=$1
manual_tinkerbell_ip=$2

packages="podman git jq"
sudo dnf install -y ${packages}

git clone https://github.com/tinkerbell/sandbox.git
ORG_NAME=tinkerbell
REPO_NAME=sandbox
LATEST_VERSION=$(curl -s https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/releases/latest | grep "tag_name" | cut -d'v' -f2 | cut -d'"' -f1)
curl -L -o ${REPO_NAME}.tar.gz https://github.com/${ORG_NAME}/${REPO_NAME}/archive/v${LATEST_VERSION}.tar.gz
tar xf sandbox.tar.gz

# interface_name=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')
# interface_name=$(echo ${interface} | awk '{ print $2 }')
# : ${manual_interface=interface_name}
# : ${manual_tinkerbell_ip=192.168.1.1}

# echo $interface

cd sandbox-0.5.0 
rm -rf cmd CODEOWNERS go.mod go.sum LICENSE README.md script setup.sh shell.nix test

./generate-envrc.sh ${manual_interface} > .env

sed -i 's|export TINKERBELL_HOST_IP=.*|export TINKERBELL_HOST_IP=${manual_tinkerbell_ip}|' .env

curl -L -O https://raw.githubusercontent.com/jkl92/podman-tinkerbell/main/podman-setup.sh

echo "ip_unprivileged_port_start=68" | sudo tee /etc/sysctl.d/99-tinkerbell-ports.conf

echo "ip_unprivileged_port_start=68" | sudo tee -a /etc/sysctl.conf 
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-tinkerbell-forward.conf

sudo sysctl net.ipv4.ip_unprivileged_port_start=68
sudo sysctl net.ipv4.ip_forward=1

chmod 700 podman-setup.sh
./podman-setup.sh

curl -L -O https://raw.githubusercontent.com/jkl92/podman-tinkerbell/main/podman-tinkerbell.sh

chmod 700 podman-tinkerbell.sh
./podman-tinkerbell.sh
curl -L -O https://raw.githubusercontent.com/jkl92/podman-tinkerbell/main/podman-setup.sh

echo "ip_unprivileged_port_start=68" | sudo tee /etc/sysctl.d/99-tinkerbell-ports.conf

echo "ip_unprivileged_port_start=68" | sudo tee -a /etc/sysctl.conf 
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-tinkerbell-forward.conf

sudo sysctl net.ipv4.ip_unprivileged_port_start=68
sudo sysctl net.ipv4.ip_forward=1

chmod 700 podman-setup.sh
./podman-setup.sh

curl -L -O https://raw.githubusercontent.com/jkl92/podman-tinkerbell/main/podman-tinkerbell.sh

chmod 700 podman-tinkerbell.sh
./podman-tinkerbell.sh
