#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant GRUB Theme — Gerador de assets visuais
#  Gera fontes Open Sans de alta suavidade (20pt, 16pt, 14pt)
#  com autohinting inteligente para eliminar serrilhado,
#  além do seletor 9-slice em PNG32 truecolor.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$SCRIPT_DIR"

CYAN="#00d4ff"
NAVY="#0f172a"
SLATE="#334155"
GOLD="#d4a017"

echo "🎨 Gerando fontes Open Sans anti-serrilhado e assets..."

# 1. Compilar fontes Open Sans com autohint forçado para eliminar serrilhado
FONT_REG="/usr/share/fonts/TTF/OpenSans-Regular.ttf"
FONT_BOLD="/usr/share/fonts/TTF/OpenSans-Bold.ttf"

if [ ! -f "$FONT_REG" ]; then
    FONT_REG="/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
    FONT_BOLD="/usr/share/fonts/liberation/LiberationSans-Bold.ttf"
fi

if command -v grub-mkfont &>/dev/null && [ -f "$FONT_REG" ]; then
    echo "  → Compilando Open Sans 20pt / 16pt / 14pt com autohint"
    grub-mkfont -a -s 20 -o "$THEME_DIR/opensans-20.pf2" "$FONT_REG" 2>/dev/null || true
    grub-mkfont -a -s 20 -b -o "$THEME_DIR/opensans-bold-20.pf2" "$FONT_BOLD" 2>/dev/null || true
    grub-mkfont -a -s 16 -o "$THEME_DIR/opensans-16.pf2" "$FONT_REG" 2>/dev/null || true
    grub-mkfont -a -s 14 -o "$THEME_DIR/opensans-14.pf2" "$FONT_REG" 2>/dev/null || true
fi

# 2. Verificar ImageMagick
if command -v magick &>/dev/null; then
    CONVERT="magick"
elif command -v convert &>/dev/null; then
    CONVERT="convert"
else
    echo "❌ ImageMagick não encontrado."
    exit 1
fi

TMP_DIR=$(mktemp -d /tmp/covenant-theme.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# 3. Gerar seletor 9-slice em 52px (PNG32 TrueColor com canal alpha)
echo "  → Seletor 9-slice cyan suave (52px)"
$CONVERT -size 80x52 xc:none \
  -fill "rgba(6, 182, 212, 0.25)" \
  -stroke "$CYAN" -strokewidth 2 \
  -draw "roundrectangle 1,1 78,50 8,8" \
  PNG32:"$TMP_DIR/select_full.png"

$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+0+0 PNG32:"$THEME_DIR/select_tl.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 60x10+10+0 PNG32:"$THEME_DIR/select_t.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+70+0 PNG32:"$THEME_DIR/select_tr.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x32+0+10 PNG32:"$THEME_DIR/select_w.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 60x32+10+10 PNG32:"$THEME_DIR/select_c.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x32+70+10 PNG32:"$THEME_DIR/select_e.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+0+42 PNG32:"$THEME_DIR/select_bl.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 60x10+10+42 PNG32:"$THEME_DIR/select_b.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+70+42 PNG32:"$THEME_DIR/select_br.png"

# 4. Scrollbar
$CONVERT -size 6x30 xc:"$CYAN" PNG32:"$THEME_DIR/scrollbar_thumb.png"
$CONVERT -size 6x30 xc:"$SLATE" PNG32:"$THEME_DIR/scrollbar_frame.png"

# 5. Ícones (36x36)
mkdir -p "$THEME_DIR/icons"
$CONVERT -size 36x36 xc:none -fill "$CYAN" -draw "circle 18,18 18,4" -fill "$NAVY" -draw "circle 18,18 18,9" -fill "$CYAN" -draw "polygon 15,9 21,9 18,22" PNG32:"$THEME_DIR/icons/cachyos.png"
$CONVERT -size 36x36 xc:none -fill "$GOLD" -draw "polygon 16,4 20,4 22,18 18,32 14,18" -fill "$CYAN" -draw "circle 18,18 18,7" -alpha set -channel A -evaluate set 30% +channel -fill "$GOLD" -draw "polygon 16,4 20,4 22,18 18,32 14,18" PNG32:"$THEME_DIR/icons/covenant.png"
$CONVERT -size 36x36 xc:none -fill "$SLATE" -draw "circle 18,18 18,7" PNG32:"$THEME_DIR/icons/unknown.png"

# Limpeza de resíduos
rm -f "$THEME_DIR/separator.png"

echo "✅ Assets do GRUB prontos!"
