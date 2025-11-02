#!/bin/bash
# Helper script to get USB device UUIDs from all worker nodes
# Usage: ./scripts/get-usb-uuids.sh

WORKERS=(
  "k8s-worker-01:192.168.1.51"
  "k8s-worker-02:192.168.1.52"
  "k8s-worker-03:192.168.1.53"
)

SSH_USER="ansible"

echo "=== USB Device UUID Discovery ==="
echo ""

for worker in "${WORKERS[@]}"; do
  IFS=: read -r name ip <<< "$worker"

  echo "📍 $name ($ip)"
  echo "----------------------------------------"

  # Check if node is reachable
  if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$ip" "exit" 2>/dev/null; then
    echo "❌ Cannot connect to $name"
    echo ""
    continue
  fi

  # Get block devices
  echo "Block devices:"
  ssh "$SSH_USER@$ip" "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'disk|part'" 2>/dev/null
  echo ""

  # Get USB device UUIDs
  echo "USB device UUIDs:"
  ssh "$SSH_USER@$ip" "sudo blkid | grep -i 'sd[b-z]' || echo 'No additional drives found'" 2>/dev/null
  echo ""

  # Suggest configuration
  echo "💡 Suggested inventory configuration:"
  UUID=$(ssh "$SSH_USER@$ip" "sudo blkid | grep -i 'sdb1' | sed -n 's/.*UUID=\"\\([^\"]*\\)\".*/\\1/p'" 2>/dev/null)
  if [ -n "$UUID" ]; then
    echo "  $name:"
    echo "    ansible_host: $ip"
    echo "    ansible_user: $SSH_USER"
    echo "    usb_device_uuid: \"$UUID\""
    echo "    usb_storage_capacity: 100Gi  # Adjust to actual size"
  else
    echo "  No /dev/sdb1 found. Check block devices above and adjust accordingly."
  fi

  echo ""
  echo "========================================"
  echo ""
done

echo "✅ Discovery complete!"
echo ""
echo "To use these UUIDs:"
echo "1. Copy the suggested configuration to inventory/hosts.yml"
echo "2. Adjust usb_storage_capacity to match your actual drive sizes"
echo "3. Run: ansible-playbook site.yml"