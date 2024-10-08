#!/bin/bash
set -e
echo "Install istioctl"
wget  https://github.com/istio/istio/releases/download/1.23.1/istioctl-1.23.1-linux-amd64.tar.gz
sudo tar zxvf istioctl-1.23.1-linux-amd64.tar.gz  -C /usr/bin/
echo "Install kind"

echo "Install kind"
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

echo "Download istio source code (1.23)"
git clone https://github.com/istio/istio.git  --branch 1.23.1 --single-branch

echo "Download&run test script"
wget https://raw.githubusercontent.com/kctsengh/misc/main/ambient-consistenthash.sh
sudo chmod +x ambient-consistenthash.sh
./ambient-consistenthash.sh "$(pwd)/istio"
