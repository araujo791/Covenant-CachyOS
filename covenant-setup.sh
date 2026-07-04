#!/bin/bash
# ============================================================
#   Covenant-CachyOS — Setup Script
#   Aplica as otimizações de sistema (base) sobre o CachyOS.
#   NÃO compila o kernel custom — para isso, use covenant-build.sh.
#
#   Hardware: 2x Intel Xeon E5-2680 v4 (dual socket NUMA)
#   NUMA Node 0: CPUs 0-13, 28-41 | Node 1: CPUs 14-27, 42-55
#   Storage: NVMe0 953GB + NVMe1 465GB (ambos no node 0)
#   GPU: AMD Radeon RX 560
#
#   Uso:          sudo bash covenant-setup.sh
#   Após reboot:  sudo bash covenant-backup.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

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
echo -e "                    CachyOS System Setup${NC}"
echo ""

[ "$EUID" -eq 0 ] || err "Execute com sudo: sudo bash covenant-setup.sh"

REAL_USER=$(logname)
KERNAL_DIR="/home/$REAL_USER/Kernal"
STEPS=11

# ─────────────────────────────────────────
# PASSO 0 — Backup dos arquivos originais (antes de qualquer modificação)
# ─────────────────────────────────────────
info "Passo 0/$STEPS — Preservando originais para rollback..."
[ -f /etc/default/grub ] && [ ! -f /etc/default/grub.covenant-orig ] \
  && cp /etc/default/grub /etc/default/grub.covenant-orig \
  && log "Original salvo: /etc/default/grub.covenant-orig"

# ─────────────────────────────────────────
# PASSO 1 — Kernel base (fallback, boota mesmo sem o custom)
# ─────────────────────────────────────────
info "Passo 1/$STEPS — Garantindo kernel base linux-cachyos (BORE+EEVDF)..."
pacman -S --needed --noconfirm \
  cachyos-v3/linux-cachyos \
  cachyos-v3/linux-cachyos-headers
log "Kernel base presente."

# ─────────────────────────────────────────
# PASSO 2 — SCX Scheduler (NUMA-aware)
# ─────────────────────────────────────────
info "Passo 2/$STEPS — Configurando scx_loader com scx_rusty..."
pacman -S --needed --noconfirm scx-scheds

mkdir -p /etc/scx_loader
cat > /etc/scx_loader/config.toml <<'EOF'
default_sched = "scx_rusty"
default_mode = "Auto"
EOF

systemctl enable --now scx_loader
log "scx_rusty ativado via scx_loader."

# ─────────────────────────────────────────
# PASSO 3 — Parâmetros de boot + nome no GRUB
# ─────────────────────────────────────────
info "Passo 3/$STEPS — Configurando GRUB (cmdline NUMA + nome Covenant)..."

CMDLINE="quiet loglevel=3 nowatchdog mitigations=off numa_balancing=1 nohz_full=1-13,28-41 rcu_nocbs=1-13,28-41 irqaffinity=0,14"

if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
  sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"|" /etc/default/grub
else
  echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"" >> /etc/default/grub
fi

# Nome nos menus do GRUB — sobrevive a grub-mkconfig e a updates de kernel,
# tornando desnecessário qualquer sed em grub.cfg ou hook do pacman.
if grep -q '^GRUB_DISTRIBUTOR=' /etc/default/grub; then
  sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="Covenant-CachyOS"|' /etc/default/grub
else
  echo 'GRUB_DISTRIBUTOR="Covenant-CachyOS"' >> /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg
log "GRUB atualizado (cmdline + GRUB_DISTRIBUTOR=Covenant-CachyOS)."

# ─────────────────────────────────────────
# PASSO 4 — sysctl tuning
# ─────────────────────────────────────────
info "Passo 4/$STEPS — Aplicando tunings de kernel (sysctl)..."
cat > /etc/sysctl.d/99-covenant-perf.conf <<'EOF'
# ── Memória ──────────────────────────────
# swappiness ALTA é o correto com zram: comprimir páginas frias em RAM
# é muito mais barato que descartar page cache. (swappiness baixa é para
# swap em disco.)
vm.swappiness = 100
vm.page-cluster = 0
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.compaction_proactiveness = 20
# THP em 'always' cobre o uso de hugepages para jogos/Proton — sem reservar
# hugepages explícitas (nr_hugepages) que sequestrariam RAM sem uso.

# ── Scheduler ────────────────────────────
kernel.sched_autogroup_enabled = 1
kernel.numa_balancing = 1
# (sched_child_runs_first foi removido do kernel junto com o EEVDF)

# ── Rede ─────────────────────────────────
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
EOF

sysctl --system > /dev/null
log "sysctl aplicado (zram-aware)."

# ─────────────────────────────────────────
# PASSO 5 — Governor performance + IRQ + gamemode
# ─────────────────────────────────────────
info "Passo 5/$STEPS — Governor performance, IRQ e gamemode..."
# Sem power-profiles-daemon: em desktop/servidor ele é redundante e briga
# com o governor fixo. O kernel custom já sobe com 'performance' como default
# (_per_gov=yes); aqui garantimos em runtime + persistência.
pacman -S --needed --noconfirm \
  numactl hwloc cpupower \
  gamemode lib32-gamemode

cpupower frequency-set -g performance >/dev/null 2>&1 || true
systemctl disable --now irqbalance 2>/dev/null || true

cat > /etc/tmpfiles.d/cpu-governor.conf <<'EOF'
w /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor - - - - performance
EOF
log "Governor performance + gamemode prontos."

# ─────────────────────────────────────────
# PASSO 6 — Zram (swap em RAM comprimida)
# ─────────────────────────────────────────
info "Passo 6/$STEPS — Configurando Zram (zstd, ~metade da RAM)..."
pacman -S --needed --noconfirm zram-generator

cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

systemctl daemon-reload
systemctl start systemd-zram-setup@zram0 2>/dev/null || true
log "Zram configurado (zstd)."

# ─────────────────────────────────────────
# PASSO 7 — Ananicy-cpp (auto-prioridade de processos)
# ─────────────────────────────────────────
info "Passo 7/$STEPS — Instalando ananicy-cpp..."
pacman -S --needed --noconfirm ananicy-cpp
systemctl enable --now ananicy-cpp
log "ananicy-cpp ativo."

# ─────────────────────────────────────────
# PASSO 8 — AMD RX 560 em performance
# ─────────────────────────────────────────
info "Passo 8/$STEPS — Fixando AMD RX 560 em performance..."
for card in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
  [ -w "$card" ] && echo "high" > "$card" 2>/dev/null && log "GPU performance: $card" || true
done

# Persiste via udev — escopado ao driver amdgpu (não casa a função de áudio HDMI).
cat > /etc/udev/rules.d/61-amdgpu-performance.rules <<'EOF'
ACTION=="add|change", SUBSYSTEM=="pci", DRIVERS=="amdgpu", ATTR{power_dpm_force_performance_level}="high"
EOF
log "RX 560 fixada em performance."

# ─────────────────────────────────────────
# PASSO 9 — I/O Scheduler
# ─────────────────────────────────────────
info "Passo 9/$STEPS — Configurando I/O schedulers..."
for nvme in /sys/block/nvme*/queue/scheduler; do
  [ -w "$nvme" ] && echo "none" > "$nvme" 2>/dev/null && log "none: $nvme" || true
done
for hdd in /sys/block/sd*/queue/scheduler; do
  [ -w "$hdd" ] && echo "bfq" > "$hdd" 2>/dev/null && log "bfq: $hdd" || true
done

cat > /etc/udev/rules.d/60-ioscheduler.rules <<'EOF'
# NVMe — sem scheduler (fila gerenciada internamente)
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# HDDs rotativos — BFQ
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
# SSDs SATA — none
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
EOF
log "I/O schedulers configurados e persistidos."

# ─────────────────────────────────────────
# PASSO 10 — Desativar serviços desnecessários
# ─────────────────────────────────────────
info "Passo 10/$STEPS — Desativando serviços desnecessários..."
for svc in bluetooth ModemManager avahi-daemon; do
  if systemctl is-enabled "$svc" &>/dev/null; then
    systemctl disable --now "$svc" 2>/dev/null && warn "Desativado: $svc" || true
  fi
done
log "Serviços desnecessários desativados."

# ─────────────────────────────────────────
# PASSO 11 — Snapshot de configs para backup
# ─────────────────────────────────────────
info "Passo 11/$STEPS — Salvando cópias das configs geradas..."
CFG_BACKUP="$KERNAL_DIR/backup/config"
mkdir -p "$CFG_BACKUP"
for f in \
  /etc/default/grub \
  /etc/scx_loader/config.toml \
  /etc/sysctl.d/99-covenant-perf.conf \
  /etc/systemd/zram-generator.conf \
  /etc/tmpfiles.d/cpu-governor.conf \
  /etc/udev/rules.d/60-ioscheduler.rules \
  /etc/udev/rules.d/61-amdgpu-performance.rules; do
  [ -f "$f" ] && cp "$f" "$CFG_BACKUP/" || true
done
chown -R "$REAL_USER:$REAL_USER" "$KERNAL_DIR"
log "Configs copiadas para $CFG_BACKUP"

# ─────────────────────────────────────────
# RESUMO
# ─────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Covenant-CachyOS — setup concluído!${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Kernel base : cachyos-v3/linux-cachyos (BORE+EEVDF)"
echo -e "  Scheduler   : scx_rusty via scx_loader (NUMA-aware)"
echo -e "  Governor    : performance (runtime + tmpfiles)"
echo -e "  Zram        : zstd, ~metade da RAM (swappiness=100)"
echo -e "  GPU         : RX 560 fixada em performance"
echo -e "  I/O         : NVMe=none | HDD=bfq"
echo -e "  Boot        : Covenant-CachyOS (via GRUB_DISTRIBUTOR)"
echo ""
echo -e "${YELLOW}  Steam launch options:${NC}"
echo -e "  numactl --cpunodebind=0 --membind=0 gamemoderun %command%"
echo ""
echo -e "${CYAN}  Opcional — kernel custom: bash covenant-build.sh${NC}"
echo -e "${CYAN}  Após reiniciar:          sudo bash covenant-backup.sh${NC}"
echo -e "${BOLD}  Reinicie: sudo reboot${NC}"
echo ""
