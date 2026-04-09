#!/bin/bash
# Sincronizza i pcap dalla vulnbox al team PC in continuo
# Avvia questo su un tmux/screen separato dopo setup.sh
#
# Uso: bash sync-pcaps.sh

source .env

if [ -z "$TEAM_PC_IP" ]; then
    echo "ERRORE: TEAM_PC_IP non impostato nel .env"
    exit 1
fi

REMOTE_USER="root"
REMOTE_DIR="/tulip/pcaps"
LOCAL_DIR="./pcaps"
INTERVAL=15

echo "→ Sync pcap verso $TEAM_PC_IP:$REMOTE_DIR ogni ${INTERVAL}s"
echo "  Premi Ctrl+C per fermare"
echo ""

while true; do
    rsync -az --no-perms \
        -e "ssh -o StrictHostKeyChecking=no" \
        "$LOCAL_DIR/" \
        "$REMOTE_USER@$TEAM_PC_IP:$REMOTE_DIR/" \
        2>/dev/null && echo "[$(date +%H:%M:%S)] ✓ sync ok" || echo "[$(date +%H:%M:%S)] ✗ sync fallito"
    sleep $INTERVAL
done
