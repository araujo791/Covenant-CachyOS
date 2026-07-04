#!/bin/bash
# ============================================================
#   Covenant-CachyOS — Backup Script (pós-reboot)
#   Detecta automaticamente o kernel em uso (linux-covenant OU
#   linux-cachyos) e salva vmlinuz/initramfs/pacotes/configs.
#
#   Uso: sudo bash covenant-backup.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[→]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo -e "${BOLD}"
echo "  ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗ "
echo "  ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗"
echo "  ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝"
echo "  ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝ "
echo "  ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║     "
echo "   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
echo -e "              Covenant-CachyOS Backup${NC}"
echo ""

[ "$EUID" -eq 0 ] || err "Execute com sudo: sudo bash covenant-backup.sh"

REAL_USER=$(logname)
BACKUP_DIR="/home/$REAL_USER/Kernal/backup"
BOOT_BACKUP="$BACKUP_DIR/boot"
PKG_BACKUP="$BACKUP_DIR/pkgs"
CFG_BACKUP="$BACKUP_DIR/config"
DATE=$(date +%Y-%m-%d_%H-%M)
mkdir -p "$BOOT_BACKUP" "$PKG_BACKUP" "$CFG_BACKUP"

# ─────────────────────────────────────────
# Detectar o pacote do kernel em uso
# ─────────────────────────────────────────
KERNEL_RUNNING=$(uname -r)
info "Kernel rodando: $KERNEL_RUNNING"

# vmlinuz-<pkgbase> — descobre qual pkgbase é dono do kernel atual.
KPKG=""
for base in linux-covenant linux-cachyos; do
  if [ -f "/boot/vmlinuz-$base" ] && pacman -Q "$base" &>/dev/null; then
    KPKG="$base"; break
  fi
done
[ -n "$KPKG" ] || KPKG="linux-cachyos"
info "Pacote do kernel detectado: $KPKG"

# ─────────────────────────────────────────
# BACKUP 1 — boot (vmlinuz + initramfs do kernel correto)
# ─────────────────────────────────────────
info "Salvando arquivos de boot..."
for f in \
  "/boot/vmlinuz-$KPKG" \
  "/boot/initramfs-$KPKG.img" \
  "/boot/initramfs-$KPKG-fallback.img"; do
  if [ -f "$f" ]; then cp "$f" "$BOOT_BACKUP/" && log "Salvo: $(basename "$f")"
  else warn "Não encontrado: $f"; fi
done

# ─────────────────────────────────────────
# BACKUP 2 — pacotes do cache pacman
# ─────────────────────────────────────────
info "Salvando pacotes do cache..."
PKGS=("$KPKG" "$KPKG-headers" scx-scheds numactl hwloc cpupower
      gamemode lib32-gamemode zram-generator ananicy-cpp)
# se o kernel custom está em uso, guarda também o pacote compilado
COMPILED_DIR="/home/$REAL_USER/Kernal/backup/compiled"
if [ -d "$COMPILED_DIR" ]; then
  find "$COMPILED_DIR" -name "${KPKG}-*.pkg.tar.zst" -exec cp {} "$PKG_BACKUP/" \; 2>/dev/null || true
fi
for pkg in "${PKGS[@]}"; do
  found=$(find /var/cache/pacman/pkg/ -name "${pkg}-[0-9]*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1)
  if [ -n "$found" ]; then cp "$found" "$PKG_BACKUP/" && log "Salvo: $(basename "$found")"
  else warn "Não no cache: $pkg"; fi
done

# ─────────────────────────────────────────
# BACKUP 3 — configs (com guardas; não aborta se faltar algo)
# ─────────────────────────────────────────
info "Salvando configurações..."
copy_cfg() { [ -f "$1" ] && cp "$1" "$CFG_BACKUP/$2" && log "$2" || warn "faltando: $1"; }
copy_cfg /etc/default/grub                        grub.conf.bak
copy_cfg /boot/grub/grub.cfg                       grub.cfg.bak
copy_cfg /etc/scx_loader/config.toml               scx_loader.toml.bak
copy_cfg /etc/sysctl.d/99-covenant-perf.conf       99-covenant-perf.conf
copy_cfg /etc/tmpfiles.d/cpu-governor.conf         cpu-governor.conf
copy_cfg /etc/udev/rules.d/60-ioscheduler.rules    60-ioscheduler.rules
copy_cfg /etc/udev/rules.d/61-amdgpu-performance.rules 61-amdgpu-performance.rules

# ─────────────────────────────────────────
# BACKUP 4 — snapshot do estado
# ─────────────────────────────────────────
info "Gerando snapshot do estado..."
{
  echo "=== Covenant-CachyOS Snapshot — $DATE ==="
  echo; echo "--- Kernel ---"; uname -r
  echo; echo "--- sched_ext (scx) ---"
  cat /sys/kernel/sched_ext/state 2>/dev/null || echo "sched_ext não exposto"
  systemctl is-active scx_loader 2>/dev/null || true
  echo; echo "--- Governor ---"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo n/a
  echo; echo "--- NUMA ---"; numactl --hardware 2>/dev/null || echo "numactl ausente"
  echo; echo "--- Zram ---"; zramctl 2>/dev/null || echo "sem zram"
  echo; echo "--- Congestion control ---"
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true
  echo; echo "--- Pacotes ---"
  pacman -Q "$KPKG" "$KPKG-headers" scx-scheds numactl gamemode 2>/dev/null || true
} > "$CFG_BACKUP/snapshot_$DATE.txt"
log "Snapshot: snapshot_$DATE.txt"

chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/Kernal"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Backup completo ($KPKG)!${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  $BOOT_BACKUP/  → vmlinuz + initramfs"
echo -e "  $PKG_BACKUP/   → pacotes .pkg.tar.zst"
echo -e "  $CFG_BACKUP/   → configs + snapshot"
echo ""
echo -e "${CYAN}  Reinstalar o kernel:${NC}"
echo -e "  sudo pacman -U $PKG_BACKUP/${KPKG}-*.pkg.tar.zst"
echo ""
