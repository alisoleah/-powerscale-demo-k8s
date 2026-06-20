# NFS Client Automation Demo

This document covers the client-side NFS automation added to the PowerScale demo.
It explains what was built, how the networking works, how auto-triggering works,
and the exact steps to run the full end-to-end demo.

---

## What Was Added

The original demo only automated NFS on the **server side** (PowerScale exports, read-only flags, SyncIQ).
This extension adds automation for the **client side** — Linux machines that mount and unmount those NFS shares.

### New Files

```
nfs-clients/
  Dockerfile                    Ubuntu 22.04 image (nfs-common + openssh-server)
  docker-compose.yml            2 privileged containers on the minikube network

playbooks/
  client_mount_nfs.yml          Mount Site A export on clients, write fstab
  client_unmount_nfs.yml        Gracefully unmount and remove fstab entry
  client_switchover_nfs.yml     Switch clients from Site A to Site B (run after failover)
  client_switchback_nfs.yml     Switch clients from Site B to Site A (run after failback)

inventory/
  nfs_clients.ini               Reference inventory — edit with real client IPs if needed

deploy_nfs_clients.sh           Build image, start containers, wait for SSH, auto-trigger AWX
```

`awx_config/configure_awx.yml` and `collections/requirements.yml` were also updated to register
all new job templates, workflow templates, and the `ansible.posix` collection.

---

## Architecture

```
+----------------------------------------------------------+
|  WSL2 Host (Windows)                                     |
|                                                          |
|  +----------------------------------------------------+  |
|  |  minikube Docker network  192.168.49.0/24          |  |
|  |                                                    |  |
|  |  +------------------+  SSH  +-------------------+ |  |
|  |  |  AWX Task Pod    | ----> |  nfs-client-1     | |  |
|  |  |  (Kubernetes)    |       |  192.168.49.10    | |  |
|  |  |                  | ----> |  nfs-client-2     | |  |
|  |  +------------------+       |  192.168.49.11    | |  |
|  |                             +--------+----------+ |  |
|  +--------------------------------------|-------------+  |
|                                         | NFS mount      |
|                                         v                |
|                                192.168.243.50            |
|                                PowerScale Simulator      |
+----------------------------------------------------------+
```

**Key networking points:**
- Client containers run on the same `minikube` Docker bridge as the Kubernetes node (`192.168.49.2`)
- AWX task pods reach the containers directly through the Kubernetes node routing
- Docker NAT allows containers to reach the PowerScale at `192.168.243.50`
- `--privileged` mode is required on the containers so NFS mounts work inside them

---

## Client Container Details

| Container    | IP             | SSH Credentials  | Hostname       |
|--------------|----------------|------------------|----------------|
| nfs-client-1 | 192.168.49.10  | root / demo1234  | linux-client-1 |
| nfs-client-2 | 192.168.49.11  | root / demo1234  | linux-client-2 |

NFS mount point on clients: `/mnt/powerscale_data`

---

## Auto-Trigger: Job Fires When Containers Come Up

`deploy_nfs_clients.sh` automatically triggers the AWX mount job once SSH is confirmed ready:

1. Resolves the AWX URL from `minikube ip` + the Kubernetes NodePort
2. Reads the AWX admin password from the Kubernetes secret `awx-demo-admin-password`
3. Looks up the job template **"CLIENT: Mount NFS Shares (Initial Setup)"** by name via AWX REST API
4. Launches the job via `POST /api/v2/job_templates/{id}/launch/`
5. Prints the direct link to watch output in the AWX dashboard

If AWX is not yet running or the templates have not been registered, the script skips gracefully and prints instructions — it will not fail the deployment.

---

## AWX Workflow Templates (Single-Click Full Failover/Failback)

Two workflow templates chain the PowerScale and client operations together.
Press one button in AWX and both steps run automatically in sequence.

### WORKFLOW: Full Failover (PowerScale + Clients)

```
[Launch]
   |
   v
Step 1: EXECUTE: Site A to Site B NFS Failover
   |   PowerScale fences Site A, promotes Site B
   |   on SUCCESS
   v
Step 2: CLIENT: Switch NFS Mount to Site B (Post-Failover)
   |   All clients unmount Site A, mount Site B, fstab updated
   v
[Done]
```

### WORKFLOW: Full Failback (PowerScale + Clients)

```
[Launch]
   |
   v
Step 1: EXECUTE: Site B to Site A Failback (Restore)
   |   PowerScale restores Site A, fences Site B
   |   on SUCCESS
   v
Step 2: CLIENT: Switch NFS Mount to Site A (Post-Failback)
   |   All clients unmount Site B, mount Site A, fstab updated
   v
[Done]
```

If Step 1 fails, Step 2 does **not** run — clients are never switched to a site that is not ready.

---

## Prerequisites

- Minikube is up: `minikube status`
- AWX tunnel is active in a separate terminal: `./start_demo.sh`
- PowerScale simulator is reachable at `192.168.243.50`
- NFS exports exist on PowerScale: run `configure_shares.yml` first

---

## Step-by-Step Demo Guide

### Step 1 — Start the Lab

```bash
./start_demo.sh
```

Leave that terminal open — it holds the port-forward tunnel to AWX.

---

### Step 2 — Bootstrap AWX (first time only)

```bash
ansible-playbook awx_config/configure_awx.yml
```

This registers in AWX:
- `NFS_Client_SSH_Creds` — SSH credential (root / demo1234)
- `NFS Clients Inventory` — inventory with both client containers pre-loaded
- 4 individual client job templates
- **2 workflow templates** (Full Failover / Full Failback)

---

### Step 3 — Deploy Client Containers (auto-triggers mount job)

```bash
./deploy_nfs_clients.sh
```

This will:
1. Build the Ubuntu NFS client Docker image
2. Start two privileged containers on the minikube network
3. Wait until SSH is ready on both
4. **Automatically call AWX to launch "CLIENT: Mount NFS Shares (Initial Setup)"**
5. Print the job URL

Expected output when auto-trigger fires:
```
Step 4: Auto-triggering AWX job 'CLIENT: Mount NFS Shares (Initial Setup)'...
  AWX job launched successfully!
  Job ID  : 42
  Track at: http://192.168.49.2:32825/#/jobs/playbook/42/output
```

Verify the mounts landed:
```bash
docker exec nfs-client-1 df -h /mnt/powerscale_data
docker exec nfs-client-1 cat /etc/fstab
```

---

### Step 4 — Full Failover (Single Click)

In AWX, launch:

**`WORKFLOW: Full Failover (PowerScale + Clients)`**

AWX runs both steps in sequence:
- Step 1: fences Site A, promotes Site B on PowerScale
- Step 2 (only on success): switches all client mounts from Site A to Site B

---

### Step 5 — Full Failback (Single Click)

In AWX, launch:

**`WORKFLOW: Full Failback (PowerScale + Clients)`**

AWX runs both steps in sequence:
- Step 1: restores Site A as primary, fences Site B on PowerScale
- Step 2 (only on success): switches all client mounts back to Site A

---

## All AWX Templates at a Glance

| Template | Type | Purpose |
|---|---|---|
| SETUP: PowerScale Loopback Demo | Job | One-time SyncIQ setup |
| SETUP: PowerScale Shares and Quotas | Job | Create NFS/SMB exports |
| EXECUTE: Site A to Site B NFS Failover | Job | PowerScale failover only |
| EXECUTE: Site B to Site A Failback (Restore) | Job | PowerScale failback only |
| CLIENT: Mount NFS Shares (Initial Setup) | Job | Mount Site A on all clients |
| CLIENT: Unmount NFS Shares (Cleanup) | Job | Unmount and clean fstab |
| CLIENT: Switch NFS Mount to Site B (Post-Failover) | Job | Remount clients to Site B |
| CLIENT: Switch NFS Mount to Site A (Post-Failback) | Job | Remount clients to Site A |
| DANGER: Reset Lab (Nuke & Pave) | Job | Destroy everything |
| **WORKFLOW: Full Failover (PowerScale + Clients)** | **Workflow** | **Failover in one click** |
| **WORKFLOW: Full Failback (PowerScale + Clients)** | **Workflow** | **Failback in one click** |

---

## Overridable Variables

All playbook defaults can be overridden as AWX extra vars at launch time.

| Variable | Default | Description |
|---|---|---|
| `powerscale_ip` | `192.168.243.50` | PowerScale cluster IP |
| `nfs_export_path` | `/ifs/data/source` | Export path (mount playbook only) |
| `nfs_export_site_a` | `/ifs/data/source` | Site A export path |
| `nfs_export_site_b` | `/ifs/data/target` | Site B export path |
| `client_mount_point` | `/mnt/powerscale_data` | Local mount point on client |
| `client_nfs_options` | `rw,sync,hard,intr,nfsvers=3,timeo=14,retrans=3` | NFS mount options |

---

## Container Management

```bash
# Start containers
docker compose -f nfs-clients/docker-compose.yml up -d

# Stop containers
docker compose -f nfs-clients/docker-compose.yml down

# View container logs
docker logs nfs-client-1

# Open a shell on a client
docker exec -it nfs-client-1 bash

# Check current mounts and fstab
docker exec nfs-client-1 df -h
docker exec nfs-client-1 cat /etc/fstab
```

---

## Troubleshooting

**Auto-trigger skipped: template not found**
Run `configure_awx.yml` first to register the templates, then re-run `deploy_nfs_clients.sh`.

**Auto-trigger skipped: cannot reach AWX**
AWX must be running before `deploy_nfs_clients.sh`. Start it with `./start_demo.sh`.

**SSH connection refused from AWX**
- Confirm containers are running: `docker ps`
- Check SSH daemon: `docker exec nfs-client-1 service ssh status`
- Confirm Minikube is up: `minikube status`

**NFS mount fails inside container**
- Ping the PowerScale: `docker exec nfs-client-1 ping 192.168.243.50`
- Confirm NFS exports exist: run `configure_shares.yml` first
- Containers must use `privileged: true` (already set in docker-compose.yml)

**Workflow Step 2 did not run**
Step 2 only fires when Step 1 succeeds. Check the Step 1 job output in AWX for the root cause.

**fstab still has old entry**
The switchover playbooks use `state: absent` which removes the old entry automatically.
To clear manually: `docker exec nfs-client-1 sed -i '/powerscale/d' /etc/fstab`

=================================================
 DEPLOYMENT COMPLETE
=================================================

  Container         IP               SSH
  ─────────────── ──────────────── ──────────────────────────────
  nfs-client-1     192.168.49.10      ssh root@192.168.49.10  (pass: demo1234)
  nfs-client-2     192.168.49.11      ssh root@192.168.49.11  (pass: demo1234)

  NFS Server (PowerScale): 192.168.243.50
  Mount Point on Clients : /mnt/powerscale_data

  AWX URL    : http://192.168.49.2:31056

  To stop containers:  docker compose -f nfs-clients/docker-compose.yml down
  To view logs:        docker logs nfs-client-1
=================================================


