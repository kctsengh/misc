#!/bin/bash

set -e


## Install Kind: c1, c2
cat <<EOF > kind-c1.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "172.18.10.0/24"
nodes:
- role: control-plane
EOF

cat <<EOF > kind-c2.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "172.18.11.0/24"
nodes:
- role: control-plane
EOF


kind create cluster --image=kindest/node:v1.30.3  --name=c1 --config=kind-c1.yaml
kind create cluster --image=kindest/node:v1.30.3  --name=c2 --config=kind-c2.yaml
sleep 60



## Install Istio cluster mesh
cd $1
#git clean -df
mkdir -p certs
pushd certs

make -f ../tools/certs/Makefile.selfsigned.mk root-ca

make -f ../tools/certs/Makefile.selfsigned.mk cluster1-cacerts
make -f ../tools/certs/Makefile.selfsigned.mk cluster2-cacerts

kubectl --context="${CTX_CLUSTER1}"  create namespace istio-system 
kubectl --context="${CTX_CLUSTER1}"  create secret generic cacerts -n istio-system \
      --from-file=cluster1/ca-cert.pem \
      --from-file=cluster1/ca-key.pem \
      --from-file=cluster1/root-cert.pem \
      --from-file=cluster1/cert-chain.pem

kubectl --context="${CTX_CLUSTER2}"  create namespace istio-system
kubectl --context="${CTX_CLUSTER2}"  create secret generic cacerts -n istio-system \
      --from-file=cluster2/ca-cert.pem \
      --from-file=cluster2/ca-key.pem \
      --from-file=cluster2/root-cert.pem \
      --from-file=cluster2/cert-chain.pem
popd

# Install Istio c1
cat <<EOF > cluster1.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: ambient
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1
EOF
istioctl install --context="${CTX_CLUSTER1}" -f cluster1.yaml --skip-confirmation


# Install Istio c2

cat <<EOF > cluster2.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: ambient
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster2
      network: network1
EOF

istioctl install --context="${CTX_CLUSTER2}" -f cluster2.yaml --skip-confirmation


# Enable Endpoint Discovery
istioctl create-remote-secret \
  --context="${CTX_CLUSTER1}" \
  --name=cluster1 > secret1.yaml
c1_ip=$(docker inspect   -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'  c1-control-plane)
c1_apiserver="        server: https://${c1_ip}:6443"
sed -i "/https/c\\$c1_apiserver" secret1.yaml

cat secret1.yaml | kubectl apply -f - --context="${CTX_CLUSTER2}"

##
istioctl create-remote-secret \
  --context="${CTX_CLUSTER2}" \
  --name=cluster2 > secret2.yaml

c2_ip=$(docker inspect   -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}'  c2-control-plane)
c2_apiserver="        server: https://${c2_ip}:6443"
sed -i "/https/c\\$c2_apiserver" secret2.yaml
cat secret2.yaml | kubectl apply -f - --context="${CTX_CLUSTER1}"



## patch clusterrule
kubectl  --context="${CTX_CLUSTER1}"  patch ClusterRole/istio-reader-clusterrole-istio-system --type='json' -p='[{"op": "add", "path": "/rules/0", "value":{ "apiGroups": [""], "resources": ["configmaps"], "verbs": ["watch","get","list"]}}]'

kubectl  --context="${CTX_CLUSTER2}"  patch ClusterRole/istio-reader-clusterrole-istio-system --type='json' -p='[{"op": "add", "path": "/rules/0", "value":{ "apiGroups": [""], "resources": ["configmaps"], "verbs": ["watch","get","list"]}}]'

## Verify
kubectl create --context="${CTX_CLUSTER1}" namespace sample
kubectl create --context="${CTX_CLUSTER2}" namespace sample

kubectl label --context="${CTX_CLUSTER1}" namespace sample istio.io/dataplane-mode=ambient

kubectl label --context="${CTX_CLUSTER2}" namespace sample  istio.io/dataplane-mode=ambient


kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/helloworld/helloworld.yaml \
    -l service=helloworld -n sample
kubectl apply --context="${CTX_CLUSTER2}" \
    -f samples/helloworld/helloworld.yaml \
    -l service=helloworld -n sample

kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/helloworld/helloworld.yaml \
    -l version=v1 -n sample

kubectl apply --context="${CTX_CLUSTER2}" \
    -f samples/helloworld/helloworld.yaml \
    -l version=v2 -n sample

kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/sleep/sleep.yaml -n sample
kubectl apply --context="${CTX_CLUSTER2}" \
    -f samples/sleep/sleep.yaml -n sample





