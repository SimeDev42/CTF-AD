#!/bin/bash
# ============================================================
# CTF A/D — installer vulnbox
# Copia e incolla sulla vulnbox:
#   bash <(curl -sL https://raw.githubusercontent.com/SimeDev42/CTF-AD/main/install.sh)
# ============================================================

set -e

# --- Colori ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${CYAN}→${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err()  { echo -e "${RED}✗ ERRORE:${NC} $1"; exit 1; }

# --- URL base dei file (modifica con il tuo repo) ---
BASE_URL="https://raw.githubusercontent.com/SimeDev42/CTF-AD/main"

INSTALL_DIR="/root/ctf"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   CTF A/D — Vulnbox Setup Installer  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# --- Controlla dipendenze ---
info "Controllo dipendenze..."
command -v docker  >/dev/null 2>&1 || err "Docker non trovato. Installalo prima."
command -v curl    >/dev/null 2>&1 || err "curl non trovato."
command -v bash    >/dev/null 2>&1 || err "bash non trovato."
ok "Dipendenze OK"
echo ""

# --- Raccolta dati utente ---
echo -e "${YELLOW}Configura il tuo team:${NC}"
echo ""

read -p "  Team ID (es. 10): " TEAM_ID
[[ "$TEAM_ID" =~ ^[0-9]+$ ]] || err "Team ID deve essere un numero"

# IP team PC: default calcolato da TEAM_ID
DEFAULT_PC_IP="10.81.${TEAM_ID}.2"
read -p "  IP Team PC [default: $DEFAULT_PC_IP]: " TEAM_PC_IP
TEAM_PC_IP="${TEAM_PC_IP:-$DEFAULT_PC_IP}"

read -p "  Numero di servizi (es. 8): " SVC_COUNT
[[ "$SVC_COUNT" =~ ^[0-9]+$ ]] && [ "$SVC_COUNT" -ge 1 ] || err "Numero servizi non valido"

echo ""
echo -e "${YELLOW}Configura i servizi (porta pubblica attuale del servizio):${NC}"
echo -e "  ${CYAN}Convenzione: porta interna = porta pubblica + 10000${NC}"
echo ""

SERVICES=()
for i in $(seq 1 "$SVC_COUNT"); do
    read -p "  Servizio $i — nome: " SVC_NAME
    read -p "  Servizio $i — porta pubblica: " SVC_PUB
    [[ "$SVC_PUB" =~ ^[0-9]+$ ]] || err "Porta non valida"
    SVC_INT=$((SVC_PUB + 10000))
    echo -e "             ${CYAN}porta interna: $SVC_INT (automatica)${NC}"
    echo ""
    SERVICES+=("${SVC_NAME}:${SVC_PUB}:${SVC_INT}")
done

# --- Riepilogo e conferma ---
echo ""
echo -e "${YELLOW}Riepilogo configurazione:${NC}"
echo "  Team ID:    $TEAM_ID"
echo "  Team PC:    $TEAM_PC_IP"
echo "  Vulnbox IP: 10.60.${TEAM_ID}.1"
echo "  Servizi:    $SVC_COUNT"
for i in "${!SERVICES[@]}"; do
    IFS=':' read -r N P I <<< "${SERVICES[$i]}"
    echo "    $((i+1)). $N  pub:$P → int:$I"
done
echo ""
read -p "Confermi e avvii il setup? [s/N] " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || { echo "Annullato."; exit 0; }

# --- Crea directory ---
info "Creo $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
mkdir -p miniproxad-configs pcaps

# --- Scarica file da GitHub ---
echo ""
info "Scarico file necessari..."

curl -sL "${BASE_URL}/Dockerfile.miniproxad" -o Dockerfile.miniproxad
ok "Dockerfile.miniproxad"

curl -sL "${BASE_URL}/sync-pcaps.sh" -o sync-pcaps.sh
chmod +x sync-pcaps.sh
ok "sync-pcaps.sh"

# --- Genera .env ---
info "Genero .env..."
cat > .env << ENVEOF
TEAM_ID=${TEAM_ID}
TEAM_PC_IP=${TEAM_PC_IP}
SVC_COUNT=${SVC_COUNT}
ENVEOF

for i in "${!SERVICES[@]}"; do
    IFS=':' read -r N P I <<< "${SERVICES[$i]}"
    N_IDX=$((i+1))
    cat >> .env << ENVEOF
SVC_${N_IDX}_NAME=${N}
SVC_${N_IDX}_PUB=${P}
SVC_${N_IDX}_INT=${I}
ENVEOF
done
ok ".env generato"

# --- Genera config MiniProxad ---
info "Genero config MiniProxad..."
for i in "${!SERVICES[@]}"; do
    IFS=':' read -r NAME PUB INT <<< "${SERVICES[$i]}"
    N_IDX=$((i+1))
    cat > "miniproxad-configs/svc${N_IDX}.yml" << CFGEOF
service_name: ${NAME}

from_ip: 0.0.0.0
from_port: ${PUB}
from_timeout: 60s
from_max_history: 10Mib

to_ip: 127.0.0.1
to_port: ${INT}
to_timeout: 60s
to_max_history: 100Mib

dump_enabled: true
dump_path: "/pcaps"
dump_format: "${NAME}_{timestamp}.pcap"
dump_interval: 30s
dump_max_packets: 256
CFGEOF
    ok "Config: $NAME (pub:$PUB → int:$INT)"
done

# --- Genera docker-compose.yml ---
info "Genero docker-compose.yml..."
cat > docker-compose.yml << COMPOSEEOF
version: "3.8"

x-miniproxad: &miniproxad-base
  build:
    context: .
    dockerfile: Dockerfile.miniproxad
  image: miniproxad:local
  restart: unless-stopped
  network_mode: host

services:
COMPOSEEOF

for i in $(seq 1 "$SVC_COUNT"); do
    cat >> docker-compose.yml << COMPOSEEOF

  miniproxad-${i}:
    <<: *miniproxad-base
    container_name: miniproxad-svc${i}
    volumes:
      - ./miniproxad-configs/svc${i}.yml:/config.yml:ro
      - ./pcaps:/pcaps
COMPOSEEOF
done
ok "docker-compose.yml generato"

# --- Build immagine MiniProxad ---
echo ""
warn "Build MiniProxad (~5-10 min). Fallo PRIMA della gara."
read -p "Vuoi buildare ora? [S/n] " BUILD_NOW
if [[ ! "$BUILD_NOW" =~ ^[nN]$ ]]; then
    info "Build in corso..."
    docker compose build
    ok "Build completato"
else
    warn "Ricordati di eseguire 'docker compose build' prima della gara!"
fi

# --- Avvia Firegex ---
echo ""
info "Avvio Firegex..."
sh <(curl -sLf https://pwnzer0tt1.it/firegex.sh)

# --- Avvia MiniProxad ---
echo ""
info "Avvio MiniProxad..."
docker compose up -d
ok "MiniProxad avviato"

# --- Done ---
echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Setup completato!             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "  Firegex:   http://10.60.${TEAM_ID}.1:4444"
echo "  Directory: $INSTALL_DIR"
echo ""
echo -e "${YELLOW}PROSSIMI PASSI:${NC}"
for i in "${!SERVICES[@]}"; do
    IFS=':' read -r N P I <<< "${SERVICES[$i]}"
    echo "  → Sposta $N: porta $P → $I nel suo docker-compose"
done
echo ""
echo "  → cd $INSTALL_DIR && bash sync-pcaps.sh  (in un tmux separato)"
echo ""
