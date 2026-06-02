# Enterprise Disaster Recovery Pipeline: Dell PowerScale & Ansible AWX

## 📌 Overview
This project demonstrates a fully automated Infrastructure as Code (IaC) pipeline for Enterprise Disaster Recovery. Using Ansible AWX hosted on a local Kubernetes cluster, this pipeline provisions, configures, and executes a zero-touch failover for a Dell PowerScale (Isilon) storage environment.

**Architecture Stack:**
* **Automation Engine:** Ansible AWX (running on Minikube in Windows Subsystem for Linux - WSL)
* **Storage Array:** Dell PowerScale OneFS Simulator (hosted on VMware Workstation)
* **Version Control:** GitHub

---

## 🏗️ Phase 1: Storage Appliance Configuration

Deploying the Dell PowerScale Simulator requires specific hypervisor and operating system configurations to ensure API connectivity and service availability.

### 1. VMware Network Bridging
By default, VMware may isolate the Isilon VM. To allow the AWX container to communicate with the storage REST API:
1. Open VMware Workstation -> **VM Settings**.
2. Change **Network Adapter 1, 2, and 3** from their defaults to **NAT (Share the host's IP address)**.
3. Verify connectivity from the host/WSL terminal: `ping 192.168.243.50`
### 1. OneFS Initial Configuration Wizard
When you first boot the Dell PowerScale (Isilon) OVA in VMware, open the virtual console. The system will initialize its virtual drives and eventually drop you into the OneFS setup wizard. 

Follow these exact prompts to configure the single-node simulator:

1. **Configuration Option:** Choose `1` (Create a new cluster).
2. **EULA:** Type `yes` to accept.
3. **Passwords:** Enter your desired passwords for the `root` and `admin` accounts.
4. **Cluster Name:** Enter a hostname (e.g., `site-b-isilon`).
5. **Character Encoding:** Press Enter to accept the default (UTF-8).
6. **Internal Network (int-a / int-b):** The Isilon requires a backend network for node-to-node communication, even on a single node. 
   * Press Enter to accept the default `int-a` netmask (`255.255.255.0`).
   * Press Enter to accept the default IP range (e.g., `10.1.1.1` to `10.1.1.254`).
   * Press Enter to accept the default `int-b` settings.
7. **External Network (ext-1):** This is the front-end network your AWX container and clients will use to connect to the storage. **These settings must match your VMware NAT subnet.**
   * **Subnet Mask:** Type `255.255.255.0` (Assuming a /24 NAT network).
   * **Default Gateway:** Type your VMware NAT gateway (e.g., `192.168.243.2`).
   * **SmartConnect Zone Name:** Press Enter to skip (not needed for this demo).
   * **SmartConnect Service IP:** Press Enter to skip.
   * **DNS Servers:** Type your preferred DNS (e.g., `8.8.8.8`).
   * **IP Address Range:** Type `192.168.243.50` for the Low IP, and `192.168.243.50` for the High IP (Restricting it to exactly one IP for our single node).

Once finished, the cluster will save the configuration, restart its networking services, and drop you at the `login:` prompt.
### 2. Service & License Activation
The OneFS Simulator ships with core features disabled. Access the appliance via SSH (`ssh root@192.168.243.50`) and execute the following to arm the system:

```bash
# 1. Inject Evaluation Licenses for Replication and Quotas
isi license add --evaluation SYNCIQ
isi license add --evaluation SMARTQUOTAS

# 2. Force Enable the SyncIQ Replication Daemon
isi sync settings modify --service=on

# 3. Force Enable the NFS Daemon
isi services nfs enable

# Verify Services are active
isi services -a | grep -i -E "migr|nfs"