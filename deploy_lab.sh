#!/bin/bash
# Master Setup Script: AWX Production Operator via Minikube
set -e

echo "================================================="
echo "Step 1: Installing Kubernetes Tools"
echo "================================================="
# Install Minikube if missing
if ! command -v minikube &> /dev/null; then
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  rm minikube-linux-amd64
fi

# Install Kubectl if missing
if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install kubectl /usr/local/bin/kubectl
  rm kubectl
fi

echo "================================================="
echo "Step 2: Starting Local Kubernetes Cluster"
echo "================================================="
# Stop our old broken docker containers to free up your RAM and ports
docker stop $(docker ps -a -q) 2>/dev/null || true
docker rm $(docker ps -a -q) 2>/dev/null || true

# Start minikube with enough resources for AWX
minikube start --driver=docker --cpus=4 --memory=8192

echo "================================================="
echo "Step 3: Deploying AWX Production Instance"
echo "================================================="
# Create the isolated namespace
kubectl create namespace awx --dry-run=client -o yaml | kubectl apply -f -

# Apply the Kustomization file to deploy the AWX Operator
kubectl apply -k .

echo "Waiting for the AWX Operator to initialize..."
sleep 30

# Apply your instance configuration
kubectl apply -f awx-demo.yaml

echo "================================================="
echo "SUCCESS: AWX is now deploying!"
echo "The cluster is downloading the pre-compiled images (this usually takes 5-10 minutes depending on internet speed)."
echo "================================================="
echo ""
echo "-> To watch the deployment progress, run:"
echo "   kubectl get pods -n awx -w"
echo ""
echo "-> Once all pods show 'Running', get your Dashboard URL by running:"
echo "   minikube service awx-demo-service -n awx --url"
echo ""
echo "-> To retrieve your auto-generated admin password, run:"
echo "   kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 --decode ; echo"