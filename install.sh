#!/bin/bash
# Uninstall K3s
/usr/local/bin/k3s-uninstall.sh
# Install K3S
echo "Installing K3S..."
curl -sfL https://get.k3s.io | sh -
echo "Waiting for node to be ready..."
sleep 30
sudo k3s kubectl get node
#Kubeconfig file permission
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
cp -R /etc/rancher/k3s/k3s.yaml /home/adm02/.kube/config
chown -R adm02:adm02 /home/adm02/.kube
# Install Cert-Manager
echo "Installing Cert-Manager"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
# Wait for Cert-Manger to be ready
echo "Waiting for Cert-Manager deployment to be ready..."
kubectl wait --namespace cert-manager --for=condition=Available deployment --all --timeout=120s
# Apply Cert-Manager configurations
echo "Applying Cert-Manger Configurations"
kubectl apply -k /home/adm02/n8n-test/cert-manager
# Install N8N
echo "Installing N8N..."
kubectl create ns n8n
kubectl apply -k /home/adm02/n8n-test/n8n
echo "Waiting for N8N..."
#Installing ELK
echo "Installing ELK"
kubectl create namespace logging
helm repo add elastic https://helm.elastic.co
helm repo update
helm install elasticsearch \
  --set replicas=1 \
  elastic/elasticsearch -n logging
helm install kibana \
  --set service.type=LoadBalancer \
  elastic/kibana -n logging
kubectl wait --namespace logging --for=condition=Available deployment --all --timeout=120s

echo "ELK Username"
kubectl get secrets --namespace=logging elasticsearch-master-credentials -ojsonpath='{.data.username}' | base64 -d

echo "ELK Password"
kubectl get secrets --namespace=logging elasticsearch-master-credentials -ojsonpath='{.data.password}' | base64 -d










