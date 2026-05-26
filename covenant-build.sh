#!/bin/bash
# ============================================================
#   Covenant-CachyOS — Kernel Build Script
#   Compila o kernel do zero otimizado para:
#   - 2x Intel Xeon E5-2680 v4 (Broadwell-EP)
#   - Dual socket NUMA (node 0: CPUs 0-13,28-41)
#   - Gaming / low latency desktop
#
#   Uso: bash covenant-build.sh
#   Tempo estimado: 1-3h (primeira vez) / ~10min (rebuild)
#   Resultado: uname -r → 7.x.x-covenant-cachyos
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
echo "  ██████╗ ██╗   ██╗██╗██╗     ██████╗ "
echo "  ██╔══██╗██║   ██║██║██║     ██╔══██╗"
echo "  ██████╔╝██║   ██║██║██║     ██║  ██║"
echo "  ██╔══██╗██║   ██║██║██║     ██║  ██║"
echo "  ██████╔╝╚██████╔╝██║███████╗██████╔╝"
echo "   ╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝ "
echo -e "         Covenant-CachyOS Kernel Builder${NC}"
echo ""

# ─────────────────────────────────────────
# Configurações
# pkgbase=linux-covenant → pacote se chama linux-covenant
# _localversion="-cachyos" → uname -r: 7.x.x-covenant-cachyos
# ─────────────────────────────────────────
KERNEL_NAME="covenant"
LOCALVERSION="-cachyos"
BUILD_DIR="$HOME/kernel-build"
PKGBUILD_DIR="$BUILD_DIR/linux-cachyos/linux-cachyos"
JOBS=$(nproc)
BACKUP_DIR="$HOME/Kernal/backup/compiled"

info "Usando $JOBS threads para compilação."
info "Resultado final: uname -r → $(uname -r | sed 's/[0-9].*//')x.x-covenant-cachyos"
echo ""

# ─────────────────────────────────────────
# PASSO 1 — Dependências
# ─────────────────────────────────────────
info "Passo 1/9 — Instalando dependências de compilação..."
sudo pacman -S --noconfirm \
  base-devel bc cpio gettext git \
  libelf pahole perl python \
  tar xz zstd xmlto \
  numactl cpupower \
  llvm clang lld
log "Dependências instaladas."

# ─────────────────────────────────────────
# PASSO 2 — Baixar / atualizar fonte
# ─────────────────────────────────────────
info "Passo 2/9 — Obtendo PKGBUILD do CachyOS..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -d "linux-cachyos" ]; then
  git clone --depth=1 https://github.com/CachyOS/linux-cachyos.git
  log "Repositório clonado."
else
  cd linux-cachyos && git pull && cd ..
  log "Repositório atualizado."
fi

cd "$PKGBUILD_DIR"

# ─────────────────────────────────────────
# PASSO 3 — Renomear para Covenant
# pkgbase=linux-covenant
# _localversion="-cachyos"
# → uname -r: 7.x.x-covenant-cachyos ✅
# ─────────────────────────────────────────
info "Passo 3/9 — Aplicando nome Covenant ao PKGBUILD..."

sed -i "s/^pkgbase=.*/pkgbase=linux-${KERNEL_NAME}/" PKGBUILD

if grep -q '_localversion' PKGBUILD; then
  sed -i "s/^_localversion=.*/_localversion=\"${LOCALVERSION}\"/" PKGBUILD
else
  sed -i "/^pkgbase=/a _localversion=\"${LOCALVERSION}\"" PKGBUILD
fi

PKGBASE=$(grep '^pkgbase=' PKGBUILD | cut -d= -f2)
LVER=$(grep '_localversion=' PKGBUILD | head -1 | cut -d= -f2 | tr -d '"')
log "pkgbase      : $PKGBASE"
log "localversion : $LVER"
log "uname -r será: <versão>-covenant-cachyos ✅"

# ─────────────────────────────────────────
# PASSO 4 — Script de config otimizada
# ─────────────────────────────────────────
info "Passo 4/9 — Gerando config otimizada para Xeon E5-2680 v4..."

cat > "$BUILD_DIR/covenant-config.sh" << 'CFGEOF'
#!/bin/bash
# Otimizações aplicadas após make olddefconfig

# Arquitetura Broadwell específica
scripts/config --enable  CONFIG_MBROADWELL
scripts/config --disable CONFIG_GENERIC_CPU
scripts/config --disable CONFIG_MATOM

# Scheduler BORE + EEVDF
scripts/config --enable  CONFIG_SCHED_BORE
scripts/config --enable  CONFIG_SCHED_CLASS_EXT

# Preemption FULL
scripts/config --enable  CONFIG_PREEMPT
scripts/config --disable CONFIG_PREEMPT_VOLUNTARY
scripts/config --disable CONFIG_PREEMPT_NONE

# HZ 1000
scripts/config --set-val CONFIG_HZ 1000
scripts/config --enable  CONFIG_HZ_1000
scripts/config --disable CONFIG_HZ_300
scripts/config --disable CONFIG_HZ_250

# NUMA dual socket
scripts/config --enable CONFIG_NUMA
scripts/config --enable CONFIG_NUMA_BALANCING
scripts/config --enable CONFIG_NUMA_BALANCING_DEFAULT_ENABLED

# Hugepages
scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE
scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS
scripts/config --enable CONFIG_HUGETLBFS

# Compressão zstd
scripts/config --enable  CONFIG_RD_ZSTD
scripts/config --disable CONFIG_RD_GZIP
scripts/config --enable  CONFIG_KERNEL_ZSTD

# LTO Clang Thin
scripts/config --enable  CONFIG_LTO_CLANG_THIN
scripts/config --disable CONFIG_LTO_NONE
scripts/config --disable CONFIG_LTO_CLANG_FULL

# Performance
scripts/config --enable  CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
scripts/config --disable CONFIG_CC_OPTIMIZE_FOR_SIZE

# Desativa debug
scripts/config --disable CONFIG_DEBUG_INFO
scripts/config --disable CONFIG_DEBUG_INFO_BTF
scripts/config --disable CONFIG_DEBUG_INFO_DWARF4
scripts/config --disable CONFIG_DEBUG_INFO_DWARF5
scripts/config --disable CONFIG_SLUB_DEBUG
scripts/config --disable CONFIG_DEBUG_MEMORY_INIT
scripts/config --disable CONFIG_KFENCE
scripts/config --disable CONFIG_PAGE_POISONING
scripts/config --disable CONFIG_FTRACE
scripts/config --disable CONFIG_KPROBES

# IRQ threading
scripts/config --enable CONFIG_IRQ_FORCED_THREADING

# Watchdog desativado
scripts/config --disable CONFIG_LOCKUP_DETECTOR
scripts/config --disable CONFIG_HARDLOCKUP_DETECTOR
scripts/config --disable CONFIG_SOFTLOCKUP_DETECTOR

# RCU otimizado
scripts/config --enable CONFIG_RCU_NOCB_CPU
scripts/config --enable CONFIG_RCU_BOOST

# CPU frequency — performance por padrão
scripts/config --enable  CONFIG_CPU_FREQ_GOV_PERFORMANCE
scripts/config --enable  CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE
scripts/config --disable CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL

# AMD GPU RX 560
scripts/config --enable CONFIG_DRM_AMDGPU
scripts/config --enable CONFIG_DRM_AMDGPU_SI
scripts/config --enable CONFIG_DRM_AMDGPU_CIK

# NVMe
scripts/config --enable CONFIG_BLK_DEV_NVME
scripts/config --enable CONFIG_NVME_MULTIPATH

# Rede BBR + FQ
scripts/config --enable CONFIG_TCP_CONG_BBR
scripts/config --enable CONFIG_NET_SCH_FQ

# Steam / Proton / Wine
scripts/config --enable CONFIG_FUTEX
scripts/config --enable CONFIG_FUTEX_PI

# Memória
scripts/config --enable CONFIG_ZSWAP
scripts/config --enable CONFIG_ZSMALLOC
scripts/config --enable CONFIG_Z3FOLD

echo "[✓] Configurações Covenant aplicadas."
CFGEOF

chmod +x "$BUILD_DIR/covenant-config.sh"
log "Script de config criado."

# ─────────────────────────────────────────
# PASSO 5 — Injeta config no PKGBUILD
# ─────────────────────────────────────────
info "Passo 5/9 — Injetando config no PKGBUILD..."

sed -i '/covenant-config/d' PKGBUILD

if grep -q 'make olddefconfig' PKGBUILD; then
  sed -i "/make olddefconfig/a\\    $BUILD_DIR/covenant-config.sh" PKGBUILD
  log "Config injetada após olddefconfig."
else
  warn "Não encontrou 'make olddefconfig' — rode $BUILD_DIR/covenant-config.sh manualmente."
fi

# ─────────────────────────────────────────
# PASSO 6 — Compilar
# ─────────────────────────────────────────
info "Passo 6/9 — Compilando com $JOBS threads (Clang + ThinLTO)..."
warn "Primeira vez: 1-3h | Rebuild: ~10min"
echo ""

export CC=clang
export CXX=clang++
export LD=ld.lld
export LLVM=1
export LLVM_IAS=1

makepkg -sf --noconfirm \
  MAKEFLAGS="-j${JOBS}" \
  --skippgpcheck

log "Compilação concluída!"

# ─────────────────────────────────────────
# PASSO 7 — Localiza pacotes
# ─────────────────────────────────────────
info "Passo 7/9 — Localizando pacotes compilados..."

PKG=$(ls -1 linux-${KERNEL_NAME}-[0-9]*.pkg.tar.zst 2>/dev/null | grep -v headers | sort -V | tail -1)
HDR=$(ls -1 linux-${KERNEL_NAME}-headers-[0-9]*.pkg.tar.zst 2>/dev/null | sort -V | tail -1)

# Fallback para linux-cachyos caso pkgbase não tenha sido alterado
if [ -z "$PKG" ]; then
  PKG=$(ls -1 linux-cachyos-[0-9]*.pkg.tar.zst 2>/dev/null | grep -v headers | sort -V | tail -1)
  HDR=$(ls -1 linux-cachyos-headers-[0-9]*.pkg.tar.zst 2>/dev/null | sort -V | tail -1)
fi

[ -z "$PKG" ] && err "Pacote não encontrado. Verifique erros acima."
log "Kernel  : $PKG"
[ -n "$HDR" ] && log "Headers : $HDR"

# ─────────────────────────────────────────
# PASSO 8 — Instalar
# ─────────────────────────────────────────
info "Passo 8/9 — Instalando kernel..."
sudo pacman -U --noconfirm "$PKG" ${HDR:+"$HDR"}
log "Kernel instalado."

# ─────────────────────────────────────────
# PASSO 9 — GRUB + Backup
# ─────────────────────────────────────────
info "Passo 9/9 — Atualizando GRUB e salvando backup..."

sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo sed -i 's/CachyOS Linux/Covenant-CachyOS/g' /boot/grub/grub.cfg
log "GRUB: Covenant-CachyOS aplicado."

mkdir -p "$BACKUP_DIR"
cp "$PKG" "$BACKUP_DIR/"
[ -n "$HDR" ] && cp "$HDR" "$BACKUP_DIR/"
cp .config "$BACKUP_DIR/kernel-covenant-cachyos.config" 2>/dev/null || true
log "Backup salvo em: $BACKUP_DIR"

# ─────────────────────────────────────────
# RESUMO
# ─────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Covenant-CachyOS compilado e instalado!${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  uname -r  : → <versão>-covenant-cachyos (após reboot)"
echo -e "  Kernel    : linux-${KERNEL_NAME}${LOCALVERSION}"
echo -e "  CPU alvo  : Broadwell (E5-2680 v4)"
echo -e "  Compiler  : Clang + ThinLTO"
echo -e "  Scheduler : BORE + EEVDF"
echo -e "  HZ        : 1000"
echo -e "  Preempt   : FULL"
echo -e "  NUMA      : habilitado"
echo -e "  Backup    : $BACKUP_DIR"
echo ""
echo -e "${CYAN}  Para reinstalar sem recompilar:${NC}"
echo -e "  sudo pacman -U $BACKUP_DIR/linux-${KERNEL_NAME}-*.pkg.tar.zst"
echo ""
echo -e "${YELLOW}  Steam launch options:${NC}"
echo -e "  numactl --cpunodebind=0 --membind=0 gamemoderun %command%"
echo ""
echo -e "${BOLD}  Reinicie: sudo reboot${NC}"
echo ""
