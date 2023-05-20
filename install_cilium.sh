#!/bin/bash

wget https://docs.cilium.io/en/stable/_downloads/5d189e574ddd393eb1bcf12c6937ce0f/kind-config.yaml

kind create cluster --config=kind-config.yaml

kubectl cluster-info --context kind-kind

helm repo add cilium https://helm.cilium.io/

docker pull quay.io/cilium/cilium:v1.13.2
kind load docker-image quay.io/cilium/cilium:v1.13.2

helm install cilium cilium/cilium --version 1.13.2 \
	   --namespace kube-system \
	      --set image.pullPolicy=IfNotPresent \
	         --set ipam.mode=kubernetes

CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

cilium connectivity test

