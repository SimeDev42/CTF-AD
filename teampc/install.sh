#!/bin/bash
# ============================================================
# CTF A/D — installer team PC
# Installa: Gitea, Tulip, ExploitFarm
#
# Uso: bash <(curl -sL https://raw.githubusercontent.com/SimeDev42/CTF-AD/main/teampc/install.sh)
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${CYAN}→${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗ ERRORE:${NC} $1"; exit 1; }

INSTALL_DIR="./ctf-teampc"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    CTF A/D — Team PC Installer       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# --- Dipendenze ---
info "Controllo dipendenze..."
command -v docker >/dev/null 2>&1 || err "Docker non trovato."
command -v git    >/dev/null 2>&1 || err "git non trovato."
command -v curl   >/dev/null 2>&1 || err "curl non trovato."
ok "Dipendenze OK"
echo ""

# --- Raccolta dati ---
echo -e "${YELLOW}Configura il team PC:${NC}"
echo ""

read -p "  Team ID (es. 10): " TEAM_ID
[[ "$TEAM_ID" =~ ^[0-9]+$ ]] || err "Team ID deve essere un numero"

VULNBOX_IP="10.60.${TEAM_ID}.1"
read -p "  IP vulnbox [default: $VULNBOX_IP]: " INPUT_VULNBOX
VULNBOX_IP="${INPUT_VULNBOX:-$VULNBOX_IP}"

TEAM_PC_IP="10.81.${TEAM_ID}.254"
read -p "  IP Team PC (interfaccia VPN/compagni) [default: $TEAM_PC_IP]: " INPUT_TEAM_PC
TEAM_PC_IP="${INPUT_TEAM_PC:-$TEAM_PC_IP}"

read -p "  Flag token (dato dagli organizzatori): " FLAG_TOKEN
[[ -n "$FLAG_TOKEN" ]] || err "Flag token obbligatorio"

read -p "  Password Gitea (sceglila ora): " GITEA_PASS
[[ -n "$GITEA_PASS" ]] || err "Password Gitea obbligatoria"

# --- Riepilogo ---
echo ""
echo -e "${YELLOW}Riepilogo:${NC}"
echo "  Team ID:    $TEAM_ID"
echo "  Vulnbox:    $VULNBOX_IP"
echo "  Team PC IP: $TEAM_PC_IP"
echo "  Gitea:      http://$TEAM_PC_IP:3000"
echo "  Tulip:      http://$TEAM_PC_IP:8888"
echo "  ExploitFarm: http://$TEAM_PC_IP:5050"
echo ""
read -p "Confermi? [s/N] " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || { echo "Annullato."; exit 0; }

# --- Setup directory ---
mkdir -p "$INSTALL_DIR"/{gitea-data,tulip-pcaps,exploits}
cd "$INSTALL_DIR"

# --- Genera .env ---
info "Genero .env..."
cat > .env << ENVEOF
TEAM_ID=${TEAM_ID}
VULNBOX_IP=${VULNBOX_IP}
TEAM_PC_IP=${TEAM_PC_IP}
FLAG_TOKEN=${FLAG_TOKEN}
GITEA_PASS=${GITEA_PASS}
ENVEOF
ok ".env generato"

# --- Clona Tulip ---
info "Clono Tulip..."
if [ ! -d "tulip" ]; then
    git clone https://github.com/OpenAttackDefenseTools/tulip.git
fi

# Genera configurazione Tulip
cat > tulip/services/api/configurations.py << TULIPEOF
vm_ip = "${VULNBOX_IP}"

# Aggiungi i servizi dopo aver visto i docker della vulnbox
# Usa le porte INTERNE (INT = PUB + 10000)
services = [
    # {"ip": vm_ip, "port": 18080, "name": "service1"},
    # {"ip": vm_ip, "port": 18081, "name": "service2"},
]
TULIPEOF

# Genera .env per Tulip
cat > tulip/.env << TULIPENVEOF
TULIP_FLAGREGEX=[A-Z0-9]{31}=
TULIP_FLAGLEN=32
TULIP_TICK_DURATION=120
TRAFFIC_DIR_HOST=${INSTALL_DIR}/tulip-pcaps
TULIPENVEOF

ok "Tulip configurato"

# --- Scarica docker-compose.yml ---
info "Scarico docker-compose.yml..."
curl -sL "https://raw.githubusercontent.com/SimeDev42/CTF-AD/main/teampc/docker-compose.yml" -o docker-compose.yml
ok "docker-compose.yml scaricato"

# --- Avvia Gitea + ExploitFarm ---
echo ""
info "Avvio Gitea e ExploitFarm..."
docker compose up -d
ok "Servizi avviati"

# --- Avvia Tulip ---
echo ""
info "Avvio Tulip (build ~2 min)..."
cd tulip
docker compose up -d --build
cd ..
ok "Tulip avviato"

# --- Post-install: configura Gitea ---
echo ""
info "Attendo che Gitea sia pronto..."
for i in $(seq 1 30); do
    curl -s http://$TEAM_PC_IP:3000 >/dev/null 2>&1 && break
    sleep 2
done

# Crea admin via CLI dentro il container
docker exec -u git gitea gitea admin user create \
    --username admin \
    --password "$GITEA_PASS" \
    --email "admin@ctf.local" \
    --admin 2>/dev/null || warn "Admin Gitea già esistente o errore — verificalo manualmente"

ok "Gitea admin creato"

# --- Done ---
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Setup team PC completato!         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Gitea:       http://$TEAM_PC_IP:3000  (admin / $GITEA_PASS)"
echo "  Tulip:       http://$TEAM_PC_IP:8888"
echo "  ExploitFarm: http://$TEAM_PC_IP:5050"
echo ""
echo -e "${YELLOW}PROSSIMI PASSI:${NC}"
echo ""
echo "  1. Gitea: crea repo 'exploits' e 'patches'"
echo "     Aggiungi hook post-receive per deploy patch sulla vulnbox"
echo ""
echo "  2. Tulip: modifica $INSTALL_DIR/tulip/services/api/configurations.py"
echo "     con le porte INT dei servizi, poi:"
echo "     cd $INSTALL_DIR/tulip && docker compose up --build -d api"
echo ""
echo "  3. ExploitFarm: apri http://$TEAM_PC_IP:5050 e configura:"
echo "     - Flag regex: [A-Z0-9]{31}="
echo "     - Tick: 120s"
echo "     - Teams: 10.60.1.1 → 10.60.N.1 (escludi il tuo)"
echo "     - Submitter: vedi sotto"
echo ""
echo "  4. ExploitFarm submitter — incolla questo codice nell'interfaccia:"
echo ""
cat << SUBEOF
import requests

FLAG_SUBMISSION_URL = "http://10.10.0.1:8080/flags"

def submit(flags: list, token: str = "${FLAG_TOKEN}"):
    res = requests.put(
        FLAG_SUBMISSION_URL,
        headers={"X-Team-Token": token},
        json=flags,
        timeout=10
    )
    for r in res.json():
        print(r["msg"])
SUBEOF
echo ""
echo "  5. Installa il client xfarm su ogni PC del team:"
echo "     pip3 install -U xfarm && xfarm --install-completion"
echo ""
echo "  6. Avvia sync pcap dalla vulnbox (su un tmux):"
echo "     ssh root@$VULNBOX_IP 'cd /root/ctf && bash sync-pcaps.sh'"
echo ""