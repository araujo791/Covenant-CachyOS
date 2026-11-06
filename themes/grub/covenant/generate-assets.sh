#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant GRUB Theme — Gerador de assets visuais
#  Gera select bar, scrollbar, separator e progress bar via
#  ImageMagick (convert/magick). Funciona sem assets externos.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$SCRIPT_DIR"

# ─── Cores ────────────────────────────────────────────────────
CYAN="#06b6d4"
CYAN_DIM="#0e7490"
NAVY="#0f172a"
NAVY_LIGHT="#1e293b"
SLATE="#334155"
PURPLE="#7c3aed"
GOLD="#d4a017"

echo "🎨 Gerando assets do tema Covenant GRUB..."

# Verificar ImageMagick
if command -v magick &>/dev/null; then
    CONVERT="magick"
elif command -v convert &>/dev/null; then
    CONVERT="convert"
else
    echo "❌ ImageMagick não encontrado. Instale com:"
    echo "   sudo pacman -S imagemagick"
    exit 1
fi

# ─── Select bar (item selecionado no menu) ────────────────────
# Fundo semi-transparente com borda cyan à esquerda
echo "  → select_c.png (centro)"
$CONVERT -size 800x42 xc:"#0d1b2a" \
    -fill "$CYAN" -draw "rectangle 0,0 3,42" \
    -alpha set -channel A -evaluate set 85% +channel \
    "$THEME_DIR/select_c.png"

echo "  → select_w.png (esquerda)"
$CONVERT -size 4x42 xc:"$CYAN" \
    "$THEME_DIR/select_w.png"

echo "  → select_e.png (direita)"
$CONVERT -size 4x42 xc:"#0d1b2a" \
    -alpha set -channel A -evaluate set 60% +channel \
    "$THEME_DIR/select_e.png"

# ─── Separator (linha decorativa) ─────────────────────────────
echo "  → separator.png"
$CONVERT -size 960x2 \
    -define gradient:direction=east \
    gradient:"#00000000-${CYAN}" \
    -gravity center -extent 960x2 \
    \( -size 960x2 -define gradient:direction=east gradient:"${CYAN}-#00000000" \) \
    -gravity center -composite \
    "$THEME_DIR/separator.png"

# Versão simplificada se a composição falhar
if [ ! -f "$THEME_DIR/separator.png" ]; then
    $CONVERT -size 960x2 xc:"$CYAN" \
        -alpha set -channel A -fx "sin(pi*i/w)*0.6" +channel \
        "$THEME_DIR/separator.png"
fi

# ─── Scrollbar ────────────────────────────────────────────────
echo "  → scrollbar_thumb.png"
$CONVERT -size 6x30 xc:"$CYAN" \
    -alpha set -channel A -evaluate set 80% +channel \
    "$THEME_DIR/scrollbar_thumb.png"

echo "  → scrollbar_frame.png"
$CONVERT -size 6x30 xc:"$SLATE" \
    -alpha set -channel A -evaluate set 40% +channel \
    "$THEME_DIR/scrollbar_frame.png"

# ─── Progress bar ────────────────────────────────────────────
echo "  → progress_bar_c.png (preenchida)"
$CONVERT -size 100x12 \
    -define gradient:direction=east \
    gradient:"${CYAN_DIM}-${CYAN}" \
    "$THEME_DIR/progress_bar_c.png"

echo "  → progress_bg_c.png (fundo)"
$CONVERT -size 100x12 xc:"$NAVY_LIGHT" \
    -alpha set -channel A -evaluate set 70% +channel \
    "$THEME_DIR/progress_bg_c.png"

echo "  → highlight_c.png"
$CONVERT -size 100x12 xc:"$CYAN" \
    -alpha set -channel A -evaluate set 90% +channel \
    "$THEME_DIR/highlight_c.png"

# ─── Ícones de menu (minimalistas) ────────────────────────────
echo "  → icons/cachyos.png"
$CONVERT -size 32x32 xc:none \
    -fill "$CYAN" -draw "circle 16,16 16,4" \
    -fill "$NAVY" -draw "circle 16,16 16,8" \
    -fill "$CYAN" -draw "polygon 13,8 19,8 16,20" \
    "$THEME_DIR/icons/cachyos.png"

echo "  → icons/covenant.png"
$CONVERT -size 32x32 xc:none \
    -fill "$GOLD" -draw "polygon 14,4 18,4 20,16 16,28 12,16" \
    -fill "$CYAN" -draw "circle 16,16 16,6" \
    -alpha set -channel A -evaluate set 30% +channel \
    -fill "$GOLD" -draw "polygon 14,4 18,4 20,16 16,28 12,16" \
    "$THEME_DIR/icons/covenant.png"

echo "  → icons/unknown.png"
$CONVERT -size 32x32 xc:none \
    -fill "$SLATE" -draw "circle 16,16 16,6" \
    "$THEME_DIR/icons/unknown.png"

echo ""
echo "✅ Assets gerados em: $THEME_DIR/"
echo "   Arquivos: $(ls -1 "$THEME_DIR"/*.png 2>/dev/null | wc -l) PNGs + $(ls -1 "$THEME_DIR"/icons/*.png 2>/dev/null | wc -l) ícones"
