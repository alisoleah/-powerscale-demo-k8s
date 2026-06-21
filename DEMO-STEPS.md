# PowerScale Failover & Failback Demo — Step-by-Step

## Environment at a Glance

| Component | Detail |
|---|---|
| PowerScale (simulator) | `192.168.243.50` |
| Site A export | `/ifs/data/source` |
| Site B export | `/ifs/data/target` |
| AWX | Minikube NodePort (run `./start_demo.sh` to get URL) |
| NFS client 1 | `nfs-client-1` · IP `192.168.49.10` |
| NFS client 2 | `nfs-client-2` · IP `192.168.49.11` |
| Mount point on clients | `/mnt/powerscale_data` |

---

## Phase 0 — Start the Environment

> Do this every time you open a new terminal / restart WSL2.

### 0.1 Start WSL2 + Minikube + AWX

Open a terminal and run:

```bash
cd ~/powerscale-demo-k8s;
./start_demo.sh
```

This will:
- Load NFS kernel modules (`nfs`, `nfsv3`)
- Start the Minikube cluster
- Print the AWX admin password
- Print the AWX URL and hold the tunnel open

**Leave this terminal open for the entire demo.**

### 0.2 Note the AWX URL and password

The script prints something like:

```
Password: xxxxxxxxxxx

http://192.168.49.2:31234
```

Open that URL in a browser. Login: `admin` / (password above).

### 0.3 Deploy NFS client containers (open a second terminal)

```bash
cd ~/powerscale-demo-k8s
./deploy_nfs_clients.sh
```

This builds the client image, starts both containers, waits for SSH, then auto-triggers **"CLIENT: Mount NFS Shares (Initial Setup)"** in AWX.

Watch AWX → Jobs for the mount job to complete.

---

## Phase 1 — Verify Initial State (Both Clients on Site A)

Run these commands to confirm clients are healthy and writing to Site A before starting the demo:

```bash
# Confirm both containers are running
docker ps --filter name=nfs-client

# Confirm both are mounted to Site A (/ifs/data/source)
docker exec nfs-client-1 findmnt -n -o SOURCE /mnt/powerscale_data
docker exec nfs-client-2 findmnt -n -o SOURCE /mnt/powerscale_data
# Expected: 192.168.243.50:/ifs/data/source

# List files — both files should appear from both clients (shared NFS)
docker exec nfs-client-1 ls -la /mnt/powerscale_data/
```
# Confirm read-write access
docker exec nfs-client-1 touch /mnt/powerscale_data/client1-precheck.txt
docker exec nfs-client-2 touch /mnt/powerscale_data/client2-precheck.txt

# List files — both files should appear from both clients (shared NFS)
docker exec nfs-client-1 ls -la /mnt/powerscale_data/
```

**Expected output:** `drwxrwxrwx` directory, both `.txt` files visible, no errors.

---

## Phase 2 — FAILOVER (Site A → Site B)

### 2.1 Trigger one-click failover workflow

AWX UI → **Templates** → **"WORKFLOW: Full Failover (PowerScale + Clients)"** → **Launch**

This workflow runs two jobs in sequence:
1. `EXECUTE: Site A to Site B NFS Failover` — SyncIQ `allow_write`, locks Site A read-only, unlocks Site B
2. `CLIENT: Switch NFS Mount to Site B (Post-Failover)` — force-unmounts Site A, mounts Site B, updates `/etc/fstab`

Wait for both jobs to show **green (Successful)** in AWX Jobs view.

### 2.2 Verify failover — clients now on Site B

```bash
# Confirm clients switched to Site B (/ifs/data/target)
docker exec nfs-client-1 findmnt -n -o SOURCE /mnt/powerscale_data;
docker exec nfs-client-2 findmnt -n -o SOURCE /mnt/powerscale_data
# Expected: 192.168.243.50:/ifs/data/target

# Confirm Site B is writable
docker exec nfs-client-1 touch /mnt/powerscale_data/post-failover-client1.txt;
docker exec nfs-client-2 touch /mnt/powerscale_data/post-failover-client2.txt;
docker exec nfs-client-1 ls -la /mnt/powerscale_data/

# Confirm Site A is now READ-ONLY (fenced)
docker exec nfs-client-1 mkdir -p /tmp/test-site-a
docker exec nfs-client-1 mount -t nfs 192.168.243.50:/ifs/data/source /tmp/test-site-a
docker exec nfs-client-1 touch /tmp/test-site-a/site-a-is-fenced.txt
# Expected: mount will succeed but writes will fail with EROFS
```

**Demo talking point:** Site A data is protected (read-only/fenced). Clients seamlessly writing to Site B with no application restart.

---

## Phase 3 — FAILBACK (Site B → Site A)

### 3.1 Trigger one-click failback workflow

AWX UI → **Templates** → **"WORKFLOW: Full Failback (PowerScale + Clients)"** → **Launch**

This workflow runs two jobs in sequence:
1. `EXECUTE: Site B to Site A Failback (Restore)` — SyncIQ `allow_write_revert`, releases domain lock, restores Site A read-write, locks Site B
2. `CLIENT: Switch NFS Mount to Site A (Post-Failback)` — force-unmounts Site B, mounts Site A, updates `/etc/fstab`

Wait for both jobs to show **green (Successful)** in AWX Jobs view.

### 3.2 Verify failback — clients restored to Site A

```bash
# Confirm clients are back on Site A (/ifs/data/source)
docker exec nfs-client-1 findmnt -n -o SOURCE /mnt/powerscale_data
docker exec nfs-client-2 findmnt -n -o SOURCE /mnt/powerscale_data
# Expected: 192.168.243.50:/ifs/data/source

# Confirm Site A is writable again
docker exec nfs-client-1 touch /mnt/powerscale_data/post-failback-client1.txt
docker exec nfs-client-2 touch /mnt/powerscale_data/post-failback-client2.txt
docker exec nfs-client-1 ls -la /mnt/powerscale_data/

# Confirm fstab is updated (persistent across reboots)
docker exec nfs-client-1 grep powerscale /etc/fstab
docker exec nfs-client-2 grep powerscale /etc/fstab
# Expected: entry pointing to /ifs/data/source
```

**Demo talking point:** Full round-trip complete. Primary site restored, clients back to normal operations — no manual intervention on client machines.

---

## Troubleshooting

### "Read-only file system" (EROFS) on write

The NFS export is locked. Check which export is mounted:

```bash
docker exec nfs-client-1 findmnt -n -o SOURCE /mnt/powerscale_data
```

- If showing `/ifs/data/source` and EROFS → failover was run but not failback. Run the failback workflow.
- If showing `/ifs/data/target` and EROFS → failback ran (Site B locked) but clients weren't switched. Run **"CLIENT: Switch NFS Mount to Site A (Post-Failback)"**.

### "Permission denied" on write

Directory permissions need resetting. In AWX:
1. Projects → **"PowerScale Failover Playbooks"** → sync icon (wait for Successful)
2. Templates → **"SETUP: PowerScale Shares and Quotas"** → Launch

### Mount not present / containers not running

```bash
docker ps --filter name=nfs-client
# If containers are stopped:
docker compose -f nfs-clients/docker-compose.yml up -d
# Then in AWX: "CLIENT: Mount NFS Shares (Initial Setup)" → Launch
```

### AWX URL not reachable

The `./start_demo.sh` tunnel must be running in a separate terminal. Get the URL again:

```bash
minikube service awx-demo-service -n awx --url
```

### Full lab reset (nuclear option)

AWX → Templates → **"DANGER: Reset Lab (Nuke & Pave)"** → Launch

Then re-run setup from scratch:
1. **"SETUP: PowerScale Loopback Demo"** (creates directories + SyncIQ policy)
2. **"SETUP: PowerScale Shares and Quotas"** (NFS exports, quotas, permissions)
3. `./deploy_nfs_clients.sh` (re-deploys containers and mounts)
