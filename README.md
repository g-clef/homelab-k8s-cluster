# homelab-k8s-cluster

Ansible playbook for setting up a Kubernetes cluster in a home lab environment with Argo CD and Ray Operator.

## Architecture

- **Control Plane**: 1 VM on Synology NAS (192.168.1.50)
- **Worker Nodes**: 5 physical systems (192.168.1.51-192.168.1.55)
- **GPU Worker Nodes**: 1 NVIDIA GPU system (192.168.1.56)
- **Network**: 192.168.1.0/24 subnet
- **Container Runtime**: containerd
- **CNI Plugin**: Flannel
- **Load Balancer**: MetalLB for exposing services (192.168.1.200-220)
- **GitOps**: Argo CD with app-of-apps pattern
- **ML/AI**: Ray Operator for distributed computing, NVIDIA Device Plugin for GPU support
- **Object Storage**: MinIO for S3-compatible storage

## Prerequisites

### On Control Machine
- Ansible 2.9 or higher
- SSH access to all nodes
- Python 3.x

### On All Nodes
- Ubuntu 24.04 LTS (or other Debian-based distribution)
- SSH server running
- User with sudo privileges
- At least 2GB RAM
- At least 2 CPU cores

## Initial Setup

1. **Update inventory file** (`inventory/hosts.yml`):
   - Change `ansible_user` to match your actual SSH user on the nodes
   - Verify IP addresses match your setup

2. **Configure SSH access**:
   ```bash
   # Generate SSH key if you don't have one
   ssh-keygen -t rsa -b 4096

   # Copy SSH key to all nodes
   ssh-copy-id ansible@192.168.1.50   # Control plane
   ssh-copy-id ansible@192.168.1.51   # Worker 1
   ssh-copy-id ansible@192.168.1.52   # Worker 2
   ssh-copy-id ansible@192.168.1.53   # Worker 3
   ssh-copy-id ansible@192.168.1.54   # Worker 4
   ssh-copy-id ansible@192.168.1.55   # Worker 5
   ssh-copy-id ansible@192.168.1.56   # GPU Worker
   ```

3. **Configure Argo CD app-of-apps** (optional):
   - Edit `group_vars/all.yml`
   - Uncomment and set the following variables:
     - `argocd_repo_url`: Your GitHub repository URL
     - `argocd_repo_branch`: Branch name (default: main)
     - `argocd_repo_path`: Path to apps directory (default: apps)

## Usage

### Deploy the entire cluster

```bash
ansible-playbook site.yml
```

### Deploy specific components

You can use tags to run specific parts of the playbook:

```bash
# Deploy SSH keys
ansible-playbook site.yml --tags ssh-keys

# Setup prerequisites on all nodes (containerd, kubelet, etc.)
ansible-playbook site.yml --tags prerequisites

# Setup GPU prerequisites (NVIDIA drivers, container toolkit)
ansible-playbook site.yml --tags gpu-prerequisites

# Initialize control plane
ansible-playbook site.yml --tags control-plane

# Join worker nodes to cluster
ansible-playbook site.yml --tags workers

# Label GPU nodes
ansible-playbook site.yml --tags gpu-labeling

# Install Argo CD
ansible-playbook site.yml --tags argocd

# Install MetalLB load balancer
ansible-playbook site.yml --tags metallb

# Install Metrics Server (for kubectl top commands)
ansible-playbook site.yml --tags metrics-server

# Install Ray Operator
ansible-playbook site.yml --tags ray

# Install NVIDIA Device Plugin
ansible-playbook site.yml --tags gpu-plugin

# Install MinIO
ansible-playbook site.yml --tags minio

# Setup USB storage (both worker node config and Kubernetes PVs)
ansible-playbook site.yml --tags usb-storage

# Fetch kubeconfig to local machine
ansible-playbook site.yml --tags fetch-kubeconfig
```

You can also combine multiple tags:

```bash
# Deploy only Argo CD and MetalLB
ansible-playbook site.yml --tags argocd,metallb

# Setup full cluster infrastructure (skip applications)
ansible-playbook site.yml --tags prerequisites,control-plane,workers
```

You can also use `--limit` to target specific hosts:

```bash
# Only setup control plane node
ansible-playbook site.yml --limit control_plane

# Only setup worker nodes
ansible-playbook site.yml --limit workers

# Only setup GPU worker nodes
ansible-playbook site.yml --limit gpu_workers
```

### Test connectivity

```bash
ansible all -m ping
```

## Post-Installation

### Access Kubernetes Cluster

#### Option 1: From Control Plane Node

SSH to the control plane and use kubectl:
```bash
ssh ansible@192.168.1.50
kubectl get nodes
kubectl get pods -A
```

#### Option 2: From Your Local Machine (Recommended)

Fetch the kubeconfig to your local machine so you can use kubectl without SSH:

```bash
# Fetch kubeconfig from the cluster
ansible-playbook site.yml --tags fetch-kubeconfig

# Verify kubectl works locally
kubectl get nodes
kubectl get pods -A
```

The kubeconfig will be saved to `~/.kube/config` on your local machine and configured to connect to the cluster at `https://192.168.1.50:6443`.

**Note**: Ensure your local machine can reach the control plane IP (192.168.1.50) on port 6443.

### Access Argo CD

1. Get the NodePort:
   ```bash
   kubectl get svc argocd-server -n argocd
   ```

2. Get the admin password (shown during installation or run):
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

3. Access the UI:
   - URL: `https://192.168.1.50:<nodeport>`
   - Username: `admin`
   - Password: (from step 2)

### Verify Ray Operator

```bash
kubectl get pods -n kuberay-operator
```

### Verify MetalLB

```bash
# Check MetalLB pods are running
kubectl get pods -n metallb-system

# Check IP address pool configuration
kubectl get ipaddresspool -n metallb-system

# Check L2 advertisement configuration
kubectl get l2advertisement -n metallb-system
```

### Verify Metrics Server

```bash
# Check metrics server pod is running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# View node resource usage
kubectl top nodes

# View pod resource usage across all namespaces
kubectl top pods -A

# View pod resource usage in a specific namespace
kubectl top pods -n kube-system
```

The Metrics Server enables resource monitoring and is used by:
- Horizontal Pod Autoscaler (HPA)
- Vertical Pod Autoscaler (VPA)
- `kubectl top` commands for viewing resource usage

### Using LoadBalancer Services

With MetalLB installed, you can expose services to your network using LoadBalancer type:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: my-app
```

MetalLB will automatically assign an external IP from the configured range (192.168.1.200-220).

```bash
# Check service external IP
kubectl get svc my-service

# Example output:
# NAME         TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
# my-service   LoadBalancer   10.96.123.45    192.168.1.200    80:30123/TCP   1m
```

The service will be accessible at `http://192.168.1.200:80` from anywhere on your network.

#### Example: Expose Ray Dashboard

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ray-dashboard
  namespace: default
spec:
  type: LoadBalancer
  ports:
    - name: dashboard
      port: 8265
      targetPort: 8265
  selector:
    ray.io/node-type: head
```

After applying, access the Ray dashboard at `http://<EXTERNAL-IP>:8265`.

### Verify GPU Support

```bash
# Check NVIDIA device plugin is running
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds

# Check GPU resources are available on GPU nodes
kubectl describe node k8s-gpu-worker-01 | grep -A 5 "Allocatable"

# Should show:
#   nvidia.com/gpu: 1 (or the number of GPUs in the node)
```

### Access MinIO

1. Get the MinIO services:
   ```bash
   kubectl get svc -n minio
   ```

2. Access MinIO Console (web UI):
   ```bash
   # Port-forward the console to your local machine
   kubectl port-forward svc/minio-console -n minio 9001:9001
   ```
   Then access `http://localhost:9001`

3. Default credentials (CHANGE IN PRODUCTION):
   - Access Key: `minioadmin`
   - Secret Key: `minioadmin`

4. S3 API endpoint (internal to cluster):
   ```
   http://minio.minio.svc.cluster.local
   ```

5. Verify MinIO tenant:
   ```bash
   kubectl get tenant -n minio
   kubectl get pods -n minio
   ```

### Configure Synology NAS for MinIO Storage Backend

MinIO in the cluster uses NFS storage from the Synology NAS as its backend. This means MinIO serves as an S3-compatible interface to data stored on the NAS.

#### Step 1: Configure NFS on Synology NAS

1. **Enable NFS Service**:
   - Open Synology DSM
   - Go to **Control Panel** > **File Services**
   - Enable **NFS** service
   - Configure **NFSv4** support

2. **Create Shared Folder for MinIO**:
   - Go to **Control Panel** > **Shared Folder**
   - Click **Create** and name it `minio`
   - Set appropriate size and location (default path will be `/volume1/minio`)

3. **Configure NFS Permissions**:
   - Select the `minio` shared folder
   - Click **Edit** > **NFS Permissions**
   - Click **Create** and configure:
     - **Server or IP address**: `192.168.1.0/24` (your cluster network)
     - **Privilege**: Read/Write
     - **Squash**: Map all users to admin
     - **Security**: sys
     - **Enable asynchronous**: Unchecked (for data integrity)
     - **Allow connections from non-privileged ports**: Checked
     - **Allow users to access mounted subfolders**: Checked

4. **Create Subdirectories for MinIO Data**:
   ```bash
   # SSH into Synology NAS
   ssh admin@192.168.1.50
   
   # Create data directories for MinIO volumes
   sudo mkdir -p /volume1/minio/data-0-0
   sudo chmod 777 /volume1/minio/data-0-0
   ```
   
   Note: The directory pattern is `data-{server}-{volume}`. For the default configuration (1 server, 1 volume), you only need `data-0-0`.

#### Step 2: Update Ansible Configuration

Update `group_vars/all.yml` to match your NFS setup:

```yaml
# Synology NAS NFS Configuration for MinIO
synology_nfs_server: "192.168.1.50"
synology_nfs_path: "/volume1/minio"
```

#### Step 3: Verify NFS Connectivity

Before deploying MinIO, test NFS connectivity from a cluster node:

```bash
# SSH into a cluster node
ssh ansible@192.168.1.51

# Test NFS mount
sudo mkdir -p /mnt/test
sudo mount -t nfs -o nfsvers=4.1 192.168.1.50:/volume1/minio /mnt/test

# Verify read/write access
sudo touch /mnt/test/testfile
ls -l /mnt/test/testfile
sudo rm /mnt/test/testfile

# Unmount
sudo umount /mnt/test
```

#### Step 4: Deploy MinIO

Once NFS is configured, deploy MinIO:

```bash
ansible-playbook site.yml
```

MinIO will automatically create PersistentVolumes using the NFS share.


2. Access MinIO from Synology NAS:
   - S3 Endpoint: `http://192.168.1.50:30900` (or any worker node IP)
   - Access Key: `minioadmin` (or your configured value)
   - Secret Key: `minioadmin` (or your configured value)


## USB Storage Setup

The cluster supports local USB storage on worker nodes for persistent data storage. USB drives can be configured on non-GPU worker nodes and exposed as Kubernetes PersistentVolumes.

### Prerequisites

1. **Connect USB drives** to the worker nodes where you want storage
2. **Identify the device path** on each node:
   ```bash
   # SSH to the worker node
   ssh ansible@192.168.1.51

   # List all block devices
   lsblk

   # Or list USB devices specifically
   sudo fdisk -l | grep -i usb
   ```

   Typical device paths: `/dev/sdb1`, `/dev/sdc1`, etc.

### Configuration

1. **Get the UUID for each USB drive** (RECOMMENDED for reliability):

   SSH to each worker node and find the UUID:
   ```bash
   ssh ansible@192.168.1.51

   # Find your USB device (look for your drive size)
   lsblk

   # Get the UUID for the device
   sudo blkid /dev/sdb1
   ```

   Example output:
   ```
   /dev/sdb1: UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890" TYPE="ext4"
   ```

2. **Update inventory file** (`inventory/hosts.yml`) for each node with USB storage:

   **Option A: Using UUID (RECOMMENDED - survives reboots/device order changes):**
   ```yaml
   k8s-worker-01:
     ansible_host: 192.168.1.51
     ansible_user: ansible
     usb_device_uuid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"  # From blkid
     usb_storage_capacity: 100Gi       # Total capacity (adjust to your drive size)
   ```

   **Option B: Using device path (simpler but may change between reboots):**
   ```yaml
   k8s-worker-01:
     ansible_host: 192.168.1.51
     ansible_user: ansible
     usb_device_path: /dev/sdb1        # Device path
     usb_storage_capacity: 100Gi       # Total capacity
   ```

3. **Optional: Format USB drives** (WARNING: destroys data!)

   Edit `group_vars/all/vars.yml`:
   ```yaml
   usb_format_drive: true  # Only set to true if you want to format the drives
   ```

3. **Deploy USB storage**:
   ```bash
   ansible-playbook site.yml
   ```

   Or deploy only USB storage configuration:
   ```bash
   ansible-playbook site.yml --tags usb-storage
   ```

### Using USB Storage in Pods

Once configured, USB storage is available via the `local-usb-storage` StorageClass. Pods can request storage using PersistentVolumeClaims (PVCs).

#### Example: Pod with USB Storage

**Step 1: Create a PersistentVolumeClaim**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-usb-storage
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-usb-storage
  resources:
    requests:
      storage: 50Gi  # Must be <= the PV capacity
```

**Step 2: Use the PVC in a Pod**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: default
spec:
  containers:
    - name: app
      image: nginx:latest
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: my-usb-storage
```

**Step 3: Deploy**

```bash
kubectl apply -f pvc.yaml
kubectl apply -f pod.yaml
```

#### Example: StatefulSet with USB Storage

StatefulSets can automatically create PVCs from a template:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database
  namespace: default
spec:
  serviceName: database
  replicas: 3
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
        - name: postgres
          image: postgres:14
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-usb-storage
        resources:
          requests:
            storage: 30Gi
```

This creates one PVC per replica, automatically binding to available USB PersistentVolumes.

#### Example: Ray Cluster with USB Storage

For Ray workloads that need local storage:

```yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: ray-cluster
spec:
  headGroupSpec:
    template:
      spec:
        containers:
          - name: ray-head
            image: rayproject/ray:latest
            volumeMounts:
              - name: data
                mountPath: /data
        volumes:
          - name: data
            persistentVolumeClaim:
              claimName: ray-storage
  workerGroupSpecs:
    - replicas: 2
      template:
        spec:
          containers:
            - name: ray-worker
              image: rayproject/ray:latest
              volumeMounts:
                - name: data
                  mountPath: /data
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: ray-worker-storage
```

### Verify USB Storage

```bash
# List available PersistentVolumes
kubectl get pv -l storage-tier=usb

# Check PersistentVolume details
kubectl describe pv <pv-name>

# List PersistentVolumeClaims
kubectl get pvc -A

# Check which node a PVC is bound to
kubectl get pv <pv-name> -o jsonpath='{.spec.nodeAffinity}'
```

### Important Notes

- **Node Affinity**: Pods using USB storage are automatically scheduled to the node where the storage is located
- **ReadWriteOnce**: USB local storage only supports single-pod access (ReadWriteOnce mode)
- **No Replication**: Data is not replicated. If the node fails, data is inaccessible until the node recovers
- **Capacity**: Each PV represents one USB drive. Once claimed, the entire drive capacity is reserved for that PVC
- **Reclaim Policy**: PVs use `Retain` policy. If you delete a PVC, the PV remains and must be manually cleaned and recreated

### Troubleshooting

**PVC stuck in Pending:**
```bash
# Check events
kubectl describe pvc <pvc-name>

# Common causes:
# 1. No available PV with sufficient capacity
# 2. All PVs already bound to other PVCs
# 3. Node affinity constraints cannot be satisfied
```

**Check USB mount on worker node:**
```bash
ssh ansible@192.168.1.51
df -h | grep usb-storage
ls -la /mnt/usb-storage/k8s-local-storage
```

**Manually release a PV:**
```bash
# Delete the PVC first
kubectl delete pvc <pvc-name>

# Delete the PV
kubectl delete pv <pv-name>

# Clean the directory on the node
ssh ansible@192.168.1.51
sudo rm -rf /mnt/usb-storage/k8s-local-storage/*

# Re-run Ansible to recreate the PV
ansible-playbook site.yml --tags usb-storage
```

## Storage Options Summary

Your cluster has three storage options available:

| StorageClass | Type | Access | Use Case | Default |
|--------------|------|--------|----------|---------|
| `local-usb-storage` | Local USB drives | Single node (ReadWriteOnce) | High-performance local storage, node-specific data | No |
| `minio-nfs` | NFS (Synology NAS) | Multi-node (ReadWriteMany capable) | Shared storage across nodes, S3-backed | No |
| *(none)* | Specify explicitly | - | For static PV binding | - |

### Choosing a StorageClass

**Use `local-usb-storage` for:**
- Database storage (PostgreSQL, MySQL)
- High I/O workloads
- Ray worker scratch space
- When you need fast local disk performance

**Use `minio-nfs` for:**
- Shared configuration files
- Application logs that need to be accessible from multiple pods
- Data that should survive node failures
- When you need ReadWriteMany access

**Example: Pod with MinIO NFS Storage**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-config
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: minio-nfs
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: app-with-nfs
spec:
  containers:
    - name: app
      image: nginx:latest
      volumeMounts:
        - name: config
          mountPath: /etc/config
  volumes:
    - name: config
      persistentVolumeClaim:
        claimName: shared-config
```

## Configuration Variables

Edit `group_vars/all/vars.yml` to customize:

### Kubernetes Configuration
- `k8s_version`: Kubernetes version (default: "1.28")
- `pod_network_cidr`: Pod network CIDR (default: "10.244.0.0/16")

### Operators and Add-ons
- `ray_operator_version`: Ray Operator version (default: "1.1.1")
- `metallb_chart_version`: MetalLB Helm chart version (default: "0.14.8")
- `metallb_ip_range`: IP range for LoadBalancer services (default: "192.168.1.200-192.168.1.220")
- `minio_operator_version`: MinIO Operator version (default: "6.0.3")
- `minio_version`: MinIO server version

### Storage Configuration
- `usb_mount_path`: USB drive mount point (default: "/mnt/usb-storage")
- `usb_filesystem_type`: Filesystem type for USB drives (default: "ext4")
- `usb_format_drive`: Format USB drives during setup (default: false)
- `synology_nfs_server`: Synology NAS IP address for NFS (default: "192.168.1.50")
- `synology_nfs_path`: NFS export path on Synology (default: "/volume1/minio")

### GitOps Configuration
- `argocd_repo_url`: GitHub repository for app-of-apps pattern
- `argocd_repo_branch`: Git branch to track (default: "main")
- `argocd_repo_path`: Path to apps directory (default: "apps")

## Troubleshooting

### Check node status
```bash
kubectl get nodes -o wide
```

### View logs
```bash
# Kubernetes control plane
journalctl -u kubelet -f

# Argo CD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Ray Operator
kubectl logs -n kuberay-operator -l app.kubernetes.io/name=kuberay-operator
```

### Reset a node
```bash
# On the node to reset
sudo kubeadm reset
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/etcd
```

## Directory Structure

```
.
├── ansible.cfg              # Ansible configuration
├── site.yml                 # Main playbook
├── inventory/
│   └── hosts.yml           # Inventory file with node definitions
├── group_vars/
│   └── all/
│       └── vars.yml        # Global variables
└── roles/
    ├── kubernetes-prerequisites/
    │   └── tasks/
    │       └── main.yml    # Install prerequisites and container runtime
    ├── kubernetes-control-plane/
    │   └── tasks/
    │       └── main.yml    # Initialize control plane and install CNI
    ├── kubernetes-worker/
    │   └── tasks/
    │       └── main.yml    # Join worker nodes to cluster
    ├── gpu-prerequisites/
    │   └── tasks/
    │       └── main.yml    # Install NVIDIA drivers and container toolkit
    ├── gpu-node-labeling/
    │   └── tasks/
    │       └── main.yml    # Label GPU nodes
    ├── nvidia-device-plugin/
    │   └── tasks/
    │       └── main.yml    # Install NVIDIA Device Plugin for Kubernetes
    ├── argocd/
    │   └── tasks/
    │       └── main.yml    # Install and configure Argo CD
    ├── metallb/
    │   └── tasks/
    │       └── main.yml    # Install MetalLB load balancer
    ├── ray-operator/
    │   └── tasks/
    │       └── main.yml    # Install Ray Operator
    ├── minio/
    │   └── tasks/
    │       └── main.yml    # Install MinIO Operator and tenant
    ├── usb-storage/
    │   └── tasks/
    │       └── main.yml    # Configure USB storage on worker nodes
    └── usb-storage-k8s/
        └── tasks/
            └── main.yml    # Create Kubernetes PersistentVolumes for USB storage
```

## Security Notes

- Update the default Argo CD admin password after first login
- Consider using Ansible Vault for sensitive variables
- Configure firewall rules as needed for your environment
- Enable RBAC and network policies for production use
