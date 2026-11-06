#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant GRUB Theme — Gerador de assets visuais
#  Gera fontes .pf2, 9-slice select bar, scrollbar via ImageMagick
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$SCRIPT_DIR"

CYAN="#06b6d4"
NAVY="#0f172a"
SLATE="#334155"
GOLD="#d4a017"

echo "🎨 Gerando assets e fontes do tema Covenant GRUB..."

# 1. Compilar fontes .pf2 para renderização nítida no GRUB
if command -v grub-mkfont &>/dev/null && [ -f /usr/share/fonts/TTF/DejaVuSans.ttf ]; then
    echo "  → Fontes DejaVu Sans (.pf2)"
    grub-mkfont -s 16 -o "$THEME_DIR/dejavu-16.pf2" /usr/share/fonts/TTF/DejaVuSans.ttf 2>/dev/null || true
    grub-mkfont -s 16 -o "$THEME_DIR/dejavu-bold-16.pf2" /usr/share/fonts/TTF/DejaVuSans-Bold.ttf 2>/dev/null || true
    grub-mkfont -s 14 -o "$THEME_DIR/dejavu-14.pf2" /usr/share/fonts/TTF/DejaVuSans.ttf 2>/dev/null || true
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

# 3. Gerar 9-slice rounded rectangle para o item selecionado (glow cyan)
echo "  → 9-slice select bar (cantos arredondados + glow cyan)"
$CONVERT -size 64x44 xc:none \
  -fill "rgba(6, 182, 212, 0.20)" \
  -stroke "$CYAN" -strokewidth 2 \
  -draw "roundrectangle 1,1 62,42 6,6" \
  /tmp/select_full.png

$CONVERT /tmp/select_full.png -crop 8x8+0+0 "$THEME_DIR/select_tl.png"
$CONVERT /tmp/select_full.png -crop 48x8+8+0 "$THEME_DIR/select_t.png"
$CONVERT /tmp/select_full.png -crop 8x8+56+0 "$THEME_DIR/select_tr.png"
$CONVERT /tmp/select_full.png -crop 8x28+0+8 "$THEME_DIR/select_w.png"
$CONVERT /tmp/select_full.png -crop 48x28+8+8 "$THEME_DIR/select_c.png"
$CONVERT /tmp/select_full.png -crop 8x28+56+8 "$THEME_DIR/select_e.png"
$CONVERT /tmp/select_full.png -crop 8x8+0+36 "$THEME_DIR/select_bl.png"
$CONVERT /tmp/select_full.png -crop 48x8+8+36 "$THEME_DIR/select_b.png"
$CONVERT /tmp/select_full.png -crop 8x8+56+36 "$THEME_DIR/select_br.png"
rm -f /tmp/select_full.png

# 4. Scrollbar
echo "  → scrollbar"
$CONVERT -size 6x30 xc:"$CYAN" \
    -alpha set -channel A -evaluate set 80% +channel \
    "$THEME_DIR/scrollbar_thumb.png"

$CONVERT -size 6x30 xc:"$SLATE" \
    -alpha set -channel A -evaluate set 40% +channel \
    "$THEME_DIR/scrollbar_frame.png"

# 5. Ícones
echo "  → icons/"
mkdir -p "$THEME_DIR/icons"
$CONVERT -size 32x32 xc:none \
    -fill "$CYAN" -draw "circle 16,16 16,4" \
    -fill "$NAVY" -draw "circle 16,16 16,8" \
    -fill "$CYAN" -draw "polygon 13,8 19,8 16,20" \
    "$THEME_DIR/icons/cachyos.png"

$CONVERT -size 32x32 xc:none \
    -fill "$GOLD" -draw "polygon 14,4 18,4 20,16 16,28 12,16" \
    -fill "$CYAN" -draw "circle 16,16 16,6" \
    -alpha set -channel A -evaluate set 30% +channel \
    -fill "$GOLD" -draw "polygon 14,4 18,4 20,16 16,28 12,16" \
    "$THEME_DIR/icons/covenant.png"

$CONVERT -size 32x32 xc:none \
    -fill "$SLATE" -draw "circle 16,16 16,6" \
    "$THEME_DIR/icons/unknown.png"

# Remover artefatos legados
rm -f "$THEME_DIR/separator.png"

echo "✅ Assets e fontes atualizados em $THEME_DIR/"
