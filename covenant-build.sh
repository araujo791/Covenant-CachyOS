#!/usr/bin/env bash
# ============================================================
#   ██████╗ ██╗   ██╗██╗██╗     ██████╗ 
#   ██╔══██╗██║   ██║██║██║     ██╔══██╗
#   ██████╔╝██║   ██║██║██║     ██║  ██║
#   ██╔══██╗██║   ██║██║██║     ██║  ██║
#   ██████╔╝╚██████╔╝██║███████╗██████╔╝
#    ╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝ 
#            Covenant-CachyOS — Kernel Builder
# ============================================================
#   Compila um kernel customizado derivado do linux-cachyos,
#   otimizado para a sua máquina (-march=native, ThinLTO, sched_ext).
#
#   Uso:
#     bash covenant-build.sh                  (compilação padrão)
#     LOCALMODCFG=yes bash covenant-build.sh  (apenas módulos em uso)
#     bash covenant-build.sh --jobs 28        (limita threads)
#     bash covenant-build.sh --dry-run        (simula as etapas)
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
  echo -e "${PURPLE}${BOLD}"
  cat << 'EOF'
  ██████╗ ██╗   ██╗██╗██╗     ██████╗ 
  ██╔══██╗██║   ██║██║██║     ██╔══██╗
  ██████╔╝██║   ██║██║██║     ██║  ██║
  ██╔══██╗██║   ██║██║██║     ██║  ██║
  ██████╔╝╚██████╔╝██║███████╗██████╔╝
   ╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝ 
EOF
  echo -e "${CYAN}      ⚡ Covenant-CachyOS Custom Kernel Compiler ⚡${NC}"
  echo -e "${DIM}             By Anderson Araujo  ·  MIT License${NC}"
  echo ""
}

# ─── Verificação de Usuário (makepkg não pode rodar como root) ─
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  err "Não execute este script como root! O makepkg requer usuário comum.\n  Execute simplesmente: bash covenant-build.sh"
fi

# ─── Configurações Padrão ─────────────────────────────────────
KSUFFIX="covenant"
USER_HOME="$HOME"
BUILD_DIR="$USER_HOME/kernel-build"
PKGBUILD_DIR="$BUILD_DIR/linux-cachyos/linux-cachyos"

# Migração de typo histórico (~/Kernal -> ~/Kernel)
KERNEL_DIR="$USER_HOME/Kernel"
if [ -d "$USER_HOME/Kernal" ] && [ ! -d "$KERNEL_DIR" ]; then
  mv "$USER_HOME/Kernal" "$KERNEL_DIR"
  warn "Migrado diretório histórico: ~/Kernal → ~/Kernel"
fi
BACKUP_DIR="$KERNEL_DIR/backup/compiled"

JOBS=$(nproc)
LOCALMODCFG="${LOCALMODCFG:-no}"
DRY_RUN=false

# ─── Argumentos de Linha de Comando ──────────────────────────
show_help() {
  print_banner
  cat << 'EOF'
Opções:
  -j, --jobs N           Define o número de threads para compilação (padrão: todos os cores)
  -m, --localmodcfg      Compila apenas os módulos carregados no momento (mais rápido)
  -n, --dry-run          Simula as etapas sem executar a compilação real
  -h, --help             Exibe esta ajuda

Exemplos:
  bash covenant-build.sh
  bash covenant-build.sh --localmodcfg
  bash covenant-build.sh --jobs 32
  bash covenant-build.sh --dry-run
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -j|--jobs)
      JOBS="$2"
      shift 2
      ;;
    -m|--localmodcfg)
      LOCALMODCFG="yes"
      shift
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      ;;
    *)
      warn "Opção desconhecida: $1"
      shift
      ;;
  esac
done

print_banner

if $DRY_RUN; then
  echo -e "${YELLOW}${BOLD}⚡ MODO SIMULAÇÃO (--dry-run) ATIVO — Compilação não será executada ⚡${NC}\n"
fi

# ─── Informações do Ambiente ──────────────────────────────────
CPU_NAME=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "x86_64")
info "CPU Alvo             : ${BOLD}$CPU_NAME${NC} (-march=native)"
info "Threads para build   : ${BOLD}$JOBS threads${NC}"
info "Sufixo do kernel     : ${BOLD}$KSUFFIX${NC} (uname -r → <versao>-$KSUFFIX)"
info "Localmodconfig       : ${BOLD}$LOCALMODCFG${NC}"
info "Diretório de build   : ${BOLD}$BUILD_DIR${NC}"
echo ""

# ─── Checagem Pré-Voo de Espaço em Disco ─────────────────────
FREE_SPACE_KB=$(df -k "$USER_HOME" | awk 'NR==2 {print $4}')
FREE_SPACE_GB=$(( FREE_SPACE_KB / 1024 / 1024 ))
if [ "$FREE_SPACE_GB" -lt 20 ]; then
  warn "Espaço livre em disco: ${FREE_SPACE_GB} GB (Recomendado: 25+ GB para build com LTO)."
else
  log "Espaço em disco disponível: ${FREE_SPACE_GB} GB (OK)."
fi

# ─── Configuração de Opções do PKGBUILD ───────────────────────
export _cpusched="cachyos"            # BORE + EEVDF + sched_ext (preserva BTF para scx_rusty/scx_bpfland)
export _processor_opt=""              # vazio = X86_NATIVE_CPU (-march=native com instruções do seu processador)
export _use_llvm_lto="thin"           # Clang + ThinLTO para otimização interprocedural
export _HZ_ticks="1000"               # 1000Hz para mínima latência interativa
export _tickrate="full"               # nohz_full
export _preempt="full"                # Preempção total
export _hugepage="always"             # Transparent Hugepages ativo
export _per_gov="yes"                 # Performance governor como padrão
export _tcp_bbr3="yes"                # BBRv3 nativo no kernel
export _build_debug="no"              # Sem símbolos pesados de debug (mantém BTF)
export _localmodcfg="$LOCALMODCFG"

TOTAL_STEPS=8
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

# ─────────────────────────────────────────
# PASSO 1 — Dependências de Compilação
# ─────────────────────────────────────────
step "Verificando dependências de compilação..."
BUILD_DEPS=(
  base-devel bc cpio gettext git
  libelf pahole perl python
  tar xz zstd xmlto
  llvm clang lld
)
if ! $DRY_RUN; then
  sudo pacman -S --needed --noconfirm "${BUILD_DEPS[@]}"
fi
log "Dependências verificadas e instaladas."

# ─────────────────────────────────────────
# PASSO 2 — Clonar/Atualizar Repositório CachyOS
# ─────────────────────────────────────────
step "Obtendo PKGBUILD oficial do CachyOS..."
if ! $DRY_RUN; then
  mkdir -p "$BUILD_DIR"
  if [ ! -d "$BUILD_DIR/linux-cachyos/.git" ]; then
    git clone --depth=1 https://github.com/CachyOS/linux-cachyos.git "$BUILD_DIR/linux-cachyos"
    log "Repositório CachyOS clonado."
  else
    git -C "$BUILD_DIR/linux-cachyos" checkout -- . 2>/dev/null || true
    git -C "$BUILD_DIR/linux-cachyos" pull --ff-only
    log "Repositório CachyOS atualizado."
  fi
  cd "$PKGBUILD_DIR"
else
  info "[DRY-RUN] Atualizaria repositório em $PKGBUILD_DIR"
fi

# ─────────────────────────────────────────
# PASSO 3 — Injetar Sufixo Covenant
# ─────────────────────────────────────────
step "Configurando identificador 'linux-$KSUFFIX' no PKGBUILD..."
if ! $DRY_RUN; then
  if grep -q '^pkgbase="linux-\$_pkgsuffix"' PKGBUILD; then
    sed -i "s|^pkgbase=\"linux-\$_pkgsuffix\"|_pkgsuffix=$KSUFFIX\npkgbase=\"linux-\$_pkgsuffix\"|" PKGBUILD
    log "pkgbase configurado: linux-$KSUFFIX | uname: <versao>-$KSUFFIX"
  elif grep -q '_pkgsuffix=' PKGBUILD; then
    sed -i "s|_pkgsuffix=.*|_pkgsuffix=$KSUFFIX|" PKGBUILD
    log "Sufixo atualizado para $KSUFFIX"
  else
    warn "Estrutura padrão de pkgbase não reconhecida — prosseguindo com upstream."
  fi
else
  info "[DRY-RUN] Injetaria _pkgsuffix=$KSUFFIX"
fi

# ─────────────────────────────────────────
# PASSO 4 — Compilação com LLVM + ThinLTO
# ─────────────────────────────────────────
step "Iniciando compilação (LLVM + ThinLTO com $JOBS threads)..."
warn "Primeira compilação: 40min - 2h (depende do hardware) | Rebuild: ~10min"

if ! $DRY_RUN; then
  export LLVM=1 LLVM_IAS=1
  MAKEFLAGS="-j${JOBS}" makepkg -sf --noconfirm --skippgpcheck
  log "Compilação concluída com sucesso!"
else
  info "[DRY-RUN] makepkg seria executado com -j${JOBS}"
fi

# ─────────────────────────────────────────
# PASSO 5 — Localizar Pacotes Gerados
# ─────────────────────────────────────────
step "Localizando artefatos gerados..."
PKG=""
HDR=""
if ! $DRY_RUN; then
  PKG=$(find . -maxdepth 1 -name "linux-${KSUFFIX}-[0-9]*.pkg.tar.zst" ! -name '*headers*' 2>/dev/null | sort -V | tail -1)
  HDR=$(find . -maxdepth 1 -name "linux-${KSUFFIX}-headers-[0-9]*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1)
  
  [ -n "$PKG" ] || err "Pacote linux-${KSUFFIX} não foi encontrado no diretório de build."
  log "Kernel  : $(basename "$PKG")"
  [ -n "$HDR" ] && log "Headers : $(basename "$HDR")"
else
  info "[DRY-RUN] Localizaria linux-${KSUFFIX}-*.pkg.tar.zst"
fi

# ─────────────────────────────────────────
# PASSO 6 — Instalar Pacotes com Pacman
# ─────────────────────────────────────────
step "Instalando kernel e headers no sistema..."
if ! $DRY_RUN && [ -n "$PKG" ]; then
  # shellcheck disable=SC2086
  sudo pacman -U --noconfirm "$PKG" ${HDR:+"$HDR"}
  log "Pacote $PKG instalado no sistema."
else
  info "[DRY-RUN] sudo pacman -U seria executado"
fi

# ─────────────────────────────────────────
# PASSO 7 — Atualizar GRUB
# ─────────────────────────────────────────
step "Atualizando GRUB..."
if ! $DRY_RUN; then
  sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || sudo grub-mkconfig -o /boot/grub/grub.cfg
  log "GRUB atualizado com a nova entrada linux-$KSUFFIX."
else
  info "[DRY-RUN] sudo grub-mkconfig seria executado"
fi

# ─────────────────────────────────────────
# PASSO 8 — Backup dos Binários e Config
# ─────────────────────────────────────────
step "Salvando binários e .config no backup..."
if ! $DRY_RUN; then
  mkdir -p "$BACKUP_DIR"
  [ -n "$PKG" ] && cp "$PKG" "$BACKUP_DIR/"
  [ -n "$HDR" ] && cp "$HDR" "$BACKUP_DIR/"
  [ -f .config ] && cp .config "$BACKUP_DIR/kernel-${KSUFFIX}.config"
  log "Backup salvo em: $BACKUP_DIR"
else
  info "[DRY-RUN] Salvaria arquivos em $BACKUP_DIR"
fi

# ─────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────
echo ""
echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ⚡ Kernel linux-${KSUFFIX} Compilado e Instalado! ⚡${NC}"
echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Configurações de Compilação:${NC}"
echo -e "  ${DIM}Otimização :${NC} -march=native (instruções completas da sua CPU)"
echo -e "  ${DIM}Compilador :${NC} Clang + ThinLTO + LLVM integrated assembler"
echo -e "  ${DIM}Scheduler  :${NC} BORE + EEVDF + sched_ext (compatível com scx)"
echo -e "  ${DIM}Tickrate   :${NC} 1000Hz (full tickless nohz_full)"
echo -e "  ${DIM}Rede       :${NC} BBRv3 nativo"
echo ""
echo -e "  ${CYAN}Para reinstalar futuramente sem recompilar:${NC}"
echo -e "  sudo pacman -U $BACKUP_DIR/linux-${KSUFFIX}-*.pkg.tar.zst"
echo ""
echo -e "${BOLD}Reinicie para carregar o novo kernel: sudo reboot${NC}"
echo ""
