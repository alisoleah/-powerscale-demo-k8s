#!/bin/bash
# deploy_isilon_sim.sh
# Automates the deployment of a single-node OneFS Simulator

OVA_PATH="/home/galala/powerscale-demo-k8s/Isilon_OneFS_Simulator_9.4.0.0.ova"
VM_NAME="Site-B-Isilon-Target"
DATASTORE="datastore1"
NETWORK="VM Network"
ESXI_HOST="root:dell1234d@192.168.1.100"

echo "🚀 Deploying PowerScale Simulator: $VM_NAME..."

ovftool \
  --acceptAllEulas \
  --name="$VM_NAME" \
  --datastore="$DATASTORE" \
  --net:"Internal"="$NETWORK" \
  --net:"External"="$NETWORK" \
  --powerOn \
  "$OVA_PATH" \
  "vi://$ESXI_HOST/"

echo "✅ Deployment complete. VM is booting."
echo "Note: You will need to open the VM console once to complete the initial cluster setup wizard."