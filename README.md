# PowerScale SyncIQ Failover Automation (AWX Demo Lab)

## 🏗️ Architecture Overview
This project provides a portable, self-contained Infrastructure as Code (IaC) demonstration environment. It runs a production-grade Ansible AWX cluster locally to orchestrate Dell PowerScale SyncIQ failover operations.

**The Tech Stack:**
* **Host OS:** Windows Subsystem for Linux (WSL2) - Ubuntu
* **Container Engine:** Docker
* **Orchestration:** Kubernetes (Minikube local cluster)
* **Execution Engine:** Ansible AWX (deployed via AWX Operator)
* **Target Environment:** Dell PowerScale (Isilon) OneFS clusters
* **Version Control:** GitHub

**Traffic Flow:**
> **Windows Browser** ➔ **WSL2 Port Forward** ➔ **Minikube** ➔ **AWX Web Pod** ➔ **AWX Task Pod** ➔ **Target PowerScale REST API**

---

## 🚀 Step-by-Step Setup Guide

### 1. System Prerequisites
Ensure your WSL Ubuntu environment has the following installed:
* Git
* Docker
* Minikube
* Kubectl
* Ansible (local engine for AWX configuration)

### 2. Deploy the AWX Kubernetes Cluster
Navigate to the root directory (`~/powerscale-demo-k8s`) and execute the deployment script. This script builds the local cluster and deploys the AWX Operator.

```bash
./deploy_lab.sh
```
> *Wait until all pods in the `awx` namespace report a `Running` status before proceeding.*

### 3. Initialize Version Control
AWX requires playbooks to be hosted in a source control repository.

Create a repository on GitHub.

Initialize and push your local code:

```bash
git init
git add .
git commit -m "Initial AWX configuration and PowerScale Failover payload"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USER/powerscale-demo-k8s.git
git push -u origin main
```

### 4. Configure AWX as Code
Run the local configuration playbook to automatically populate AWX via its API. This creates the Machine Credentials, Inventory, GitHub Project, and Job Template.

> **Note:** Update `awx_config/configure_awx.yml` with your active Minikube URL and Password before running.

```bash
ansible-playbook awx_config/configure_awx.yml
```

---

## 💻 Day-to-Day Operations
Because the environment runs inside a local Kubernetes cluster, it persists across reboots. However, the network tunnel to your Windows host must be re-opened if your terminal closes.

To start the lab and get your login details, run:

```bash
./start_demo.sh
```
> **Note:** Leave the terminal running `start_demo.sh` open in the background to maintain the network tunnel.

---

## 📋 Current Project State
What is Built & Working:

* ✅ **Infrastructure:** Minikube K8s cluster running AWX.
* ✅ **Startup Script:** Automated resume, password retrieval, and port forwarding.
* ✅ **Configuration as Code:** Playbook to dynamically build the AWX UI elements.
* ✅ **Failover Payload:** `playbooks/failover.yml` utilizes the `dellemc.powerscale.synciq_target_policy` module to execute an `allow_write` action on the target cluster.

---

## 🚧 What is Missing (Next Steps)
To make this a fully functional, end-to-end demonstration, the following items must be completed:

### 1. PowerScale Environment Connectivity
* **The Gap:** AWX currently points to a dummy target (`site-b.isilon.local`) with a dummy root password.
* **The Fix:** Deploy Dell PowerScale Virtual Nodes (Simulators) or connect to a physical lab. Update the IP addresses/DNS in the AWX Inventory and enter the actual root password in the AWX Credentials tab.

### 2. Execution Environment Requirements
* **The Gap:** When the AWX Task Pod attempts to run the failover playbook, it will fail because the container image doesn't have the Dell PowerScale Ansible modules installed by default.
* **The Fix:** Create a `collections/requirements.yml` file in this repository so AWX knows to automatically download the `dellemc.powerscale` collection before running the job.

### 3. The "Failback" Playbook
* **The Gap:** We can currently break the mirror and fail over to Site B, but we have no automation to resync the data and return operations to Site A.
* **The Fix:** Write `playbooks/failback.yml` to reverse the SyncIQ policy and execute the failback operation.