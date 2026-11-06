#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant GRUB Theme — Gerador de assets visuais
#  Gera fontes .pf2 em escala grande (20pt), 9-slice select bar
#  de 54px e logo ampliada em PNG32 transparente.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$SCRIPT_DIR"

CYAN="#06b6d4"
NAVY="#0f172a"
SLATE="#334155"
GOLD="#d4a017"

echo "🎨 Gerando assets e fontes ampliadas do tema Covenant GRUB..."

# 1. Compilar fontes .pf2 de alta visibilidade (20pt e 16pt)
if command -v grub-mkfont &>/dev/null && [ -f /usr/share/fonts/TTF/DejaVuSans.ttf ]; then
    echo "  → Fontes DejaVu Sans (.pf2 em 20pt para alta legibilidade)"
    grub-mkfont -s 20 -o "$THEME_DIR/dejavu-20.pf2" /usr/share/fonts/TTF/DejaVuSans.ttf 2>/dev/null || true
    grub-mkfont -s 20 -o "$THEME_DIR/dejavu-bold-20.pf2" /usr/share/fonts/TTF/DejaVuSans-Bold.ttf 2>/dev/null || true
    grub-mkfont -s 16 -o "$THEME_DIR/dejavu-16.pf2" /usr/share/fonts/TTF/DejaVuSans.ttf 2>/dev/null || true
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

TMP_DIR=$(mktemp -d /tmp/covenant-theme.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# 3. Gerar 9-slice rounded rectangle ampliado (54px de altura para fontes 20pt)
echo "  → 9-slice select bar ampliada (54px de altura + glow cyan)"
$CONVERT -size 80x54 xc:none \
  -fill "rgba(6, 182, 212, 0.22)" \
  -stroke "$CYAN" -strokewidth 2 \
  -draw "roundrectangle 1,1 78,52 8,8" \
  "$TMP_DIR/select_full.png"

$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+0+0 "$THEME_DIR/select_tl.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 60x10+10+0 "$THEME_DIR/select_t.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+70+0 "$THEME_DIR/select_tr.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x34+0+10 "$THEME_DIR/select_w.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 60x34+10+10 "$THEME_DIR/select_c.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x34+70+10 "$THEME_DIR/select_e.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+0+44 "$THEME_DIR/select_bl.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 60x10+10+44 "$THEME_DIR/select_b.png"
$CONVERT "$TMP_DIR/select_full.png" -crop 10x10+70+44 "$THEME_DIR/select_br.png"

# 4. Scrollbar
echo "  → scrollbar"
$CONVERT -size 8x36 xc:"$CYAN" \
    -alpha set -channel A -evaluate set 80% +channel \
    "$THEME_DIR/scrollbar_thumb.png"

$CONVERT -size 8x36 xc:"$SLATE" \
    -alpha set -channel A -evaluate set 40% +channel \
    "$THEME_DIR/scrollbar_frame.png"

# 5. Ícones (36x36 para acompanhar a resolução ampliada)
echo "  → icons/ (36x36)"
mkdir -p "$THEME_DIR/icons"
$CONVERT -size 36x36 xc:none \
    -fill "$CYAN" -draw "circle 18,18 18,4" \
    -fill "$NAVY" -draw "circle 18,18 18,9" \
    -fill "$CYAN" -draw "polygon 15,9 21,9 18,22" \
    "$THEME_DIR/icons/cachyos.png"

$CONVERT -size 36x36 xc:none \
    -fill "$GOLD" -draw "polygon 16,4 20,4 22,18 18,32 14,18" \
    -fill "$CYAN" -draw "circle 18,18 18,7" \
    -alpha set -channel A -evaluate set 30% +channel \
    -fill "$GOLD" -draw "polygon 16,4 20,4 22,18 18,32 14,18" \
    "$THEME_DIR/icons/covenant.png"

$CONVERT -size 36x36 xc:none \
    -fill "$SLATE" -draw "circle 18,18 18,7" \
    "$THEME_DIR/icons/unknown.png"

# Remover artefatos legados
rm -f "$THEME_DIR/separator.png"

echo "✅ Assets e fontes atualizados em $THEME_DIR/"
