#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant Theme Installer (GRUB + Plymouth)
#  Instala o tema GRUB com resolução ampliada (1280x720) e
#  o tema Plymouth de boot/shutdown em tela preta com logo grande.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
CYAN='\033[0;36m';   BOLD='\033[1m';       DIM='\033[2m';  RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $1${RESET}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${RESET}"; }
err()  { echo -e "  ${RED}❌ $1${RESET}"; exit 1; }

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
echo "  ║   🎨 Covenant Theme Suite — Instalador    ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${RESET}"

# ─── Passo 1: Gerar assets visuais ───────────────────────────
echo -e "${BOLD}[1/4] Gerando assets e fontes ampliadas...${RESET}"
if [ -f "$THEME_SRC/generate-assets.sh" ]; then
    bash "$THEME_SRC/generate-assets.sh"
    ok "Assets do GRUB gerados"
else
    warn "generate-assets.sh não encontrado — usando assets existentes"
fi

# ─── Passo 2: Copiar logo para o GRUB ────────────────────────
echo -e "\n${BOLD}[2/4] Preparando logo do GRUB...${RESET}"
LOGO_SRC=""
for p in "$SCRIPT_DIR/../../assets/covenant-logo.png" \
         "$SCRIPT_DIR/../assets/covenant-logo.png" \
         "$THEME_SRC/covenant-logo.png"; do
    if [ -f "$p" ]; then
        LOGO_SRC="$p"
        break
    fi
done

if [ -n "$LOGO_SRC" ]; then
    if command -v magick &>/dev/null || command -v convert &>/dev/null; then
        CMD=$(command -v magick || command -v convert)
        $CMD "$LOGO_SRC" -resize 550x180 -background none PNG32:"$THEME_SRC/covenant-logo.png"
        ok "Logo GRUB redimensionada (550x180 transparente)"
    fi
fi

# ─── Passo 3: Instalar tema no /boot ─────────────────────────
echo -e "\n${BOLD}[3/4] Instalando tema em $THEME_DEST/...${RESET}"
mkdir -p "$THEME_DEST"

# Copiar todos os arquivos do tema
cp -r "$THEME_SRC"/*.txt  "$THEME_DEST/" 2>/dev/null || true
cp -r "$THEME_SRC"/*.png  "$THEME_DEST/" 2>/dev/null || true
cp -r "$THEME_SRC"/*.pf2  "$THEME_DEST/" 2>/dev/null || true
cp -r "$THEME_SRC"/icons  "$THEME_DEST/" 2>/dev/null || true
rm -f "$THEME_DEST/separator.png"

ok "Tema copiado para $THEME_DEST/"

# ─── Passo 4: Configurar GRUB (/etc/default/grub) ────────────
echo -e "\n${BOLD}[4/4] Configurando GRUB e resolução ampliada...${RESET}"
GRUB_DEFAULT="/etc/default/grub"

if [ ! -f "${GRUB_DEFAULT}.pre-covenant-theme" ]; then
    cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.pre-covenant-theme"
    ok "Backup: ${GRUB_DEFAULT}.pre-covenant-theme"
fi

# Configurar caminho do tema
sed -i '/^GRUB_THEME=/d' "$GRUB_DEFAULT"
sed -i '/^#.*GRUB_THEME.*covenant/d' "$GRUB_DEFAULT"
echo "" >> "$GRUB_DEFAULT"
echo "# Covenant GRUB Theme" >> "$GRUB_DEFAULT"
echo "GRUB_THEME=\"/boot/grub/themes/covenant/theme.txt\"" >> "$GRUB_DEFAULT"

# Definir resolução nativa 1920x1080 (1:1 pixel-perfect sem serrilhado)
if grep -q "^#\?GRUB_GFXMODE=" "$GRUB_DEFAULT"; then
    sed -i 's/^#\?GRUB_GFXMODE=.*/GRUB_GFXMODE="1920x1080,1280x720,auto"/' "$GRUB_DEFAULT"
else
    echo 'GRUB_GFXMODE="1920x1080,1280x720,auto"' >> "$GRUB_DEFAULT"
fi

# GFX payload
sed -i 's/^#\?GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX="keep"/' "$GRUB_DEFAULT" \
    || echo "GRUB_GFXPAYLOAD_LINUX=\"keep\"" >> "$GRUB_DEFAULT"

ok "Resolução ampliada (1280x720) e GRUB_THEME configurados"

# Regenerar grub.cfg
echo -e "\n${DIM}  Regenerando grub.cfg...${RESET}"
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -5
ok "grub.cfg regenerado"

# ─── Passo 5: Atualizar Plymouth (Boot e Shutdown) ───────────
PLYMOUTH_INSTALLER="$SCRIPT_DIR/../plymouth/install-plymouth-theme.sh"
if [ -f "$PLYMOUTH_INSTALLER" ]; then
    echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}Atualizando tela de Boot e Shutdown (Plymouth)...${RESET}"
    bash "$PLYMOUTH_INSTALLER"
fi

# ─── Resumo Final ────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  ✅ Suite Covenant (GRUB + Plymouth) Atualizada!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${DIM}GRUB Resolução:${RESET} 1280x720 (escala ampla e nítida)"
echo -e "  ${DIM}GRUB Layout:${RESET}    Logo no topo, menu amplo, contagem abaixo"
echo -e "  ${DIM}Plymouth:${RESET}       Fundo preto puro, logo grande, sem textos"
echo ""
echo -e "  ${YELLOW}⚠️  Reinicie para ver o novo visual: sudo reboot${RESET}"
echo ""
