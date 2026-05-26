#!/bin/bash
# ============================================================
#   Covenant-CachyOS — Backup Script (pós-reboot)
#   Execute APÓS reiniciar com o novo kernel carregado
#
#   Uso: sudo bash covenant-backup.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

# Verifica root
if [ "$EUID" -ne 0 ]; then
  err "Execute com sudo: sudo bash covenant-backup.sh"
fi

REAL_USER=$(logname)
BACKUP_DIR="/home/$REAL_USER/Kernal/backup"
BOOT_BACKUP="$BACKUP_DIR/boot"
PKG_BACKUP="$BACKUP_DIR/pkgs"
CFG_BACKUP="$BACKUP_DIR/config"
DATE=$(date +%Y-%m-%d_%H-%M)

mkdir -p "$BOOT_BACKUP" "$PKG_BACKUP" "$CFG_BACKUP"

# ─────────────────────────────────────────
# Verifica kernel atual
# ─────────────────────────────────────────
KERNEL_RUNNING=$(uname -r)
info "Kernel rodando: $KERNEL_RUNNING"

if [[ "$KERNEL_RUNNING" != *"cachyos"* ]]; then
  warn "Kernel atual não parece ser o linux-cachyos!"
  warn "Reinicie com o Covenant-CachyOS selecionado no GRUB antes de rodar este script."
  read -p "Continuar mesmo assim? [s/N] " confirm
  [[ "$confirm" =~ ^[sS]$ ]] || exit 1
fi

# ─────────────────────────────────────────
# BACKUP 1 — Arquivos de boot
# ─────────────────────────────────────────
info "Salvando arquivos de boot..."

for f in \
  /boot/vmlinuz-linux-cachyos \
  /boot/initramfs-linux-cachyos.img \
  /boot/initramfs-linux-cachyos-fallback.img; do
  if [ -f "$f" ]; then
    cp "$f" "$BOOT_BACKUP/"
    log "Salvo: $(basename $f)"
  else
    warn "Não encontrado: $f"
  fi
done

# ─────────────────────────────────────────
# BACKUP 2 — Pacotes .pkg.tar.zst
# ─────────────────────────────────────────
info "Salvando pacotes do cache pacman..."

for pkg in linux-cachyos linux-cachyos-headers scx-scheds \
           numactl hwloc cpupower gamemode lib32-gamemode power-profiles-daemon; do
  found=$(find /var/cache/pacman/pkg/ -name "${pkg}-[0-9]*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1)
  if [ -n "$found" ]; then
    cp "$found" "$PKG_BACKUP/"
    log "Salvo: $(basename $found)"
  else
    warn "Não encontrado no cache: $pkg"
  fi
done

# ─────────────────────────────────────────
# BACKUP 3 — Configurações do sistema
# ─────────────────────────────────────────
info "Salvando configurações..."

cp /etc/default/grub              "$CFG_BACKUP/grub.conf.bak"          && log "grub.conf"
cp /boot/grub/grub.cfg            "$CFG_BACKUP/grub.cfg.bak"           && log "grub.cfg"
cp /etc/scx_loader/config.toml    "$CFG_BACKUP/scx_loader.toml.bak"    && log "scx_loader.toml"
cp /etc/sysctl.d/99-covenant-perf.conf "$CFG_BACKUP/"                  && log "sysctl 99-covenant-perf.conf"
cp /etc/tmpfiles.d/cpu-governor.conf   "$CFG_BACKUP/" 2>/dev/null      && log "cpu-governor.conf" || true
cp /etc/pacman.d/hooks/covenant-grub.hook "$CFG_BACKUP/" 2>/dev/null   && log "covenant-grub.hook" || true

# ─────────────────────────────────────────
# BACKUP 4 — Snapshot do estado atual
# ─────────────────────────────────────────
info "Salvando snapshot do estado do sistema..."

{
  echo "=== Covenant-CachyOS Snapshot — $DATE ==="
  echo ""
  echo "--- Kernel ---"
  uname -r
  echo ""
  echo "--- SCX Scheduler ---"
  systemctl status scx_loader --no-pager -l 2>/dev/null || echo "scx_loader não ativo"
  echo ""
  echo "--- CPU Governor ---"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "n/a"
  echo ""
  echo "--- NUMA ---"
  numactl --hardware 2>/dev/null || echo "numactl não instalado"
  echo ""
  echo "--- Hugepages ---"
  grep HugePages /proc/meminfo
  echo ""
  echo "--- Pacotes instalados ---"
  pacman -Q linux-cachyos linux-cachyos-headers scx-scheds \
            numactl hwloc cpupower gamemode power-profiles-daemon 2>/dev/null
} > "$CFG_BACKUP/snapshot_$DATE.txt"

log "Snapshot salvo: snapshot_$DATE.txt"

# ─────────────────────────────────────────
# Ajusta permissões
# ─────────────────────────────────────────
chown -R "$REAL_USER:$REAL_USER" "/home/$REAL_USER/Kernal"

# ─────────────────────────────────────────
# RESUMO
# ─────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Backup completo!${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  $BOOT_BACKUP/     → vmlinuz + initramfs"
echo -e "  $PKG_BACKUP/      → pacotes .pkg.tar.zst"
echo -e "  $CFG_BACKUP/      → configs + snapshot"
echo ""
echo -e "${CYAN}  Para reinstalar em qualquer momento:${NC}"
echo -e "  sudo pacman -U $PKG_BACKUP/linux-cachyos-*.pkg.tar.zst \\"
echo -e "               $PKG_BACKUP/linux-cachyos-headers-*.pkg.tar.zst"
echo ""
echo -e "${CYAN}  Para restaurar configs:${NC}"
echo -e "  sudo cp $CFG_BACKUP/grub.conf.bak /etc/default/grub"
echo -e "  sudo cp $CFG_BACKUP/scx_loader.toml.bak /etc/scx_loader/config.toml"
echo -e "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
