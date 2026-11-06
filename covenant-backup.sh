#!/usr/bin/env bash
# ============================================================
#   ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗ 
#   ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗
#   ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝
#   ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝ 
#   ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║     
#    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     
#             Covenant-CachyOS — System Backup
# ============================================================
#   Salva o estado do sistema pós-reboot: binários de boot,
#   pacotes do cache pacman, arquivos de configuração e
#   um snapshot detalhado das métricas de performance.
#
#   Uso: sudo bash covenant-backup.sh
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

print_banner() {
  echo -e "${GOLD}${BOLD}"
  cat << 'EOF'
  ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗ 
  ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗
  ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝
  ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝ 
  ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║     
   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     
EOF
  echo -e "${CYAN}            ⚡ Covenant-CachyOS State Backup ⚡${NC}"
  echo -e "${DIM}             By Anderson Araujo  ·  MIT License${NC}"
  echo ""
}

print_banner

[ "$EUID" -eq 0 ] || err "Execute com privilégios de root: sudo bash covenant-backup.sh"

# ─── Detecção Segura de Usuário ──────────────────────────────
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
  mv "$USER_HOME/Kernal" "$KERNEL_DIR"
  warn "Migrado diretório histórico: ~/Kernal → ~/Kernel"
fi

BACKUP_DIR="$KERNEL_DIR/backup"
BOOT_BACKUP="$BACKUP_DIR/boot"
PKG_BACKUP="$BACKUP_DIR/pkgs"
CFG_BACKUP="$BACKUP_DIR/config"
DATE=$(date +%Y-%m-%d_%H-%M)

mkdir -p "$BOOT_BACKUP" "$PKG_BACKUP" "$CFG_BACKUP"

# ─── Detecção do Kernel em Execução ──────────────────────────
KERNEL_RUNNING=$(uname -r)
info "Kernel em execução: ${BOLD}$KERNEL_RUNNING${NC}"

# Tenta encontrar qual pacote é dono do kernel ativo
KPKG=""
for base in linux-covenant linux-cachyos linux-cachyos-bore linux-cachyos-eevdf linux; do
  if [ -f "/boot/vmlinuz-$base" ] && pacman -Q "$base" &>/dev/null; then
    KPKG="$base"
    break
  fi
done

# Fallback pelo uname
if [ -z "$KPKG" ]; then
  if [[ "$KERNEL_RUNNING" =~ covenant ]]; then
    KPKG="linux-covenant"
  elif [[ "$KERNEL_RUNNING" =~ cachyos ]]; then
    KPKG="linux-cachyos"
  else
    KPKG="linux"
  fi
fi
info "Pacote identificado: ${BOLD}$KPKG${NC}"

# ─────────────────────────────────────────
# SEÇÃO 1 — Boot (vmlinuz + initramfs)
# ─────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}[1/4]${NC} ${BOLD}Salvando arquivos de boot...${NC}"
BOOT_FILES=(
  "/boot/vmlinuz-$KPKG"
  "/boot/initramfs-$KPKG.img"
  "/boot/initramfs-$KPKG-fallback.img"
)
for f in "${BOOT_FILES[@]}"; do
  if [ -f "$f" ]; then
    cp "$f" "$BOOT_BACKUP/"
    log "Salvo: $(basename "$f")"
  else
    warn "Não encontrado em /boot: $f"
  fi
done

# ─────────────────────────────────────────
# SEÇÃO 2 — Pacotes do Cache Pacman
# ─────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}[2/4]${NC} ${BOLD}Salvando pacotes do cache pacman...${NC}"
PKGS_TO_BACKUP=(
  "$KPKG"
  "${KPKG}-headers"
  scx-scheds
  numactl
  hwloc
  cpupower
  gamemode
  lib32-gamemode
  zram-generator
  ananicy-cpp
)

# Se houver pacotes compilados em backup/compiled, inclui
COMPILED_DIR="$BACKUP_DIR/compiled"
if [ -d "$COMPILED_DIR" ]; then
  find "$COMPILED_DIR" -name "${KPKG}-*.pkg.tar.zst" -exec cp {} "$PKG_BACKUP/" \; 2>/dev/null || true
fi

for pkg in "${PKGS_TO_BACKUP[@]}"; do
  found=$(find /var/cache/pacman/pkg/ -name "${pkg}-[0-9]*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1)
  if [ -n "$found" ]; then
    cp "$found" "$PKG_BACKUP/"
    log "Salvo pacote: $(basename "$found")"
  else
    warn "Pacote não encontrado no cache do pacman: $pkg"
  fi
done

# ─────────────────────────────────────────
# SEÇÃO 3 — Arquivos de Configuração
# ─────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}[3/4]${NC} ${BOLD}Salvando cópias das configurações...${NC}"
copy_cfg() {
  local src="$1"
  local dest_name="$2"
  if [ -f "$src" ]; then
    cp "$src" "$CFG_BACKUP/$dest_name"
    log "Config salva: $dest_name"
  else
    warn "Arquivo ausente para backup: $src"
  fi
}

copy_cfg /etc/default/grub                        grub.conf.bak
copy_cfg /boot/grub/grub.cfg                       grub.cfg.bak
copy_cfg /etc/scx_loader/config.toml               scx_loader.toml.bak
copy_cfg /etc/sysctl.d/99-covenant-perf.conf       99-covenant-perf.conf
copy_cfg /etc/tmpfiles.d/cpu-governor.conf         cpu-governor.conf
copy_cfg /etc/systemd/zram-generator.conf          zram-generator.conf
copy_cfg /etc/udev/rules.d/60-ioscheduler.rules    60-ioscheduler.rules
copy_cfg /etc/udev/rules.d/61-amdgpu-performance.rules 61-amdgpu-performance.rules
copy_cfg /etc/covenant/rollback.sh                 covenant-rollback.sh

# ─────────────────────────────────────────
# SEÇÃO 4 — Snapshot Detalhado do Sistema
# ─────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}[4/4]${NC} ${BOLD}Gerando snapshot de telemetria e estado...${NC}"
SNAPSHOT_FILE="$CFG_BACKUP/snapshot_$DATE.txt"

{
  echo "═══════════════════════════════════════════════════════════════"
  echo "  Covenant-CachyOS — Snapshot de Estado do Sistema"
  echo "  Data: $DATE | Usuário: $REAL_USER"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  
  echo "── Kernel e Linha de Boot ─────────────────────────────────────"
  echo "uname -r: $(uname -r)"
  echo "cmdline : $(cat /proc/cmdline 2>/dev/null || echo 'n/a')"
  echo ""
  
  echo "── Scheduler sched_ext (scx) ──────────────────────────────────"
  echo "sched_ext/state: $(cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'não exposto')"
  echo "scx_loader     : $(systemctl is-active scx_loader 2>/dev/null || echo 'inativo')"
  echo ""
  
  echo "── CPU & Frequency Governor ───────────────────────────────────"
  echo "Modelo  : $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'n/a')"
  echo "Threads : $(nproc --all 2>/dev/null || echo 'n/a')"
  echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'n/a')"
  echo ""
  
  echo "── NUMA Topology ──────────────────────────────────────────────"
  numactl --hardware 2>/dev/null || echo "numactl não disponível"
  echo ""
  
  echo "── Memória e ZRAM ─────────────────────────────────────────────"
  free -h
  echo ""
  zramctl 2>/dev/null || echo "sem zram ativo"
  echo ""
  
  echo "── Rede (TCP & Qdisc) ─────────────────────────────────────────"
  echo "congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'n/a')"
  echo "default_qdisc     : $(sysctl -n net.core.default_qdisc 2>/dev/null || echo 'n/a')"
  echo ""
  
  echo "── I/O Schedulers ─────────────────────────────────────────────"
  for dev in /sys/block/*/queue/scheduler; do
    if [ -f "$dev" ]; then
      bname=$(echo "$dev" | cut -d/ -f4)
      echo "$bname: $(cat "$dev")"
    fi
  done
  echo ""
  
  echo "── GPUs & Drivers ─────────────────────────────────────────────"
  lspci 2>/dev/null | grep -i 'vga\|3d\|display' || echo "nenhuma GPU listada"
  echo ""
  
  echo "── Pacotes Covenant / Otimização ──────────────────────────────"
  pacman -Q "$KPKG" "${KPKG}-headers" scx-scheds numactl gamemode ananicy-cpp zram-generator 2>/dev/null || true
  
} > "$SNAPSHOT_FILE"

log "Snapshot salvo: snapshot_$DATE.txt"

# Ajustar permissões
chown -R "$REAL_USER:$REAL_USER" "$KERNEL_DIR" 2>/dev/null || true

# ─────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ⚡ Backup Covenant Concluído com Sucesso! ⚡${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Destinos:${NC}"
echo -e "  ${DIM}Boot     :${NC} $BOOT_BACKUP/  (vmlinuz + initramfs)"
echo -e "  ${DIM}Pacotes  :${NC} $PKG_BACKUP/   (pacotes .pkg.tar.zst)"
echo -e "  ${DIM}Configs  :${NC} $CFG_BACKUP/   (arquivos de configuração)"
echo -e "  ${DIM}Snapshot :${NC} $SNAPSHOT_FILE"
echo ""
echo -e "  ${CYAN}Para reinstalar o kernel arquivado futuramente:${NC}"
echo -e "  sudo pacman -U $PKG_BACKUP/${KPKG}-*.pkg.tar.zst"
echo ""
