#!/bin/bash
# ============================================================
#   Covenant-CachyOS — Kernel Setup Script v2
#   Hardware: 2x Intel Xeon E5-2680 v4 (dual socket NUMA)
#   NUMA Node 0: CPUs 0-13, 28-41 | Node 1: CPUs 14-27, 42-55
#   Storage: NVMe0 953GB + NVMe1 465GB (ambos no node 0)
#   GPU: AMD Radeon RX 560
#
#   Uso: sudo bash covenant-cachyos.sh
#   Após reboot: sudo bash covenant-backup.sh
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
echo "  ██████╗ ██████╗ ██╗   ██╗███████╗███╗   ██╗ █████╗ ███╗   ██╗████████╗"
echo "  ██╔════╝██╔═══██╗██║   ██║██╔════╝████╗  ██║██╔══██╗████╗  ██║╚══██╔══╝"
echo "  ██║     ██║   ██║██║   ██║█████╗  ██╔██╗ ██║███████║██╔██╗ ██║   ██║   "
echo "  ██║     ██║   ██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██╔══██║██║╚██╗██║   ██║   "
echo "  ╚██████╗╚██████╔╝ ╚████╔╝ ███████╗██║ ╚████║██║  ██║██║ ╚████║   ██║   "
echo "   ╚═════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝  "
echo -e "                    CachyOS Kernel Setup v2${NC}"
echo ""

# Verifica root
if [ "$EUID" -ne 0 ]; then
  err "Execute com sudo: sudo bash covenant-cachyos.sh"
fi

REAL_USER=$(logname)
KERNAL_DIR="/home/$REAL_USER/Kernal"

# ─────────────────────────────────────────
# PASSO 1 — Instalar kernel
# ─────────────────────────────────────────
info "Passo 1/12 — Instalando linux-cachyos v3 (BORE+EEVDF)..."
pacman -S --noconfirm \
  cachyos-v3/linux-cachyos \
  cachyos-v3/linux-cachyos-headers
log "Kernel instalado."

# ─────────────────────────────────────────
# PASSO 2 — SCX Scheduler (NUMA-aware)
# ─────────────────────────────────────────
info "Passo 2/12 — Configurando scx_loader com scx_rusty..."
pacman -S --noconfirm scx-scheds

mkdir -p /etc/scx_loader
tee /etc/scx_loader/config.toml <<'EOF'
default_sched = "scx_rusty"
default_mode = "Auto"
EOF

systemctl enable --now scx_loader
systemctl restart scx_loader
log "scx_rusty ativado via scx_loader."

# ─────────────────────────────────────────
# PASSO 3 — Parâmetros de boot (GRUB)
# ─────────────────────────────────────────
info "Passo 3/12 — Configurando GRUB para dual-socket NUMA..."
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 nowatchdog mitigations=off numa_balancing=1 nohz_full=1-13,28-41 rcu_nocbs=1-13,28-41 irqaffinity=0,14"/' \
  /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
log "GRUB atualizado."

# ─────────────────────────────────────────
# PASSO 4 — sysctl tuning
# ─────────────────────────────────────────
info "Passo 4/12 — Aplicando tunnings de kernel..."
tee /etc/sysctl.d/99-covenant-perf.conf <<'EOF'
# Memória
vm.nr_hugepages = 1024
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.compaction_proactiveness = 20

# Scheduler
kernel.sched_autogroup_enabled = 1
kernel.sched_child_runs_first = 0
kernel.numa_balancing = 1

# Rede
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF

sysctl --system > /dev/null
log "sysctl aplicado."

# ─────────────────────────────────────────
# PASSO 5 — Energia + IRQ + Gamemode
# ─────────────────────────────────────────
info "Passo 5/12 — Configurando governor, IRQ e gamemode..."
pacman -S --noconfirm \
  numactl hwloc cpupower \
  gamemode lib32-gamemode \
  power-profiles-daemon

cpupower frequency-set -g performance

systemctl enable --now power-profiles-daemon
powerprofilesctl set performance

systemctl disable --now irqbalance 2>/dev/null || true

tee /etc/tmpfiles.d/cpu-governor.conf <<'EOF'
w /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor - - - - performance
EOF

log "Governor performance + gamemode prontos."

# ─────────────────────────────────────────
# PASSO 6 — Zram (swap em RAM comprimida)
# ─────────────────────────────────────────
info "Passo 6/12 — Configurando Zram (swap em RAM com zstd)..."
pacman -S --noconfirm zram-generator

tee /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

systemctl daemon-reload
systemctl start systemd-zram-setup@zram0 2>/dev/null || true
systemctl enable systemd-zram-setup@zram0 2>/dev/null || true
log "Zram configurado (zstd, 32GB)."

# ─────────────────────────────────────────
# PASSO 7 — Ananicy-cpp (prioridade de processos)
# ─────────────────────────────────────────
info "Passo 7/12 — Instalando ananicy-cpp (auto-prioridade de processos)..."
pacman -S --noconfirm ananicy-cpp
systemctl enable --now ananicy-cpp
log "ananicy-cpp ativo — jogos recebem prioridade automática."

# ─────────────────────────────────────────
# PASSO 8 — AMD GPU RX 560 performance
# ─────────────────────────────────────────
info "Passo 8/12 — Configurando AMD RX 560 para performance..."

# Aplica imediatamente
for card in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
  echo "high" > "$card" 2>/dev/null && log "GPU performance: $card" || true
done

# Persiste no boot via udev
tee /etc/udev/rules.d/61-amdgpu-performance.rules <<'EOF'
ACTION=="add|change", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{power_dpm_force_performance_level}="high"
EOF

log "RX 560 fixada em modo performance."

# ─────────────────────────────────────────
# PASSO 9 — I/O Scheduler otimizado
# ─────────────────────────────────────────
info "Passo 9/12 — Configurando I/O scheduler..."

# NVMe — none (melhor para SSDs com fila interna)
for nvme in /sys/block/nvme*/queue/scheduler; do
  echo "none" > "$nvme" 2>/dev/null && log "I/O scheduler 'none': $nvme" || true
done

# HDDs — bfq (melhor para discos rotativos)
for hdd in /sys/block/sd*/queue/scheduler; do
  echo "bfq" > "$hdd" 2>/dev/null && log "I/O scheduler 'bfq': $hdd" || true
done

# Persiste via udev
tee /etc/udev/rules.d/60-ioscheduler.rules <<'EOF'
# NVMe — sem scheduler (gerencia internamente)
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# HDDs — BFQ (Budget Fair Queueing)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# SSDs SATA — none
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
EOF

log "I/O schedulers configurados e persistidos."

# ─────────────────────────────────────────
# PASSO 10 — Desativar serviços desnecessários
# ─────────────────────────────────────────
info "Passo 10/12 — Desativando serviços desnecessários..."

SERVICES_DISABLE=(
  "bluetooth"         # desativa se não usar bluetooth
  "ModemManager"      # não tem modem
  "avahi-daemon"      # descoberta de rede local desnecessária
)

for svc in "${SERVICES_DISABLE[@]}"; do
  if systemctl is-enabled "$svc" &>/dev/null; then
    systemctl disable --now "$svc" 2>/dev/null && warn "Desativado: $svc" || true
  fi
done

log "Serviços desnecessários desativados."

# ─────────────────────────────────────────
# PASSO 11 — Nome: Covenant-CachyOS
# ─────────────────────────────────────────
info "Passo 11/12 — Aplicando nome Covenant-CachyOS no GRUB..."

sed -i 's/CachyOS Linux/Covenant-CachyOS/g' /boot/grub/grub.cfg

mkdir -p /etc/pacman.d/hooks
tee /etc/pacman.d/hooks/covenant-grub.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux-cachyos

[Action]
Description = Renaming kernel to Covenant-CachyOS...
When = PostTransaction
Exec = /bin/sed -i 's/CachyOS Linux/Covenant-CachyOS/g' /boot/grub/grub.cfg
EOF

log "Nome aplicado e hook criado."

# ─────────────────────────────────────────
# PASSO 12 — Backup
# ─────────────────────────────────────────
info "Passo 12/12 — Salvando pacotes para backup..."
BACKUP_DIR="$KERNAL_DIR/backup"
mkdir -p "$BACKUP_DIR/pkgs" "$BACKUP_DIR/config"

for pkg in linux-cachyos linux-cachyos-headers scx-scheds \
           numactl hwloc cpupower gamemode lib32-gamemode \
           power-profiles-daemon zram-generator ananicy-cpp; do
  found=$(find /var/cache/pacman/pkg/ -name "${pkg}-[0-9]*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1)
  if [ -n "$found" ]; then
    cp "$found" "$BACKUP_DIR/pkgs/"
    log "Salvo: $(basename $found)"
  else
    warn "Não encontrado no cache: $pkg"
  fi
done

cp /etc/default/grub                    "$BACKUP_DIR/config/grub.conf.bak"
cp /etc/scx_loader/config.toml          "$BACKUP_DIR/config/scx_loader.toml.bak"
cp /etc/sysctl.d/99-covenant-perf.conf  "$BACKUP_DIR/config/"
cp /etc/systemd/zram-generator.conf     "$BACKUP_DIR/config/"
cp /etc/udev/rules.d/60-ioscheduler.rules    "$BACKUP_DIR/config/"
cp /etc/udev/rules.d/61-amdgpu-performance.rules "$BACKUP_DIR/config/"

chown -R "$REAL_USER:$REAL_USER" "$KERNAL_DIR"
log "Backup em: $BACKUP_DIR"

# ─────────────────────────────────────────
# RESUMO FINAL
# ─────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Covenant-CachyOS v2 instalado com sucesso!${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Kernel     : cachyos-v3/linux-cachyos (BORE+EEVDF)"
echo -e "  Scheduler  : scx_rusty via scx_loader (NUMA-aware)"
echo -e "  NUMA       : node 0 = CPUs 0-13,28-41"
echo -e "  Governor   : performance"
echo -e "  Zram       : 32GB zstd (swap em RAM)"
echo -e "  Ananicy    : prioridade automática de processos"
echo -e "  GPU        : RX 560 fixada em performance"
echo -e "  NVMe I/O   : scheduler none"
echo -e "  HDD I/O    : scheduler bfq"
echo -e "  Serviços   : bluetooth/avahi/modem desativados"
echo -e "  Boot       : Covenant-CachyOS"
echo -e "  Backup     : $BACKUP_DIR"
echo ""
echo -e "${YELLOW}  Steam launch options (cole em cada jogo):${NC}"
echo -e "  numactl --cpunodebind=0 --membind=0 gamemoderun %command%"
echo ""
echo -e "${CYAN}  Próximo passo — após reiniciar:${NC}"
echo -e "  sudo bash $KERNAL_DIR/covenant-backup.sh"
echo ""
echo -e "${BOLD}  Reinicie agora: sudo reboot${NC}"
echo ""
