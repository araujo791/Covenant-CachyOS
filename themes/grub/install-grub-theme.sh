#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant GRUB Theme — Instalador
#  Instala o tema GRUB com background, logo e menu estilizado
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Cores ────────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
CYAN='\033[0;36m';   BOLD='\033[1m';       DIM='\033[2m';  RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $1${RESET}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${RESET}"; }
err()  { echo -e "  ${RED}❌ $1${RESET}"; exit 1; }

# ─── Verificações ────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    err "Execute como root: sudo bash install-grub-theme.sh"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_SRC="$SCRIPT_DIR/covenant"
THEME_DEST="/boot/grub/themes/covenant"

if [ ! -f "$THEME_SRC/theme.txt" ]; then
    err "theme.txt não encontrado em $THEME_SRC/"
fi

echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║   🎨 Covenant GRUB Theme — Instalador    ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${RESET}"

# ─── Passo 1: Gerar assets visuais ───────────────────────────
echo -e "${BOLD}[1/4] Gerando assets visuais...${RESET}"
if [ -f "$THEME_SRC/generate-assets.sh" ]; then
    bash "$THEME_SRC/generate-assets.sh"
else
    warn "generate-assets.sh não encontrado — usando assets existentes"
fi

# ─── Passo 2: Copiar logo ────────────────────────────────────
echo -e "\n${BOLD}[2/4] Preparando logo...${RESET}"
LOGO_SRC="$SCRIPT_DIR/../../assets/covenant-logo.png"
if [ -f "$LOGO_SRC" ]; then
    # Redimensionar logo para o GRUB (max 400px largura)
    if command -v magick &>/dev/null || command -v convert &>/dev/null; then
        CMD=$(command -v magick || command -v convert)
        $CMD "$LOGO_SRC" -resize 500x150 -background none -flatten \
            "$THEME_SRC/covenant-logo.png"
        ok "Logo redimensionada (500x150)"
    else
        cp "$LOGO_SRC" "$THEME_SRC/covenant-logo.png"
        warn "ImageMagick não encontrado — logo copiada sem redimensionar"
    fi
else
    warn "Logo não encontrada em assets/covenant-logo.png"
fi

# ─── Passo 3: Instalar tema ─────────────────────────────────
echo -e "\n${BOLD}[3/4] Instalando tema em $THEME_DEST/...${RESET}"
mkdir -p "$THEME_DEST"

# Copiar todos os arquivos do tema
cp -r "$THEME_SRC"/*.txt  "$THEME_DEST/" 2>/dev/null || true
cp -r "$THEME_SRC"/*.png  "$THEME_DEST/" 2>/dev/null || true
cp -r "$THEME_SRC"/icons  "$THEME_DEST/" 2>/dev/null || true

ok "Tema copiado para $THEME_DEST/"

# ─── Passo 4: Configurar GRUB ────────────────────────────────
echo -e "\n${BOLD}[4/4] Configurando GRUB...${RESET}"
GRUB_DEFAULT="/etc/default/grub"

# Backup
if [ ! -f "${GRUB_DEFAULT}.pre-covenant-theme" ]; then
    cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.pre-covenant-theme"
    ok "Backup: ${GRUB_DEFAULT}.pre-covenant-theme"
fi

# Remover tema anterior se existir
sed -i '/^GRUB_THEME=/d' "$GRUB_DEFAULT"
sed -i '/^#.*GRUB_THEME.*covenant/d' "$GRUB_DEFAULT"

# Adicionar tema Covenant
echo "" >> "$GRUB_DEFAULT"
echo "# Covenant GRUB Theme" >> "$GRUB_DEFAULT"
echo "GRUB_THEME=\"/boot/grub/themes/covenant/theme.txt\"" >> "$GRUB_DEFAULT"

# Garantir resolução do GRUB
if ! grep -q "^GRUB_GFXMODE=" "$GRUB_DEFAULT"; then
    echo "GRUB_GFXMODE=\"1920x1080,1280x720,auto\"" >> "$GRUB_DEFAULT"
fi
# Garantir que GFX payload está habilitado
sed -i 's/^#\?GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX="keep"/' "$GRUB_DEFAULT" \
    || echo "GRUB_GFXPAYLOAD_LINUX=\"keep\"" >> "$GRUB_DEFAULT"

ok "GRUB_THEME configurado"

# Regenerar grub.cfg
echo -e "\n${DIM}  Regenerando grub.cfg...${RESET}"
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -5
ok "grub.cfg regenerado"

# ─── Resumo ──────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  ✅ Tema Covenant instalado com sucesso!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${DIM}Tema:${RESET}     $THEME_DEST/"
echo -e "  ${DIM}Backup:${RESET}   ${GRUB_DEFAULT}.pre-covenant-theme"
echo -e "  ${DIM}Resolução:${RESET} $(grep GRUB_GFXMODE "$GRUB_DEFAULT" | cut -d= -f2)"
echo ""
echo -e "  ${YELLOW}⚠️  Reinicie para ver o novo tema de boot${RESET}"
echo ""
echo -e "  ${DIM}Para desinstalar:${RESET}"
echo -e "  ${DIM}  sudo rm -rf $THEME_DEST${RESET}"
echo -e "  ${DIM}  sudo sed -i '/GRUB_THEME/d' $GRUB_DEFAULT${RESET}"
echo -e "  ${DIM}  sudo grub-mkconfig -o /boot/grub/grub.cfg${RESET}"
echo ""
