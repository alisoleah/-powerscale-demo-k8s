# PowerScale Automated Failover Demo — Customer Environment Requirements

This document describes everything needed to deploy the PowerScale automated failover demo in a customer environment. It covers the four components: **Dell PowerScale**, **AWX / Ansible Automation Platform**, **GitLab**, and **Linux NFS client machines**.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Customer Network                        │
│                                                             │
│   ┌──────────────┐      ┌──────────────┐                   │
│   │    GitLab    │◄────►│     AWX      │                   │
│   │  (playbooks) │      │ (automation) │                   │
│   └──────────────┘      └──────┬───────┘                   │
│                                │  PAPI :8080 / SSH :22      │
│                         ┌──────▼───────────────────────┐   │
│                         │    Dell PowerScale Cluster    │   │
│                         │  Site A: /ifs/data/source     │   │
│                         │  Site B: /ifs/data/target     │   │
│                         │  SyncIQ: source → target      │   │
│                         └──────────────────────────────┘   │
│                                │  NFS :2049                 │
│                  ┌─────────────┴─────────────┐             │
│                  │                           │             │
│           ┌──────▼──────┐           ┌────────▼──────┐     │
│           │ Linux Client│           │ Linux Client  │     │
│           │   (Site A)  │           │   (Site B)    │     │
│           └─────────────┘           └───────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

## 1. Dell PowerScale Requirements

### 1.1 Software Licenses (all required)

| License | Purpose |
|---|---|
| **SyncIQ** | Replication between Site A and Site B; enables failover/failback |
| **SmartQuotas** | Directory-level capacity limits shown during demo |
| **NFS** | Linux client access (included in base OneFS) |
| **SMB** | Windows client access (included in base OneFS, optional) |

### 1.2 OneFS Version

- **Minimum:** OneFS 9.0
- **Recommended:** OneFS 9.4 or later
- **PAPI version 3** must be available (standard on 9.x)

### 1.3 Cluster Configuration

- At least **two directories** must be configurable under `/ifs/`:
  - `/ifs/data/source` — Site A (primary)
  - `/ifs/data/target` — Site B (standby / SyncIQ target)
- **SyncIQ** can be configured as a **loopback policy** (source and target on the same cluster, different paths) — no second cluster needed for the demo
- **NFS service** must be running and accessible from the AWX host and Linux client machines

### 1.4 API Access

- The **Platform API (PAPI)** must be reachable from the AWX host on **TCP port 8080**
- An admin account (e.g. `root`) must be available for API authentication
- PAPI uses **session-based authentication** — basic auth is not supported by AWX's `uri` module; the Dell PowerScale Ansible collection handles this automatically

### 1.5 SSH Access (optional but recommended)

- SSH access on **TCP port 22** to the OneFS management IP is recommended for troubleshooting
- Not required for normal demo operation

### 1.6 NFS Export Settings

The following must be configurable on NFS exports (the automation sets these automatically):

| Setting | Site A (source) | Site B (target) |
|---|---|---|
| `read_only` | `false` (normal) / `true` (after failover) | `true` (normal) / `false` (after failover) |
| `root_clients` | Client subnet CIDR | Client subnet CIDR |
| Directory permissions | `0777` | `0777` (set by SyncIQ sync from source) |

---

## 2. AWX / Ansible Automation Platform Requirements

### 2.1 Platform Options

| Option | Notes |
|---|---|
| **AWX Community** (free) | Kubernetes-based deployment. Suitable for demos and labs. |
| **Red Hat AAP 2.x** (licensed) | Production-grade. Supported by Red Hat. Recommended for customer production use. |

### 2.2 Minimum Server Specs (for AWX Community on Kubernetes)

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB |
| Disk | 40 GB | 80 GB |
| OS | RHEL 8/9, Ubuntu 22.04 | RHEL 9 |

### 2.3 Required Software on the AWX Host

| Software | Version | Notes |
|---|---|---|
| **Docker** or **Podman** | Latest stable | For AWX Operator / container runtime |
| **Kubernetes** (k3s, minikube, or full cluster) | 1.24+ | AWX runs on Kubernetes |
| **AWX Operator** | Latest | Deploys AWX into Kubernetes |
| **kubectl** | Matching cluster version | For managing AWX pods |
| **Python** | 3.9+ | For Ansible and the isilon-sdk package |
| **Ansible** | 2.14+ | For running `configure_awx.yml` bootstrap |

### 2.4 Required Ansible Collections (installed on AWX host for bootstrap)

```bash
ansible-galaxy collection install awx.awx
ansible-galaxy collection install dellemc.powerscale
```

### 2.5 Required Python Package (inside AWX Execution Environment)

```
isilon-sdk
```

The playbooks install this automatically at runtime via `ansible.builtin.pip`. No manual EE customization needed.

### 2.6 AWX Objects Created by Bootstrap

The `awx_config/configure_awx.yml` playbook automatically creates all of the following — **no manual AWX configuration required**:

| Type | Name |
|---|---|
| Credential | `PowerScale_API_Creds` (API user + password) |
| Credential | `NFS_Client_SSH_Creds` (SSH to Linux clients) |
| Inventory | `PowerScale Demo Inventory` (PowerScale cluster IP) |
| Inventory | `NFS Clients Inventory` (Linux client IPs) |
| Project | `PowerScale Failover Playbooks` (linked to GitLab repo) |
| Job Template | `SETUP: PowerScale Loopback Demo` |
| Job Template | `SETUP: PowerScale Shares and Quotas` |
| Job Template | `EXECUTE: Site A to Site B NFS Failover` |
| Job Template | `EXECUTE: Site B to Site A Failback (Restore)` |
| Job Template | `CLIENT: Mount NFS Shares (Initial Setup)` |
| Job Template | `CLIENT: Switch NFS Mount to Site B (Post-Failover)` |
| Job Template | `CLIENT: Switch NFS Mount to Site A (Post-Failback)` |
| Job Template | `DANGER: Reset Lab (Nuke & Pave)` |
| Workflow | `WORKFLOW: Full Failover (PowerScale + Clients)` |
| Workflow | `WORKFLOW: Full Failback (PowerScale + Clients)` |

### 2.7 AWX Network Requirements

| Destination | Port | Protocol | Purpose |
|---|---|---|---|
| PowerScale management IP | 8080 | TCP | PAPI (PowerScale REST API) |
| PowerScale management IP | 22 | TCP | SSH (optional, troubleshooting) |
| GitLab server | 443 | TCP HTTPS | Pull playbooks (or port 22 for SSH) |
| Linux client machines | 22 | TCP | SSH to manage NFS mounts |

---

## 3. GitLab Requirements

### 3.1 Platform Options

| Option | Notes |
|---|---|
| **GitLab.com** (cloud) | Simplest. No infrastructure needed. Free tier is sufficient. |
| **GitLab CE** (self-hosted) | For air-gapped or private environments |
| **GitHub** (alternative) | Works identically — AWX supports any Git provider |

### 3.2 Repository Setup

1. Create a new project/repository (e.g. `powerscale-failover-demo`)
2. Copy all files from this repo into it (or fork directly)
3. Make the repository **accessible from the AWX host**:
   - Public repo: no authentication needed
   - Private repo: requires a deploy token or personal access token

### 3.3 Access Token (for private repos)

1. GitLab → Repository → **Settings → Repository → Deploy tokens**
2. Create a token with `read_repository` scope
3. Provide the username and token to the AWX bootstrap config

### 3.4 Files That Must Be in the Repository Root

```
playbooks/
├── setup_demo.yml
├── configure_shares.yml
├── failover.yml
├── failback.yml
├── reset_lab.yml
├── client_mount_nfs.yml
├── client_switchover_nfs.yml
├── client_switchback_nfs.yml
└── client_unmount_nfs.yml
collections/
└── requirements.yml        ← tells AWX to install dellemc.powerscale
awx_config/
└── configure_awx.yml
inventory/
└── nfs_clients.ini
```

### 3.5 AWX Project Sync

Every time playbooks are updated in GitLab:
1. AWX → **Projects** → "PowerScale Failover Playbooks" → click **sync** icon
2. Wait for status to show **Successful** before re-running any job

Alternatively, configure a **GitLab webhook** to auto-trigger AWX project sync on push:
- AWX → Projects → (project) → **Webhooks** tab → copy the webhook URL and secret
- GitLab → Repository → **Settings → Webhooks** → paste URL + secret, select "Push events"

---

## 4. Linux NFS Client Machine Requirements

These are the machines that demonstrate live NFS access and the seamless switchover during failover.

### 4.1 Minimum Specs per Client

| Resource | Minimum |
|---|---|
| CPU | 1 vCPU |
| RAM | 512 MB |
| Disk | 5 GB |
| OS | Any Linux with systemd (RHEL 8/9, Ubuntu 20.04+, Debian 11+) |

### 4.2 Required Packages

**RHEL / CentOS / Rocky:**
```bash
dnf install -y nfs-utils
```

**Ubuntu / Debian:**
```bash
apt-get install -y nfs-common
```

### 4.3 NFS Client Configuration

| Setting | Value |
|---|---|
| NFS version | NFSv4 (v4.2 preferred) |
| Mount options | `rw,soft,timeo=10,retrans=2,nfsvers=4,sec=sys` |
| Mount point | `/mnt/powerscale_data` (created by playbook) |
| Authentication | `sec=sys` (AUTH_SYS — numeric UID, no Kerberos needed) |

### 4.4 SSH Access for AWX

- AWX must be able to reach each client on **TCP port 22**
- An account with **sudo or root access** must be available (playbooks run as root)
- Credentials are stored in AWX as `NFS_Client_SSH_Creds`

### 4.5 NFS Client Network Requirements

| Destination | Port | Protocol | Purpose |
|---|---|---|---|
| PowerScale NFS IP | 2049 | TCP + UDP | NFS data |
| PowerScale NFS IP | 111 | TCP + UDP | rpcbind / portmapper |

---

## 5. Network Summary

All required connectivity in one view:

```
AWX Host  ──── TCP 8080 ──────────────► PowerScale (PAPI)
AWX Host  ──── TCP 22   ──────────────► PowerScale (SSH, optional)
AWX Host  ──── TCP 443  ──────────────► GitLab (HTTPS pull)
AWX Host  ──── TCP 22   ──────────────► Linux Client 1
AWX Host  ──── TCP 22   ──────────────► Linux Client 2

Linux Client 1 ── TCP+UDP 2049, 111 ──► PowerScale (NFS)
Linux Client 2 ── TCP+UDP 2049, 111 ──► PowerScale (NFS)
```

No inbound connectivity to the AWX host is required (AWX initiates all connections).

---

## 6. Preparing the Environment — Step by Step

### Step 1 — PowerScale

1. Verify SyncIQ and SmartQuotas licenses are active:
   ```
   isi license list
   ```
2. Confirm NFS service is running:
   ```
   isi services nfs status
   ```
3. Confirm PAPI is accessible from the AWX host:
   ```bash
   curl -k https://<powerscale-ip>:8080/platform/3/cluster/identity
   # Should return JSON (will prompt for auth — that confirms the port is open)
   ```

### Step 2 — GitLab

1. Create the repository and push all playbook files
2. If the repo is private, create a deploy token with `read_repository` scope
3. Note the repository URL (HTTPS or SSH)

### Step 3 — AWX

1. Deploy AWX (Community or AAP) on a Kubernetes cluster
2. Install the required collection on the host running the bootstrap:
   ```bash
   ansible-galaxy collection install awx.awx
   ```
3. Edit `awx_config/configure_awx.yml` — update these two values:
   ```yaml
   isilon_password: "<your-powerscale-admin-password>"
   github_repo: "https://gitlab.com/<your-org>/<your-repo>.git"
   ```
   If using a private GitLab repo, also add:
   ```yaml
   scm_credential: "GitLab_Token"   # after creating the credential manually in AWX
   ```
4. Run the bootstrap:
   ```bash
   ansible-playbook awx_config/configure_awx.yml
   ```
   This creates all inventories, credentials, job templates, and workflows automatically.

### Step 4 — Linux Clients

1. Install `nfs-utils` / `nfs-common` on each client machine
2. Ensure SSH is running and root (or a sudo user) is accessible
3. Add client IPs to the AWX inventory (`NFS Clients Inventory`) — the bootstrap does this for IPs defined in `configure_awx.yml`
4. In AWX, run **"CLIENT: Mount NFS Shares (Initial Setup)"** to perform the initial mount on all clients

### Step 5 — Run Setup Playbooks in AWX

Run these in order, each must show **Successful** before the next:

| Order | Template Name | What it does |
|---|---|---|
| 1 | `SETUP: PowerScale Loopback Demo` | Creates directories, SyncIQ policy, runs baseline sync |
| 2 | `SETUP: PowerScale Shares and Quotas` | Creates NFS exports, sets permissions, applies quotas |
| 3 | `CLIENT: Mount NFS Shares (Initial Setup)` | Mounts Site A on all Linux clients |

After these three complete, the environment is ready and the failover/failback demo can be run.

---

## 7. Customization Checklist

Before running in a customer environment, update these values:

| File | Variable | Change to |
|---|---|---|
| `awx_config/configure_awx.yml` | `isilon_password` | Customer's PowerScale admin password |
| `awx_config/configure_awx.yml` | `github_repo` | Customer's GitLab repository URL |
| `awx_config/configure_awx.yml` | `nfs_client_hosts` | Customer's Linux client IPs and hostnames |
| `awx_config/configure_awx.yml` | `nfs_client_password` | Customer's Linux client SSH password |
| `playbooks/failover.yml` (task 5b) | `root_clients` CIDR | Customer's client subnet |
| `playbooks/failback.yml` (task 3b/4b) | `root_clients` CIDR | Customer's client subnet |
| `playbooks/configure_shares.yml` (tasks 3/4) | `root_clients` CIDR | Customer's client subnet |
| `awx_config/configure_awx.yml` | Host `192.168.243.50` | Customer's PowerScale management IP |
