# homelab-k8s-cluster

Ansible playbook for setting up a Kubernetes cluster in a home lab environment with Argo CD and Ray Operator.

## Architecture

- **Control Plane**: 1 VM on Synology NAS (192.168.1.50)
- **Worker Nodes**: 5 physical systems (192.168.1.51-192.168.1.55)
- **Network**: 192.168.1.0/24 subnet
- **Container Runtime**: containerd
- **CNI Plugin**: Flannel
- **GitOps**: Argo CD with app-of-apps pattern
- **ML/AI**: Ray Operator for distributed computing
- **Object Storage**: MinIO for S3-compatible storage

## Prerequisites

### On Control Machine
- Ansible 2.9 or higher
- SSH access to all nodes
- Python 3.x

### On All Nodes
- Ubuntu 20.04 or 22.04 (or Debian-based distribution)
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
   ssh-copy-id ansible@192.168.1.50
   ssh-copy-id ansible@192.168.1.51
   ssh-copy-id ansible@192.168.1.52
   ssh-copy-id ansible@192.168.1.53
   ssh-copy-id ansible@192.168.1.54
   ssh-copy-id ansible@192.168.1.55
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

```bash
# Only setup prerequisites
ansible-playbook site.yml --tags prerequisites

# Only setup control plane
ansible-playbook site.yml --limit control_plane

# Only setup worker nodes
ansible-playbook site.yml --limit workers
```

### Test connectivity

```bash
ansible all -m ping
```

## Post-Installation

### Access Kubernetes Cluster

From the control plane node:
```bash
kubectl get nodes
kubectl get pods -A
```

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


## Configuration Variables

Edit `group_vars/all.yml` to customize:

- `k8s_version`: Kubernetes version (default: "1.28")
- `pod_network_cidr`: Pod network CIDR (default: "10.244.0.0/16")
- `ray_operator_version`: Ray Operator version (default: "1.1.1")
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
│   └── all.yml             # Global variables
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
    ├── argocd/
    │   └── tasks/
    │       └── main.yml    # Install and configure Argo CD
    └── ray-operator/
        └── tasks/
            └── main.yml    # Install Ray Operator
```

## Security Notes

- Update the default Argo CD admin password after first login
- Consider using Ansible Vault for sensitive variables
- Configure firewall rules as needed for your environment
- Enable RBAC and network policies for production use
