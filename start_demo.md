Two steps every time you start fresh. Open two terminals:

Terminal 1 — keep this open the whole session:


cd /home/galala/powerscale-demo-k8s
./start_demo.sh
This wakes up Minikube, prints your AWX password, and holds the port-forward tunnel open. Close this terminal = AWX goes offline.

Terminal 2 — check NFS client containers:


docker ps | grep nfs-client
The containers have restart: unless-stopped so they usually survive a Docker restart automatically. If they're not listed as Up:


docker compose -f /home/galala/powerscale-demo-k8s/nfs-clients/docker-compose.yml up -d
That's it. You do not need to re-run:

deploy_lab.sh — Minikube cluster and AWX persist on disk
configure_awx.yml — AWX keeps all your job templates and credentials
deploy_nfs_clients.sh — only needed if containers were deleted (not just stopped)
ansible-playbook for shares/setup — PowerScale config persists on the simulator VM
Quick reference card:

Situation	Command
Every session start	./start_demo.sh (keep terminal open)
Containers stopped	docker compose -f nfs-clients/docker-compose.yml up -d
Forgot AWX password	kubectl get secret awx-demo-admin-password -n awx -o jsonpath='{.data.password}' | base64 --decode
Check what's running	docker ps
Containers deleted	./deploy_nfs_clients.sh