#!/bin/bash
# ============================================================
#   Covenant-CachyOS — Kernel Build Script
#   Compila um kernel derivado do linux-cachyos, otimizado para
#   ESTA máquina (compile na própria Covenant: -march=native = Broadwell-EP).
#
#   Todas as opções são passadas via variáveis de ambiente que o
#   PKGBUILD oficial já expõe — sem editar o .config à mão. Isso mantém
#   BTF/sched_ext ligados (necessário para o scx_rusty) e sobrevive a
#   mudanças upstream no PKGBUILD.
#
#   Uso:   bash covenant-build.sh
#   Tempo: 1-3h (primeira vez) / ~10min (rebuild incremental)
#   uname -r resultante: <versão>-covenant   (ex.: 7.1.2-covenant)
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

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
# Configuração
# ─────────────────────────────────────────
KSUFFIX="covenant"                    # → pkgbase=linux-covenant, uname=<ver>-covenant
BUILD_DIR="$HOME/kernel-build"
PKGBUILD_DIR="$BUILD_DIR/linux-cachyos/linux-cachyos"
BACKUP_DIR="$HOME/Kernal/backup/compiled"
JOBS=$(nproc)

# Opções do kernel (env vars oficiais do PKGBUILD do CachyOS).
# _localmodcfg=yes compila só os módulos que ESTA máquina carrega — corta
# muito o tempo de build. Requer 'modprobed-db' populado ao longo do tempo:
#   pacman -S modprobed-db && modprobed-db store   (repita por alguns dias)
LOCALMODCFG="${LOCALMODCFG:-no}"

export _cpusched="cachyos"            # BORE + EEVDF + sched_ext (mantém BTF p/ scx_rusty)
export _processor_opt=""              # vazio → X86_NATIVE_CPU (=march=native = Broadwell-EP aqui)
export _use_llvm_lto="thin"           # Clang + ThinLTO
export _HZ_ticks="1000"
export _tickrate="full"               # nohz_full
export _preempt="full"
export _hugepage="always"             # THP always
export _per_gov="yes"                 # governor default = performance
export _tcp_bbr3="yes"                # BBRv3 (fornece o módulo 'bbr')
export _build_debug="no"
export _localmodcfg="$LOCALMODCFG"

info "Threads de compilação: $JOBS"
info "Sufixo do kernel     : $KSUFFIX (uname -r → <versão>-$KSUFFIX)"
info "localmodconfig       : $LOCALMODCFG"
echo ""

# ─────────────────────────────────────────
# PASSO 1 — Dependências
# ─────────────────────────────────────────
info "Passo 1/8 — Instalando dependências de compilação..."
sudo pacman -S --needed --noconfirm \
  base-devel bc cpio gettext git \
  libelf pahole perl python \
  tar xz zstd xmlto \
  llvm clang lld
log "Dependências instaladas."

# ─────────────────────────────────────────
# PASSO 2 — Obter/atualizar fonte (idempotente)
# ─────────────────────────────────────────
info "Passo 2/8 — Obtendo PKGBUILD do CachyOS..."
mkdir -p "$BUILD_DIR"
if [ ! -d "$BUILD_DIR/linux-cachyos/.git" ]; then
  git clone --depth=1 https://github.com/CachyOS/linux-cachyos.git "$BUILD_DIR/linux-cachyos"
  log "Repositório clonado."
else
  git -C "$BUILD_DIR/linux-cachyos" checkout -- . 2>/dev/null || true   # descarta seds anteriores
  git -C "$BUILD_DIR/linux-cachyos" pull --ff-only
  log "Repositório atualizado."
fi
cd "$PKGBUILD_DIR"

# ─────────────────────────────────────────
# PASSO 3 — Forçar o sufixo Covenant
# _pkgsuffix governa TANTO pkgbase QUANTO uname (_kernuname). Forçá-lo
# imediatamente antes de 'pkgbase=' cobre os dois de uma vez.
# ─────────────────────────────────────────
info "Passo 3/8 — Aplicando sufixo '$KSUFFIX' ao PKGBUILD..."
if grep -q '^pkgbase="linux-\$_pkgsuffix"' PKGBUILD; then
  sed -i "s|^pkgbase=\"linux-\$_pkgsuffix\"|_pkgsuffix=$KSUFFIX\npkgbase=\"linux-\$_pkgsuffix\"|" PKGBUILD
  log "pkgbase → linux-$KSUFFIX | uname → <versão>-$KSUFFIX"
else
  warn "Layout de pkgbase inesperado no PKGBUILD — seguindo com o padrão do CachyOS."
fi

# ─────────────────────────────────────────
# PASSO 4 — Compilar (Clang + ThinLTO)
# ─────────────────────────────────────────
info "Passo 4/8 — Compilando com $JOBS threads..."
warn "Primeira vez: 1-3h | Rebuild: ~10min"
echo ""
export LLVM=1 LLVM_IAS=1
MAKEFLAGS="-j${JOBS}" makepkg -sf --noconfirm --skippgpcheck
log "Compilação concluída."

# ─────────────────────────────────────────
# PASSO 5 — Localizar pacotes gerados
# ─────────────────────────────────────────
info "Passo 5/8 — Localizando pacotes..."
PKG=$(find . -maxdepth 1 -name "linux-${KSUFFIX}-[0-9]*.pkg.tar.zst" ! -name '*headers*' | sort -V | tail -1)
HDR=$(find . -maxdepth 1 -name "linux-${KSUFFIX}-headers-[0-9]*.pkg.tar.zst" | sort -V | tail -1)
[ -n "$PKG" ] || err "Pacote linux-${KSUFFIX} não encontrado — verifique erros acima."
log "Kernel  : $(basename "$PKG")"
[ -n "$HDR" ] && log "Headers : $(basename "$HDR")"

# ─────────────────────────────────────────
# PASSO 6 — Instalar
# ─────────────────────────────────────────
info "Passo 6/8 — Instalando kernel..."
# shellcheck disable=SC2086
sudo pacman -U --noconfirm "$PKG" ${HDR:+"$HDR"}
log "Kernel instalado."

# ─────────────────────────────────────────
# PASSO 7 — GRUB
# O nome nos menus vem de GRUB_DISTRIBUTOR (definido pelo covenant-setup.sh),
# então basta regenerar — sem sed em grub.cfg.
# ─────────────────────────────────────────
info "Passo 7/8 — Atualizando GRUB..."
sudo grub-mkconfig -o /boot/grub/grub.cfg
log "GRUB atualizado."

# ─────────────────────────────────────────
# PASSO 8 — Backup dos artefatos
# ─────────────────────────────────────────
info "Passo 8/8 — Salvando backup..."
mkdir -p "$BACKUP_DIR"
cp "$PKG" "$BACKUP_DIR/"
[ -n "$HDR" ] && cp "$HDR" "$BACKUP_DIR/"
cp .config "$BACKUP_DIR/kernel-${KSUFFIX}.config" 2>/dev/null || true
log "Backup em: $BACKUP_DIR"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  linux-${KSUFFIX} compilado e instalado!${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  uname -r   : → <versão>-${KSUFFIX} (após reboot)"
echo -e "  CPU        : -march=native (Broadwell-EP)"
echo -e "  Compiler   : Clang + ThinLTO"
echo -e "  Scheduler  : BORE + EEVDF + sched_ext (scx_rusty OK)"
echo -e "  Rede       : BBRv3"
echo ""
echo -e "${CYAN}  Reinstalar sem recompilar:${NC}"
echo -e "  sudo pacman -U $BACKUP_DIR/linux-${KSUFFIX}-*.pkg.tar.zst"
echo ""
echo -e "${BOLD}  Reinicie: sudo reboot${NC}"
echo ""
