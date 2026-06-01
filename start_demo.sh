#!/bin/bash
# Startup Script: AWX Demo Environment

echo "================================================="
echo "1. Waking up the Kubernetes Cluster..."
echo "================================================="
# This is safe to run even if the cluster is already running
minikube start --driver=docker

echo "================================================="
echo "2. Your AWX Credentials:"
echo "================================================="
echo "Username: admin"
echo -n "Password: "
kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 --decode
echo -e "\n"

echo "================================================="
echo "3. Opening Network Tunnel to AWX..."
echo "================================================="
echo "⚠️  WARNING: Leave this terminal window open!"
echo "If you close this terminal, the dashboard will go offline."
echo "Press Ctrl+C when you are done working."
echo "================================================="
echo ""

# Launch the tunnel (this command will block the terminal and stay running)
minikube service awx-demo-service -n awx --url