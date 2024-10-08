#!/bin/bash
set -e
export KUBECONFIG=~/.kube/config

echo "= Install kind k8s"
## Install Kind: c1
cat <<EOF > kind-c1.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF

kind create cluster --image=kindest/node:v1.30.2  --name=c1 --config=kind-c1.yaml
sleep 50

# Install metallb
echo "= Install metallb"
kubectl --context="${CTX_CLUSTER1}"  apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

sleep 10;
cat <<EOF > c1-ip-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  namespace: metallb-system
  name: doc-example
spec:
  addresses:
  - 172.18.0.100-172.18.0.120

EOF


cat <<EOF > L2Advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system

EOF

kubectl --context="${CTX_CLUSTER1}" -n metallb-system wait --for=condition=ready pod -l app=metallb --timeout=120s
kubectl --context="${CTX_CLUSTER1}"  apply -f c1-ip-pool.yaml
kubectl --context="${CTX_CLUSTER1}"  apply -f L2Advertisement.yaml


## Install Istio cluster mesh

kubectl --context="${CTX_CLUSTER1}"  create namespace istio-system

# Install Istio c1
cat <<EOF > cluster1.yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      variant: debug
  profile: ambient
  components:
    ingressGateways:
    - enabled: true
      name: my-ingressgateway
    pilot:
      k8s:
        env:
          - name: PILOT_FILTER_GATEWAY_CLUSTER_CONFIG
            value: "true"
          - name: PILOT_HTTP10
            value: "true"
EOF
echo "= Install Istio ambient ..."
cp cluster1.yaml /root/istioctl/1-23-0/
cd /root/istioctl/1-23-0
./istioctl install --context="${CTX_CLUSTER1}" -f cluster1.yaml --skip-confirmation

kubectl --context="${CTX_CLUSTER1}" taint nodes c1-control-plane  node-role.kubernetes.io/control-plane:NoSchedule-

cd $1
echo "= Deploy test client pod in ns/sample and server pod in ns/sample2"
kubectl create --context="${CTX_CLUSTER1}" namespace sample

kubectl label namespace sample istio.io/dataplane-mode=ambient
kubectl create --context="${CTX_CLUSTER1}" namespace sample2

kubectl label namespace sample2 istio.io/dataplane-mode=ambient


kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/helloworld/helloworld.yaml \
    -l service=helloworld -n sample2

kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/helloworld/helloworld.yaml \
    -l version=v1 -n sample2


kubectl apply --context="${CTX_CLUSTER1}" \
    -f samples/sleep/sleep.yaml -n sample
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml; }

kubectl -n sample2 patch deployment helloworld-v1 -p '{"spec":{"replicas":2}}'

kubectl --context="${CTX_CLUSTER1}" -n sample2 wait --for=condition=ready pod -l app=helloworld --timeout=120s

kubectl --context="${CTX_CLUSTER1}" -n sample wait --for=condition=ready pod -l app=sleep --timeout=120s

cat <<EOF > gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  labels:
    istio.io/waypoint-for: service
  name: waypoint
  namespace: sample2
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE

EOF

echo "= Install waypoint gateway in sample2"
kubectl apply -f gateway.yaml
istioctl waypoint apply -n sample2 --enroll-namespace

sleep 3;
cat <<EOF > dr.yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: hellodr
spec:
  host: helloworld.sample2.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      consistentHash:
        httpHeaderName: X-User  
EOF
echo "= Install consistent hash destinationRule"
kubectl -n sample2 apply -f dr.yaml
sleep 1
echo "= Show cluster rule in waypoint"
istioctl -n sample2  pc cluster $(kubectl -n sample2 get pod  --no-headers -o custom-columns=":metadata.name" | grep waypoint)

echo "= Test: client curl with fix HTTP header ..."
for i in {1..10} ; do  sleep 1 ; kubectl -n sample  exec $(kubectl -n sample  get pod  -l app=sleep --no-headers -o custom-columns=":metadata.name")  -- curl -s -H "X-User: abc" helloworld.sample2.svc.cluster.local:5000/hello ; done
