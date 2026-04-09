# CTF A/D — Vulnbox Setup

## File nel repo

```
repo/
├── install.sh            ← installer interattivo (one-liner)
├── Dockerfile.miniproxad ← build MiniProxad
└── sync-pcaps.sh         ← sync pcap → Tulip sul team PC
```

Tutto il resto (`.env`, `docker-compose.yml`, `miniproxad-configs/`) viene
generato da `install.sh` direttamente sulla vulnbox.


## Grace period — setup vulnbox (hai 30 minuti)

### 1. Esegui il one-liner sulla vulnbox

```bash
bash <(curl -sL https://raw.githubusercontent.com/SimeDev42/CTF-AD/main/install.sh)
```

Lo script chiede interattivamente:
- Team ID
- IP del team PC
- Numero di servizi
- Nome e porta pubblica di ogni servizio

La porta interna viene calcolata automaticamente: `INT = PUB + 10000`

### 2. Sposta i servizi sulle porte interne

Per ogni servizio, modifica il suo `docker-compose.yml` per farlo
ascoltare sulla porta interna invece di quella pubblica, poi:

```bash
docker compose restart <nome-servizio>
```

### 3. Avvia sync pcap in background

```bash
cd /root/ctf
tmux new -s pcaps
bash sync-pcaps.sh
# Ctrl+B D per detach
```

---

## Durante la gara

**Fermare un singolo MiniProxad** (emergenza SLA):
```bash
cd /root/ctf
docker compose stop miniproxad-3
```
Il traffico torna direttamente al servizio — perdi il logging ma salvi l'SLA.

**Firegex** (WAF):
```
http://10.60.<TEAM_ID>.1:4444
```
Workflow: vedi l'attacco su Tulip → scrivi regex → attiva in "log only" → verifica che il checker passi → attiva "block".

**Riavviare tutto**:
```bash
cd /root/ctf
docker compose restart
```

---

## Struttura generata sulla vulnbox

```
/root/ctf/
├── .env                     ← generato da install.sh
├── docker-compose.yml        ← generato da install.sh
├── Dockerfile.miniproxad     ← scaricato da install.sh
├── sync-pcaps.sh             ← scaricato da install.sh
├── miniproxad-configs/
│   ├── svc1.yml
│   └── ...
└── pcaps/                   ← pcap dumped da MiniProxad
```

---

## Tool sul team PC (setup separato)

| Tool | Funzione |
|------|----------|
| Gitea | Versioning patch + deploy automatico via SSH hook |
| Tulip | Analisi pcap ricevuti da sync-pcaps.sh |
| ExploitFarm | Lancia exploit su tutti i team in parallelo |

---

## Rete di gara

| Indirizzo | Cosa |
|-----------|------|
| `10.60.<TEAM_ID>.1` | La tua vulnbox |
| `10.60.0.1` | NOP team — testa gli exploit qui |
| `10.81.<TEAM_ID>.X` | Tuoi PC sulla game network |
| `10.10.0.1:8080` | Flag submission |
| `10.10.0.1:8081` | Flag IDs |

Tick: **120 secondi** — flag valida per **5 tick (10 min)**.