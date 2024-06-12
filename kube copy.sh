#!/bin/bash

# 设置变量
IMAGES="block1 compute1 controller database network"
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
mount -t bpf bpffs /sys/fs/bpf

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

# 创建 Kubernetes 部署和服务
echo "Deploying controller..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app: controller
  template:
    metadata:
      labels:
        app: controller
    spec:
      containers:
      - name: controller
        image: controller-image:latest
        imagePullPolicy: Never
        command: ["tini", "--", "/root/controller_setup.sh"]
        envFrom:
        - configMapRef:
            name: common-env
        ports:
        - containerPort: 80
        - containerPort: 6080
EOF

echo "Deploying network..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: network
spec:
  replicas: 1
  selector:
    matchLabels:
      app: network
  template:
    metadata:
      labels:
        app: network
    spec:
      containers:
      - name: network
        securityContext:
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
          privileged: true
        env:
        - name: PROVIDER_INTERFACE_NAME
          value: "br-provider" # 替换为实际的提供者接口名称
        image: network-image:latest
        imagePullPolicy: Never
        command: ["tini", "--", "/root/network_setup.sh"]
        envFrom:
        - configMapRef:
            name: common-env
EOF

echo "Deploying compute1..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: compute1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: compute1
  template:
    metadata:
      labels:
        app: compute1
    spec:
      containers:
      - name: compute1
        securityContext:
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
          privileged: true
        env:
        - name: PROVIDER_INTERFACE_NAME
          value: "br-provider" # 替换为实际的提供者接口名称
        image: compute1-image:latest
        imagePullPolicy: Never
        command: ["tini", "--", "/root/compute1_setup.sh"]
        envFrom:
        - configMapRef:
            name: common-env
EOF

echo "Deploying database..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: database
        image: database-image:latest
        imagePullPolicy: Never
        envFrom:
        - configMapRef:
            name: common-env
EOF

echo "Deploying block1..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: block1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: block1
  template:
    metadata:
      labels:
        app: block1
    spec:
      containers:
      - name: block1
        securityContext:
          privileged: true
        image: block1-image:latest
        imagePullPolicy: Never
        command: ["tini", "--", "/root/block1_setup.sh"]
        envFrom:
        - configMapRef:
            name: common-env
EOF

echo "Deploying nfs_server..."
docker pull erichough/nfs-server:latest
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-server
  template:
    metadata:
      labels:
        app: nfs-server
    spec:
      containers:
      - name: nfs-server
        image: erichough/nfs-server:latest
        imagePullPolicy: Never
        securityContext:
          privileged: true
        volumeMounts:
        - name: nfs-root
          mountPath: /srv/nfs4
          readOnly: false
        - name: nfs-home
          mountPath: /srv/nfs4/home
          readOnly: false
        - name: exports
          mountPath: /etc/exports
          readOnly: true
      volumes:
      - name: nfs-root
        hostPath:
          path: /home/user/nfs_root
      - name: nfs-home
        hostPath:
          path: /home/user/nfs_home
      - name: exports
        hostPath:
          path: $(pwd)/exports.txt
EOF

echo "Deploying memcached_server..."
docker pull memcached:latest
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memcached-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memcached-server
  template:
    metadata:
      labels:
        app: memcached-server
    spec:
      containers:
      - name: memcached-server
        image: memcached:latest
        imagePullPolicy: Never
EOF

echo "Deploying rabbitmq_server..."
docker pull rabbitmq:3.8.2
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rabbitmq-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq-server
  template:
    metadata:
      labels:
        app: rabbitmq-server
    spec:
      containers:
      - name: rabbitmq-server
        image: rabbitmq:3.8.2
        imagePullPolicy: Never
        volumeMounts:
        - name: definitions
          mountPath: /etc/rabbitmq/definitions.json
          readOnly: false
        - name: config
          mountPath: /etc/rabbitmq/rabbitmq.conf
          readOnly: false
      volumes:
      - name: definitions
        hostPath:
          path: $(pwd)/config/rabbitmq/definitions.json
      - name: config
        hostPath:
          path: $(pwd)/config/rabbitmq/rabbitmq.conf
EOF


echo "All deployments are applied."
