#!/bin/bash
# Deploy NFS Demo Client Containers
# Builds and starts 2 privileged Ubuntu containers on the minikube network.
# Once SSH is ready, automatically triggers the AWX mount job.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NFS_CLIENTS_DIR="$SCRIPT_DIR/nfs-clients"

CLIENT1_IP="192.168.49.10"
CLIENT2_IP="192.168.49.11"
AWX_USER="admin"
MOUNT_TEMPLATE_NAME="CLIENT: Mount NFS Shares (Initial Setup)"

# ---------------------------------------------------------------
# Helper: resolve AWX base URL from Minikube NodePort
# ---------------------------------------------------------------
get_awx_url() {
  local minikube_ip nodeport
  minikube_ip=$(minikube ip 2>/dev/null)
  nodeport=$(kubectl get service awx-demo-service -n awx \
    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
  if [ -n "$minikube_ip" ] && [ -n "$nodeport" ]; then
    echo "http://${minikube_ip}:${nodeport}"
  fi
}

# ---------------------------------------------------------------
# Helper: get AWX admin password from Kubernetes secret
# ---------------------------------------------------------------
get_awx_password() {
  kubectl get secret awx-demo-admin-password -n awx \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode
}

# ---------------------------------------------------------------
# Helper: launch AWX job template by name, return job URL
# ---------------------------------------------------------------
trigger_awx_job() {
  local awx_url="$1"
  local awx_pass="$2"
  local template_name="$3"

  # Look up template ID by name
  local template_id
  template_id=$(curl -s -u "${AWX_USER}:${awx_pass}" \
    "${awx_url}/api/v2/job_templates/" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
match = next((t['id'] for t in data.get('results', []) if t['name'] == '${template_name}'), None)
print(match or '')
" 2>/dev/null)

  if [ -z "$template_id" ]; then
    echo ""
    return 1
  fi

  # Launch the job
  local job_id
  job_id=$(curl -s -X POST \
    -u "${AWX_USER}:${awx_pass}" \
    -H "Content-Type: application/json" \
    "${awx_url}/api/v2/job_templates/${template_id}/launch/" \
    -d '{}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

  echo "$job_id"
}

# =================================================================
echo "================================================="
echo " PowerScale NFS Client Container Deployment"
echo "================================================="

# Verify minikube network exists
if ! docker network inspect minikube &>/dev/null; then
  echo "ERROR: minikube Docker network not found."
  echo "       Run ./start_demo.sh first, then re-run this script."
  exit 1
fi

echo ""
echo "Step 1: Building NFS client image..."
docker compose -f "$NFS_CLIENTS_DIR/docker-compose.yml" build

echo ""
echo "Step 2: Starting NFS client containers..."
docker compose -f "$NFS_CLIENTS_DIR/docker-compose.yml" up -d

echo ""
echo "Step 3: Waiting for SSH to become ready..."
ALL_READY=true
for ip in $CLIENT1_IP $CLIENT2_IP; do
  echo -n "  Waiting for $ip port 22..."
  READY=false
  for i in $(seq 1 30); do
    if docker run --rm --network minikube alpine sh -c "nc -z $ip 22" 2>/dev/null; then
      echo " ready."
      READY=true
      break
    fi
    sleep 2
    echo -n "."
  done
  if [ "$READY" = false ]; then
    echo " TIMEOUT — check: docker logs nfs-client-1"
    ALL_READY=false
  fi
done

# ---------------------------------------------------------------
# Step 4: Auto-trigger AWX mount job once VMs are up
# ---------------------------------------------------------------
echo ""
echo "Step 4: Auto-triggering AWX job '${MOUNT_TEMPLATE_NAME}'..."

AWX_URL=$(get_awx_url)
AWX_PASS=$(get_awx_password)

if [ -z "$AWX_URL" ] || [ -z "$AWX_PASS" ]; then
  echo "  SKIP: Cannot reach AWX (Minikube may not be running or AWX not deployed)."
  echo "        Start AWX with ./start_demo.sh, then trigger the job manually in AWX."
else
  if [ "$ALL_READY" = true ]; then
    JOB_ID=$(trigger_awx_job "$AWX_URL" "$AWX_PASS" "$MOUNT_TEMPLATE_NAME")

    if [ -n "$JOB_ID" ]; then
      echo "  AWX job launched successfully!"
      echo "  Job ID  : ${JOB_ID}"
      echo "  Track at: ${AWX_URL}/#/jobs/playbook/${JOB_ID}/output"
    else
      echo "  SKIP: Job template '${MOUNT_TEMPLATE_NAME}' not found in AWX."
      echo "        Run configure_awx.yml first to register templates, then re-run this script."
    fi
  else
    echo "  SKIP: One or more containers did not become ready. Fix the containers first."
  fi
fi

# =================================================================
echo ""
echo "================================================="
echo " DEPLOYMENT COMPLETE"
echo "================================================="
echo ""
echo "  Container         IP               SSH"
echo "  ─────────────── ──────────────── ──────────────────────────────"
echo "  nfs-client-1     $CLIENT1_IP      ssh root@$CLIENT1_IP  (pass: demo1234)"
echo "  nfs-client-2     $CLIENT2_IP      ssh root@$CLIENT2_IP  (pass: demo1234)"
echo ""
echo "  NFS Server (PowerScale): 192.168.243.50"
echo "  Mount Point on Clients : /mnt/powerscale_data"
echo ""
echo "  AWX URL    : ${AWX_URL:-run ./start_demo.sh to get URL}"
echo ""
echo "  To stop containers:  docker compose -f nfs-clients/docker-compose.yml down"
echo "  To view logs:        docker logs nfs-client-1"
echo "================================================="
