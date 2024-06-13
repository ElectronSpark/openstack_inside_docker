#!/bin/bash

# 设置变量
IMAGES="block1 compute1 controller database network rabbitmq-server"
NAMESPACE="default"
# alias kubectl="minikube kubectl"

# # 构建 Docker 镜像
for i in $IMAGES; do
  echo "Building Docker image for ${i}.dockerfile..."
  docker build -t "${i}-image" -f "${i}.dockerfile" .
done

# 创建 ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: common-env
data:
$(awk 'NF && $1!~/^#/ {split($0, a, "="); printf "  %s: %s\n", a[1], a[2]}' common.env)
EOF

# for calio
sudo mount bpffs -t bpf /sys/fs/bpf
sudo mount --make-shared /sys/fs/bpf
# sudo mkdir -p /run/cilium/cgroupv2
# sudo mount -t cgroup2 none /run/cilium/cgroupv2
# sudo mount --make-shared /run/cilium/cgroupv2/

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/custom-resources.yaml

# 创建一个允许所有流量的 NetworkPolicy（仅供测试）
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
EOF

docker pull erichough/nfs-server:latest
docker pull memcached:latest
docker pull soarinferret/iptablesproxy

# 创建 Kubernetes 部署和服务
DEPLOYMENTS=$(ls kubes/*deployment.yaml)
SERVICES=$(ls kubes/*service.yaml)
for each in $DEPLOYMENTS; do
  kubectl apply -f ${each}
done
for each in $SERVICES; do
  kubectl apply -f ${each}
done
