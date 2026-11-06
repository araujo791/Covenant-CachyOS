#!/usr/bin/env bash
# ============================================================
#   ██████╗ ██████╗ ██╗   ██╗███████╗███╗   ██╗ █████╗ ███╗   ██╗████████╗
#  ██╔════╝██╔═══██╗██║   ██║██╔════╝████╗  ██║██╔══██╗████╗  ██║╚══██╔══╝
#  ██║     ██║   ██║██║   ██║█████╗  ██╔██╗ ██║███████║██╔██╗ ██║   ██║   
#  ██║     ██║   ██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██╔══██║██║╚██╗██║   ██║   
#  ╚██████╗╚██████╔╝ ╚████╔╝ ███████╗██║ ╚████║██║  ██║██║ ╚████║   ██║   
#   ╚═════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   
#         Covenant-CachyOS — Quick Package & Theme Installer
# ============================================================
#   Instala rapidamente os pacotes .pkg.tar.zst do kernel compilado
#   junto com o tema oficial Covenant do GRUB (e Plymouth).
#
#   Uso:
#     sudo bash covenant-install.sh
#     sudo bash covenant-install.sh /caminho/para/pacotes
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
  echo -e "${CYAN}${BOLD}"
  cat << 'EOF'
   ██████╗ ██████╗ ██╗   ██╗███████╗███╗   ██╗ █████╗ ███╗   ██╗████████╗
  ██╔════╝██╔═══██╗██║   ██║██╔════╝████╗  ██║██╔══██╗████╗  ██║╚══██╔══╝
  ██║     ██║   ██║██║   ██║█████╗  ██╔██╗ ██║███████║██╔██╗ ██║   ██║   
  ██║     ██║   ██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║██╔══██║██║╚██╗██║   ██║   
  ╚██████╗╚██████╔╝ ╚████╔╝ ███████╗██║ ╚████║██║  ██║██║ ╚████║   ██║   
   ╚═════╝ ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   
EOF
  echo -e "${GOLD}         ⚡ Covenant-CachyOS — Quick Package & Theme Installer ⚡${NC}"
  echo -e "${DIM}               By Anderson Araujo  ·  MIT License${NC}"
  echo ""
}

print_banner

# ─── Verificação de Permissões ──────────────────────────────
[ "${EUID:-$(id -u)}" -eq 0 ] || err "Execute com sudo: sudo bash covenant-install.sh"

# ─── Identificação do Usuário Real ──────────────────────────
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  REAL_USER="$SUDO_USER"
elif [ -n "${PKEXEC_UID:-}" ]; then
  REAL_USER=$(id -un "$PKEXEC_UID" 2>/dev/null || whoami)
else
  REAL_USER=$(logname 2>/dev/null || whoami)
fi
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
USER_HOME="${USER_HOME:-/home/$REAL_USER}"

KERNEL_DIR="$USER_HOME/Kernel"
BACKUP_COMPILED="$KERNEL_DIR/backup/compiled"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Localização dos Pacotes .pkg.tar.zst ────────────────────
CUSTOM_DIR="${1:-}"

POSSIBLE_DIRS=(
  "$CUSTOM_DIR"
  "$SCRIPT_DIR"
  "$SCRIPT_DIR/packages"
  "$SCRIPT_DIR/pkgs"
  "$BACKUP_COMPILED"
  "$USER_HOME/kernel-build/linux-cachyos/linux-cachyos"
  "$USER_HOME/Kernal/backup/compiled"
  "$USER_HOME/Downloads"
)

PKG=""
HDR=""

info "Procurando pacotes linux-covenant... "
for dir in "${POSSIBLE_DIRS[@]}"; do
  [ -z "$dir" ] && continue
  if [ -d "$dir" ]; then
    found_pkg=$(find "$dir" -maxdepth 2 -type f -name "linux-covenant-[0-9]*.pkg.tar.zst" ! -name "*headers*" 2>/dev/null | sort -V | tail -1 || true)
    found_hdr=$(find "$dir" -maxdepth 2 -type f -name "linux-covenant-headers-[0-9]*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1 || true)
    
    if [ -n "$found_pkg" ]; then
      PKG="$found_pkg"
      HDR="$found_hdr"
      info "Pacotes encontrados em: ${BOLD}$dir${NC}"
      break
    fi
  fi
done

# Fallback para qualquer pacote custom de kernel caso não ache com nome específico
if [ -z "$PKG" ]; then
  for dir in "${POSSIBLE_DIRS[@]}"; do
    [ -z "$dir" ] && continue
    if [ -d "$dir" ]; then
      found_pkg=$(find "$dir" -maxdepth 2 -type f -name "linux-*-*-*.pkg.tar.zst" ! -name "*headers*" 2>/dev/null | sort -V | tail -1 || true)
      found_hdr=$(find "$dir" -maxdepth 2 -type f -name "linux-*-headers-*-*.pkg.tar.zst" 2>/dev/null | sort -V | tail -1 || true)
      if [ -n "$found_pkg" ]; then
        PKG="$found_pkg"
        HDR="$found_hdr"
        info "Pacote genérico encontrado em: ${BOLD}$dir${NC}"
        break
      fi
    fi
  done
fi

[ -n "$PKG" ] || err "Nenhum pacote .pkg.tar.zst encontrado. Coloque os arquivos neste diretório ou passe o caminho como argumento."

log "Kernel  : ${BOLD}$(basename "$PKG")${NC}"
if [ -n "$HDR" ]; then
  log "Headers : ${BOLD}$(basename "$HDR")${NC}"
else
  warn "Pacote de headers não encontrado — instalando apenas o kernel."
fi

# ─────────────────────────────────────────
# ETAPA 1 — Instalar os Pacotes com Pacman
# ─────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}[1/3]${NC} ${BOLD}Instalando pacotes do kernel no sistema...${NC}"
# shellcheck disable=SC2086
pacman -U --noconfirm "$PKG" ${HDR:+"$HDR"}
log "Kernel instalado com sucesso via pacman!"

# Fazer backup em ~/Kernel/backup/compiled
mkdir -p "$BACKUP_COMPILED"
cp -u "$PKG" "$BACKUP_COMPILED/" 2>/dev/null || true
[ -n "$HDR" ] && cp -u "$HDR" "$BACKUP_COMPILED/" 2>/dev/null || true
chown -R "$REAL_USER:$REAL_USER" "$KERNEL_DIR" 2>/dev/null || true
log "Cópia preservada em: $BACKUP_COMPILED"

# ─────────────────────────────────────────
# ETAPA 2 — Instalar Tema Oficial do GRUB
# ─────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}[2/3]${NC} ${BOLD}Instalando tema visual Covenant no GRUB...${NC}"
GRUB_INSTALLER="$SCRIPT_DIR/themes/grub/install-grub-theme.sh"

if [ -f "$GRUB_INSTALLER" ]; then
  bash "$GRUB_INSTALLER"
else
  warn "Instalador do tema GRUB não encontrado em $GRUB_INSTALLER"
fi

# Instalar também Plymouth se disponível
PLYMOUTH_INSTALLER="$SCRIPT_DIR/themes/plymouth/install-plymouth-theme.sh"
if [ -f "$PLYMOUTH_INSTALLER" ]; then
  info "Configurando tema Plymouth de boot splash..."
  bash "$PLYMOUTH_INSTALLER" || warn "Plymouth não instalado ou pulado."
fi

# ─────────────────────────────────────────
# ETAPA 3 — Regenerar GRUB
# ─────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}[3/3]${NC} ${BOLD}Atualizando entradas de boot do GRUB...${NC}"
grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || grub-mkconfig -o /boot/grub/grub.cfg
log "grub.cfg atualizado!"

# ─────────────────────────────────────────
# Resumo Final
# ─────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ⚡ Covenant-CachyOS — Instalação Concluída! ⚡${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Resumo do Sistema:${NC}"
echo -e "  ${DIM}Kernel instalado :${NC} $(basename "$PKG")"
[ -n "$HDR" ] && echo -e "  ${DIM}Headers          :${NC} $(basename "$HDR")"
echo -e "  ${DIM}Tema de Boot     :${NC} Cyberpunk Covenant (GRUB 1920x1080)"
echo -e "  ${DIM}Backup seguro    :${NC} $BACKUP_COMPILED"
echo ""
echo -e "  ${YELLOW}${BOLD}Pronto para inicializar!${NC}"
echo -e "  Execute agora: ${BOLD}sudo reboot${NC}"
echo ""
