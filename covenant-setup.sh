#!/usr/bin/env bash
# ============================================================
#   ██████╗ ██████╗ ██╗   ██╗███████╗███╗   ██╗ █████╗ ███╗   ██╗████████╗
#  ██╔════╝██╔═══██╗██║   ██║██╔════╝████╗  ██║██╔══██╗████╗  ██║╚══██╔══╝
#  ██║     ██║   ██║██║   ██║█████╗  ██╔██╗ ██║███████║██╔██╗ ██║   ██║   
#  ██║     ██║   ██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██╔══██║██║╚██╗██║   ██║   
#  ╚██████╗╚██████╔╝ ╚████╔╝ ███████╗██║ ╚████║██║  ██║██║ ╚████║   ██║   
#   ╚═════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   
#             Covenant-CachyOS — System Optimizer & Tuner
# ============================================================
#   Aplica otimizações de sistema para máxima performance em CachyOS/Arch.
#   Suporta auto-detecção de topologia NUMA, CPU, GPU e memória.
#
#   Uso:
#     sudo bash covenant-setup.sh              (execução normal)
#     sudo bash covenant-setup.sh --dry-run    (visualiza sem alterar o sistema)
#     sudo bash covenant-setup.sh --rollback   (desfaz as otimizações do Covenant)
# ============================================================

set -euo pipefail

# ─── Cores e Efeitos ──────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GOLD='\033[38;5;220m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

CHECK="✓"
ARROW="→"
ALERT="!"
CROSS="✗"

log()  { echo -e "  ${GREEN}[${CHECK}]${NC} $1"; }
info() { echo -e "  ${CYAN}[${ARROW}]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[${ALERT}]${NC} $1"; }
err()  { echo -e "  ${RED}[${CROSS}]${NC} $1"; exit 1; }

# ─── Banner ───────────────────────────────────────────────────
print_banner() {
  echo -e "${CYAN}${BOLD}"
  cat << 'EOF'
   ██████╗ ██████╗ ██╗   ██╗███████╗███╗   ██╗ █████╗ ███╗   ██╗████████╗
  ██╔════╝██╔═══██╗██║   ██║██╔════╝████╗  ██║██╔══██╗████╗  ██║╚══██╔══╝
  ██║     ██║   ██║██║   ██║█████╗  ██╔██╗ ██║███████║██╔██╗ ██║   ██║   
  ██║     ██║   ██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██╔══██║██║╚██╗██║   ██║   
  ╚██████╗╚██████╔╝ ╚████╔╝ ███████╗██║ ╚████║██║  ██║██║ ╚████║   ██║   
   ╚═════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   
EOF
  echo -e "${GOLD}           ⚡ CachyOS Performance & System Optimizer ⚡${NC}"
  echo -e "${DIM}             By Anderson Araujo  ·  MIT License${NC}"
  echo ""
}

# ─── Argumentos de Linha de Comando ──────────────────────────
DRY_RUN=false
DO_ROLLBACK=false
INSTALL_THEME=false

show_help() {
  print_banner
  cat << 'EOF'
Opções:
  -n, --dry-run          Simula a execução mostrando o que seria feito sem alterar o sistema
  -r, --rollback         Restaura os arquivos originais e remove as configurações do Covenant
  --install-theme        Instala também o tema GRUB oficial do Covenant
  -h, --help             Exibe esta ajuda

Exemplos:
  sudo bash covenant-setup.sh
  sudo bash covenant-setup.sh --dry-run
  sudo bash covenant-setup.sh --rollback
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY_RUN=true ;;
    -r|--rollback) DO_ROLLBACK=true ;;
    --install-theme) INSTALL_THEME=true ;;
    -h|--help) show_help ;;
    *) warn "Opção desconhecida: $arg (use --help para ver as opções)" ;;
  esac
done

# Wrapper para respeitar o modo dry-run
run_cmd() {
  if $DRY_RUN; then
    echo -e "    ${DIM}[DRY-RUN] ${*}${NC}"
  else
    "$@"
  fi
}

write_file() {
  local target="$1"
  local content="$2"
  if $DRY_RUN; then
    echo -e "    ${DIM}[DRY-RUN] Escrever em ${target} (${#content} bytes)${NC}"
  else
    mkdir -p "$(dirname "$target")"
    echo "$content" > "$target"
  fi
}

# ─── Verificação de Privilégios ──────────────────────────────
[ "$EUID" -eq 0 ] || err "Execute com privilégios de root: sudo bash covenant-setup.sh"

# ─── Detecção Segura do Usuário ──────────────────────────────
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  REAL_USER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
  REAL_USER=$(id -un "$PKEXEC_UID" 2>/dev/null || whoami)
else
  REAL_USER=$(logname 2>/dev/null || whoami)
fi
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
USER_HOME="${USER_HOME:-/home/$REAL_USER}"

# Migração de typo histórico (~/Kernal -> ~/Kernel)
KERNEL_DIR="$USER_HOME/Kernel"
if [ -d "$USER_HOME/Kernal" ] && [ ! -d "$KERNEL_DIR" ]; then
  if ! $DRY_RUN; then
    mv "$USER_HOME/Kernal" "$KERNEL_DIR"
    chown -R "$REAL_USER:$REAL_USER" "$KERNEL_DIR" 2>/dev/null || true
  fi
  warn "Migrado diretório histórico: ~/Kernal → ~/Kernel"
fi

# ─── ROLLBACK ────────────────────────────────────────────────
if $DO_ROLLBACK; then
  print_banner
  echo -e "${YELLOW}${BOLD}=== Executando Rollback das Otimizações do Covenant ===${NC}\n"
  
  # Restaurar GRUB
  if [ -f /etc/default/grub.covenant-orig ]; then
    info "Restaurando /etc/default/grub original..."
    run_cmd cp /etc/default/grub.covenant-orig /etc/default/grub
    run_cmd grub-mkconfig -o /boot/grub/grub.cfg
    log "GRUB restaurado para a versão original."
  else
    warn "Arquivo /etc/default/grub.covenant-orig não encontrado."
  fi

  # Remover configs criadas
  FILES_TO_REMOVE=(
    "/etc/scx_loader/config.toml"
    "/etc/sysctl.d/99-covenant-perf.conf"
    "/etc/systemd/zram-generator.conf"
    "/etc/tmpfiles.d/cpu-governor.conf"
    "/etc/udev/rules.d/60-ioscheduler.rules"
    "/etc/udev/rules.d/61-amdgpu-performance.rules"
    "/etc/covenant/rollback.sh"
  )
  for f in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$f" ]; then
      info "Removendo $f..."
      run_cmd rm -f "$f"
    fi
  done

  # Re-aplicar sysctl padrão
  run_cmd sysctl --system >/dev/null 2>&1 || true

  # Re-habilitar irqbalance caso tenha sido desativado
  run_cmd systemctl enable irqbalance 2>/dev/null || true
  run_cmd systemctl daemon-reload 2>/dev/null || true

  echo ""
  log "Rollback finalizado com sucesso! Reinicie o sistema se desejar restaurar o estado completo."
  exit 0
fi

# ─── Inicialização Normal do Setup ────────────────────────────
print_banner

if $DRY_RUN; then
  echo -e "${YELLOW}${BOLD}⚡ MODO SIMULAÇÃO (--dry-run) ATIVO — Nenhuma alteração real será feita ⚡${NC}\n"
fi

# ─── Detecção de Hardware ────────────────────────────────────
TOTAL_CPUS=$(nproc --all 2>/dev/null || echo 1)
NUMA_NODES=1
if [ -d /sys/devices/system/node ]; then
  NUMA_NODES=$(find /sys/devices/system/node -maxdepth 1 -name "node*" 2>/dev/null | wc -l)
fi

MEM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 16777216)
MEM_TOTAL_GB=$(( MEM_TOTAL_KB / 1024 / 1024 ))

CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Processador x86_64")

# Identificar GPUs instaladas
GPUS=$(lspci 2>/dev/null | grep -i 'vga\|3d\|display' || true)
AMD_GPU_NAME=""
NVIDIA_GPU_NAME=""
if echo "$GPUS" | grep -qi 'amd\|ati'; then
  AMD_GPU_NAME=$(echo "$GPUS" | grep -i 'amd\|ati' | head -1 | sed 's/.*: //')
fi
if echo "$GPUS" | grep -qi 'nvidia'; then
  NVIDIA_GPU_NAME=$(echo "$GPUS" | grep -i 'nvidia' | head -1 | sed 's/.*: //')
fi

echo -e "${BOLD}Hardware Detectado:${NC}"
echo -e "  ${DIM}CPU   :${NC} ${BOLD}$CPU_MODEL${NC} ($TOTAL_CPUS threads)"
echo -e "  ${DIM}NUMA  :${NC} ${BOLD}$NUMA_NODES${NC} nó(s)"
echo -e "  ${DIM}RAM   :${NC} ${BOLD}${MEM_TOTAL_GB} GB${NC}"
if [ -n "$AMD_GPU_NAME" ]; then
  echo -e "  ${DIM}GPU   :${NC} ${BOLD}AMD${NC} ($AMD_GPU_NAME)"
fi
if [ -n "$NVIDIA_GPU_NAME" ]; then
  echo -e "  ${DIM}GPU   :${NC} ${BOLD}NVIDIA${NC} ($NVIDIA_GPU_NAME)"
fi
echo -e "  ${DIM}User  :${NC} ${BOLD}$REAL_USER${NC} (Home: $USER_HOME)"
echo ""

TOTAL_STEPS=11
STEP=0

step() {
  STEP=$((STEP + 1))
  local PCT=$(( STEP * 100 / TOTAL_STEPS ))
  local FILLED=$(( PCT / 5 ))
  local EMPTY=$(( 20 - FILLED ))
  local BAR=""
  [ "$FILLED" -gt 0 ] && BAR=$(printf '█%.0s' $(seq 1 $FILLED))
  [ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf '░%.0s' $(seq 1 $EMPTY))"
  
  echo -e "\n${BOLD}${BLUE}[${STEP}/${TOTAL_STEPS}]${NC} ${BOLD}$1${NC}"
  echo -e "  ${DIM}[${BAR}] ${PCT}%${NC}"
}

# Criar script de rollback para registro
ROLLBACK_SCRIPT="/etc/covenant/rollback.sh"
if ! $DRY_RUN; then
  mkdir -p /etc/covenant
  cat > "$ROLLBACK_SCRIPT" << 'RBSCRIPT'
#!/usr/bin/env bash
# Script gerado automaticamente pelo Covenant Setup
# Para reverter todas as modificações: sudo /etc/covenant/rollback.sh
set -euo pipefail
echo "Desfazendo configurações do Covenant..."
if [ -f /etc/default/grub.covenant-orig ]; then
  cp /etc/default/grub.covenant-orig /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg
fi
rm -f /etc/scx_loader/config.toml
rm -f /etc/sysctl.d/99-covenant-perf.conf
rm -f /etc/systemd/zram-generator.conf
rm -f /etc/tmpfiles.d/cpu-governor.conf
rm -f /etc/udev/rules.d/60-ioscheduler.rules
rm -f /etc/udev/rules.d/61-amdgpu-performance.rules
sysctl --system >/dev/null 2>&1 || true
systemctl daemon-reload >/dev/null 2>&1 || true
echo "Rollback concluído!"
RBSCRIPT
  chmod +x "$ROLLBACK_SCRIPT"
fi

# ─────────────────────────────────────────
# PASSO 0 — Backup dos originais
# ─────────────────────────────────────────
step "Preservando arquivos originais para rollback..."
if [ -f /etc/default/grub ] && [ ! -f /etc/default/grub.covenant-orig ]; then
  run_cmd cp /etc/default/grub /etc/default/grub.covenant-orig
  log "Backup salvo: /etc/default/grub.covenant-orig"
else
  log "Backup do GRUB já existente ou não necessário."
fi

# ─────────────────────────────────────────
# PASSO 1 — Kernel Base (CachyOS)
# ─────────────────────────────────────────
step "Garantindo kernel base linux-cachyos (fallback seguro)..."
run_cmd pacman -S --needed --noconfirm \
  cachyos-v3/linux-cachyos \
  cachyos-v3/linux-cachyos-headers 2>/dev/null || \
run_cmd pacman -S --needed --noconfirm \
  linux-cachyos \
  linux-cachyos-headers
log "Kernel base presente."

# ─────────────────────────────────────────
# PASSO 2 — SCX Scheduler Adaptativo
# ─────────────────────────────────────────
step "Configurando SCX Scheduler (sched_ext)..."
run_cmd pacman -S --needed --noconfirm scx-scheds

CHOSEN_SCHED="scx_rusty"
CHOSEN_MODE="Auto"
if [ "$NUMA_NODES" -gt 1 ]; then
  CHOSEN_SCHED="scx_rusty"
  CHOSEN_MODE="Auto"
  info "Topologia multi-socket detectada → selecionado scx_rusty (NUMA-aware)"
else
  # Em single-socket, scx_bpfland oferece menor latência em jogos
  if command -v scx_bpfland &>/dev/null || pacman -Ql scx-scheds 2>/dev/null | grep -q "scx_bpfland"; then
    CHOSEN_SCHED="scx_bpfland"
    CHOSEN_MODE="Gaming"
    info "Topologia single-socket detectada → selecionado scx_bpfland (baixa latência)"
  else
    CHOSEN_SCHED="scx_rusty"
    CHOSEN_MODE="Auto"
  fi
fi

SCX_CONFIG="default_sched = \"${CHOSEN_SCHED}\"
default_mode = \"${CHOSEN_MODE}\"
"
write_file "/etc/scx_loader/config.toml" "$SCX_CONFIG"
run_cmd systemctl enable --now scx_loader 2>/dev/null || true
log "Scheduler $CHOSEN_SCHED ativado via scx_loader."

# ─────────────────────────────────────────
# PASSO 3 — Parâmetros de Boot + GRUB
# ─────────────────────────────────────────
step "Calculando cmdline do Kernel e configurando GRUB..."

# Cálculo dinâmico dos ranges de CPU para nohz_full e irqaffinity
CMDLINE_BASE="quiet loglevel=3 nowatchdog mitigations=off"

if [ "$NUMA_NODES" -gt 1 ] && [ -f /sys/devices/system/node/node0/cpulist ] && [ -f /sys/devices/system/node/node1/cpulist ]; then
  N0_CPUS=$(cat /sys/devices/system/node/node0/cpulist)
  N1_CPUS=$(cat /sys/devices/system/node/node1/cpulist)
  N1_FIRST=$(echo "$N1_CPUS" | cut -d, -f1 | cut -d- -f1)
  
  # Isola o nó 0 para tarefas críticas/jogos, reservando o primeiro core para IRQs
  if [[ "$N0_CPUS" =~ ^0-([0-9]+)(.*) ]]; then
    END1="${BASH_REMATCH[1]}"
    REST="${BASH_REMATCH[2]}"
    ISOLATED="1-${END1}${REST}"
  elif [[ "$N0_CPUS" =~ ^0,(.*) ]]; then
    ISOLATED="${BASH_REMATCH[1]}"
  else
    ISOLATED="$N0_CPUS"
  fi
  CMDLINE="$CMDLINE_BASE numa_balancing=1 nohz_full=${ISOLATED} rcu_nocbs=${ISOLATED} irqaffinity=0,${N1_FIRST}"
  info "NUMA multi-socket: nohz_full=${ISOLATED} irqaffinity=0,${N1_FIRST}"
else
  if [ "$TOTAL_CPUS" -ge 8 ]; then
    ISOLATED="1-$((TOTAL_CPUS - 1))"
    CMDLINE="$CMDLINE_BASE numa_balancing=0 nohz_full=${ISOLATED} rcu_nocbs=${ISOLATED} irqaffinity=0"
    info "Single-socket: nohz_full=${ISOLATED} irqaffinity=0"
  else
    CMDLINE="$CMDLINE_BASE numa_balancing=0"
    info "Single-socket padrão configurado."
  fi
fi

if ! $DRY_RUN; then
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"|" /etc/default/grub
  else
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"" >> /etc/default/grub
  fi

  if grep -q '^GRUB_DISTRIBUTOR=' /etc/default/grub; then
    sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="Covenant-CachyOS"|' /etc/default/grub
  else
    echo 'GRUB_DISTRIBUTOR="Covenant-CachyOS"' >> /etc/default/grub
  fi

  grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || grub-mkconfig -o /boot/grub/grub.cfg
fi
log "GRUB atualizado com sucesso."

# ─────────────────────────────────────────
# PASSO 4 — Sysctl Tuning
# ─────────────────────────────────────────
step "Aplicando tunings avançados de kernel (sysctl)..."
SYSCTL_CONF="# ═══════════════════════════════════════════════════════════
#   Covenant-CachyOS Performance Sysctl Configuration
# ═══════════════════════════════════════════════════════════

# ── Memória e Cache ─────────────────────────────────────────
vm.swappiness = 100
vm.page-cluster = 0
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 250
vm.compaction_proactiveness = 20
vm.vfs_cache_pressure = 50

# ── Scheduler e Timer ───────────────────────────────────────
kernel.sched_autogroup_enabled = 1
kernel.numa_balancing = $( [ "$NUMA_NODES" -gt 1 ] && echo 1 || echo 0 )
kernel.timer_migration = 0

# ── Rede de Alta Performance (BBRv3 + Buffers) ─────────────
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
"
write_file "/etc/sysctl.d/99-covenant-perf.conf" "$SYSCTL_CONF"
run_cmd sysctl --system >/dev/null 2>&1 || true
log "Sysctl aplicado (I/O burst, zram-aware, buffers TCP)."

# ─────────────────────────────────────────
# PASSO 5 — Governor Performance + Gamemode
# ─────────────────────────────────────────
step "Configurando Governor Performance e Gamemode..."
run_cmd pacman -S --needed --noconfirm \
  numactl hwloc cpupower gamemode lib32-gamemode

run_cmd cpupower frequency-set -g performance >/dev/null 2>&1 || true
run_cmd systemctl disable --now irqbalance 2>/dev/null || true

GOV_CONF="w /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor - - - - performance"
write_file "/etc/tmpfiles.d/cpu-governor.conf" "$GOV_CONF"
log "Governor performance persistido via tmpfiles.d."

# ─────────────────────────────────────────
# PASSO 6 — Zram Adaptativo
# ─────────────────────────────────────────
step "Configurando Zram Adaptativo..."
run_cmd pacman -S --needed --noconfirm zram-generator

if [ "$MEM_TOTAL_GB" -ge 64 ]; then
  ZRAM_SIZE="ram / 2"
  ZRAM_ALGO="zstd"
elif [ "$MEM_TOTAL_GB" -le 16 ]; then
  ZRAM_SIZE="ram"
  ZRAM_ALGO="zstd"
else
  ZRAM_SIZE="ram / 2"
  ZRAM_ALGO="zstd"
fi

ZRAM_CONF="[zram0]
zram-size = ${ZRAM_SIZE}
compression-algorithm = ${ZRAM_ALGO}
"
write_file "/etc/systemd/zram-generator.conf" "$ZRAM_CONF"
run_cmd systemctl daemon-reload
run_cmd systemctl start systemd-zram-setup@zram0 2>/dev/null || true
log "Zram configurado: tamanho=$ZRAM_SIZE, algo=$ZRAM_ALGO."

# ─────────────────────────────────────────
# PASSO 7 — Ananicy-cpp (Prioridade Automática)
# ─────────────────────────────────────────
step "Instalando e habilitando Ananicy-cpp..."
run_cmd pacman -S --needed --noconfirm ananicy-cpp
run_cmd systemctl enable --now ananicy-cpp 2>/dev/null || true
log "Ananicy-cpp ativo."

# ─────────────────────────────────────────
# PASSO 8 — Otimização de GPU
# ─────────────────────────────────────────
step "Detectando e otimizando perfil de GPU..."
if [ -n "$AMD_GPU_NAME" ]; then
  for card in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
    if [ -w "$card" ]; then
      run_cmd bash -c "echo 'high' > '$card'" 2>/dev/null || true
    fi
  done
  AMD_UDEV='ACTION=="add|change", SUBSYSTEM=="pci", DRIVERS=="amdgpu", ATTR{power_dpm_force_performance_level}="high"'
  write_file "/etc/udev/rules.d/61-amdgpu-performance.rules" "$AMD_UDEV"
  log "GPU AMD ($AMD_GPU_NAME): perfil high performance ativado."
elif [ -n "$NVIDIA_GPU_NAME" ]; then
  if command -v nvidia-smi &>/dev/null; then
    run_cmd nvidia-smi -pm 1 >/dev/null 2>&1 || true
    log "GPU NVIDIA ($NVIDIA_GPU_NAME): Persistence Mode ativado."
  else
    info "GPU NVIDIA detectada ($NVIDIA_GPU_NAME)."
  fi
else
  info "Nenhuma GPU dedicada detectada para regras udev específicas."
fi

# ─────────────────────────────────────────
# PASSO 9 — I/O Schedulers
# ─────────────────────────────────────────
step "Configurando I/O Schedulers (NVMe, SSD e HDD)..."
if ! $DRY_RUN; then
  for nvme in /sys/block/nvme*/queue/scheduler; do
    [ -w "$nvme" ] && echo "none" > "$nvme" 2>/dev/null || true
  done
  for hdd in /sys/block/sd*/queue/scheduler; do
    [ -w "$hdd" ] && echo "bfq" > "$hdd" 2>/dev/null || true
  done
fi

IO_UDEV='# NVMe — fila interna de alta velocidade (sem scheduler)
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# HDDs rotativos — BFQ para justiça e fluidez sob carga
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# SSDs SATA — none
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
'
write_file "/etc/udev/rules.d/60-ioscheduler.rules" "$IO_UDEV"
log "I/O schedulers persistidos via udev."

# ─────────────────────────────────────────
# PASSO 10 — Otimização de Serviços em Background
# ─────────────────────────────────────────
step "Ajustando serviços em background..."
for svc in bluetooth ModemManager avahi-daemon; do
  if systemctl is-enabled "$svc" &>/dev/null; then
    run_cmd systemctl disable --now "$svc" 2>/dev/null || true
    warn "Serviço desativado para economia de recursos: $svc"
  fi
done
log "Serviços ajustados."

# ─────────────────────────────────────────
# PASSO 11 — Backup das Configurações
# ─────────────────────────────────────────
step "Salvando snapshot de backup das configurações..."
CFG_BACKUP="$KERNEL_DIR/backup/config"
if ! $DRY_RUN; then
  mkdir -p "$CFG_BACKUP"
  for f in \
    /etc/default/grub \
    /etc/scx_loader/config.toml \
    /etc/sysctl.d/99-covenant-perf.conf \
    /etc/systemd/zram-generator.conf \
    /etc/tmpfiles.d/cpu-governor.conf \
    /etc/udev/rules.d/60-ioscheduler.rules \
    /etc/udev/rules.d/61-amdgpu-performance.rules \
    /etc/covenant/rollback.sh; do
    [ -f "$f" ] && cp "$f" "$CFG_BACKUP/" || true
  done
  chown -R "$REAL_USER:$REAL_USER" "$KERNEL_DIR" 2>/dev/null || true
fi
log "Configs salvas em $CFG_BACKUP."

# ─── Instalação Opcional de Tema GRUB ────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if $INSTALL_THEME; then
  if [ -f "$SCRIPT_DIR/themes/grub/install-grub-theme.sh" ]; then
    info "Instalando tema GRUB Covenant..."
    run_cmd bash "$SCRIPT_DIR/themes/grub/install-grub-theme.sh"
  fi
fi

# ─────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ⚡ Covenant-CachyOS — Setup Concluído com Sucesso! ⚡${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Hardware Tunado:${NC}"
echo -e "  ${DIM}CPU:${NC}       $CPU_MODEL ($TOTAL_CPUS threads, $NUMA_NODES nó(s) NUMA)"
echo -e "  ${DIM}Scheduler:${NC} $CHOSEN_SCHED (modo $CHOSEN_MODE)"
echo -e "  ${DIM}Governor:${NC}  performance (runtime + tmpfiles.d)"
echo -e "  ${DIM}Zram:${NC}      $ZRAM_SIZE ($ZRAM_ALGO, swappiness=100)"
echo -e "  ${DIM}Boot:${NC}      Covenant-CachyOS (GRUB_DISTRIBUTOR)"
echo -e "  ${DIM}Rollback:${NC}  sudo $ROLLBACK_SCRIPT"
echo ""
if [ "$NUMA_NODES" -gt 1 ]; then
  echo -e "  ${YELLOW}${BOLD}Dica para Jogos / Proton (Steam Launch Options):${NC}"
  echo -e "  numactl --cpunodebind=0 --membind=0 gamemoderun %command%"
  echo ""
fi
echo -e "  ${CYAN}Próximos passos:${NC}"
echo -e "  ${CYAN}1.${NC} Compilar kernel custom opcional:  ${BOLD}bash covenant-build.sh${NC}"
echo -e "  ${CYAN}2.${NC} Instalar tema GRUB oficial:       ${BOLD}sudo bash themes/grub/install-grub-theme.sh${NC}"
echo -e "  ${CYAN}3.${NC} Salvar snapshot pós-reboot:       ${BOLD}sudo bash covenant-backup.sh${NC}"
echo -e "  ${BOLD}Para aplicar todas as alterações:   sudo reboot${NC}"
echo ""
