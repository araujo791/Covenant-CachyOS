#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant Plymouth Theme — Instalador
#  Splash de boot com logo Covenant + spinner animado
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
CYAN='\033[0;36m';   BOLD='\033[1m';       DIM='\033[2m';  RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $1${RESET}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${RESET}"; }
err()  { echo -e "  ${RED}❌ $1${RESET}"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    err "Execute como root: sudo bash install-plymouth-theme.sh"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_NAME="covenant"
PLYMOUTH_DIR="/usr/share/plymouth/themes/$THEME_NAME"

echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║  🎨 Covenant Plymouth Theme — Instalador  ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${RESET}"

# ─── Verificar plymouth ──────────────────────────────────────
if ! command -v plymouth-set-default-theme &>/dev/null; then
    echo -e "${BOLD}[1/3] Instalando plymouth...${RESET}"
    pacman -S --noconfirm --needed plymouth
    ok "Plymouth instalado"
else
    echo -e "${BOLD}[1/3] Plymouth já instalado${RESET}"
    ok "OK"
fi

# ─── Preparar assets ─────────────────────────────────────────
echo -e "\n${BOLD}[2/3] Preparando assets...${RESET}"
mkdir -p "$PLYMOUTH_DIR"

# Copiar logo
LOGO_SRC="$SCRIPT_DIR/../../assets/covenant-logo.png"
if [ -f "$LOGO_SRC" ]; then
    CMD=$(command -v magick || command -v convert || echo "")
    if [ -n "$CMD" ]; then
        $CMD "$LOGO_SRC" -resize 400x120 -background "#0a0e1a" -flatten \
            "$PLYMOUTH_DIR/covenant-logo.png"
        ok "Logo redimensionada (400x120)"
    else
        cp "$LOGO_SRC" "$PLYMOUTH_DIR/covenant-logo.png"
        warn "ImageMagick ausente — logo sem redimensionar"
    fi
else
    warn "Logo não encontrada em assets/ — tema usará texto"
fi

# Gerar background (gradiente navy → púrpura)
CMD=$(command -v magick || command -v convert || echo "")
if [ -n "$CMD" ]; then
    $CMD -size 1920x1080 \
        -define gradient:direction=south \
        gradient:"#0a0e1a-#1a1040" \
        "$PLYMOUTH_DIR/background.png"
    ok "Background gradiente gerado"

    # Spinner frames (12 frames de um anel cyan girando)
    for i in $(seq 0 11); do
        ANGLE=$((i * 30))
        $CMD -size 48x48 xc:none \
            -fill none -stroke "#06b6d4" -strokewidth 3 \
            -draw "arc 4,4 44,44 $ANGLE,$((ANGLE+90))" \
            -fill none -stroke "#1e293b" -strokewidth 3 \
            -draw "arc 4,4 44,44 $((ANGLE+120)),$((ANGLE+360))" \
            "$PLYMOUTH_DIR/spinner-$(printf '%02d' $i).png"
    done
    ok "Spinner: 12 frames gerados"

    # Barra de progresso (fundo e preenchimento)
    $CMD -size 300x6 xc:"#1e293b" "$PLYMOUTH_DIR/progress-bg.png"
    $CMD -size 300x6 \
        -define gradient:direction=east \
        gradient:"#0e7490-#06b6d4" \
        "$PLYMOUTH_DIR/progress-fg.png"
    ok "Barra de progresso gerada"
else
    warn "ImageMagick ausente — instale para gerar spinner/progresso"
fi

# Plymouth theme descriptor
cat > "$PLYMOUTH_DIR/$THEME_NAME.plymouth" << EOF
[Plymouth Theme]
Name=Covenant
Description=Covenant-CachyOS boot splash — cyberpunk dark theme with cyan accents
ModuleName=script

[script]
ImageDir=$PLYMOUTH_DIR
ScriptFile=$PLYMOUTH_DIR/$THEME_NAME.script
EOF

# Plymouth script
cat > "$PLYMOUTH_DIR/$THEME_NAME.script" << 'PLYSCRIPT'
# ═══════════════════════════════════════════════════════════════
#  Covenant Plymouth Script
#  Background gradient + logo central + spinner + progress bar
# ═══════════════════════════════════════════════════════════════

# ─── Background ───────────────────────────────────────────────
bg = Image("background.png");
bg_sprite = Sprite(bg);
bg_sprite.SetPosition(0, 0, -100);

# Escalar background para resolução real
screen_w = Window.GetWidth();
screen_h = Window.GetHeight();
bg_scale_x = screen_w / bg.GetWidth();
bg_scale_y = screen_h / bg.GetHeight();
scale = Math.Max(bg_scale_x, bg_scale_y);
bg_sprite.SetImage(bg.Scale(screen_w, screen_h));

# ─── Logo ─────────────────────────────────────────────────────
logo = Image("covenant-logo.png");
logo_sprite = Sprite(logo);
logo_x = (screen_w - logo.GetWidth()) / 2;
logo_y = (screen_h / 2) - logo.GetHeight() - 30;
logo_sprite.SetPosition(logo_x, logo_y, 1);

# ─── Spinner ─────────────────────────────────────────────────
spinner_frames = [];
for (i = 0; i < 12; i++) {
    if (i < 10)
        spinner_frames[i] = Image("spinner-0" + i + ".png");
    else
        spinner_frames[i] = Image("spinner-" + i + ".png");
}
spinner_sprite = Sprite(spinner_frames[0]);
spinner_x = (screen_w - 48) / 2;
spinner_y = (screen_h / 2) + 20;
spinner_sprite.SetPosition(spinner_x, spinner_y, 2);

frame_count = 0;

fun refresh_callback() {
    frame_count++;
    idx = Math.Int(frame_count / 3) % 12;
    spinner_sprite.SetImage(spinner_frames[idx]);
}
Plymouth.SetRefreshFunction(refresh_callback);

# ─── Progress bar ────────────────────────────────────────────
progress_bg = Image("progress-bg.png");
progress_fg = Image("progress-fg.png");

progress_bg_sprite = Sprite(progress_bg);
progress_bg_x = (screen_w - 300) / 2;
progress_bg_y = (screen_h / 2) + 90;
progress_bg_sprite.SetPosition(progress_bg_x, progress_bg_y, 1);

progress_fg_sprite = Sprite();
progress_fg_sprite.SetPosition(progress_bg_x, progress_bg_y, 2);

fun boot_progress_callback(duration, progress) {
    if (progress >= 0 && progress <= 1) {
        fill_w = Math.Int(300 * progress);
        if (fill_w > 0) {
            fill = progress_fg.Scale(fill_w, 6);
            progress_fg_sprite.SetImage(fill);
        }
    }
}
Plymouth.SetBootProgressFunction(boot_progress_callback);

# ─── Texto de status ─────────────────────────────────────────
status_text = Sprite();
status_text.SetPosition(0, progress_bg_y + 20, 3);

fun status_callback(text) {
    txt_img = Image.Text(text, 0.39, 0.45, 0.56, 1, "Sans 11");
    txt_x = (screen_w - txt_img.GetWidth()) / 2;
    status_text.SetPosition(txt_x, progress_bg_y + 20, 3);
    status_text.SetImage(txt_img);
}
Plymouth.SetUpdateStatusFunction(status_callback);

# ─── Password prompt (disk encryption) ──────────────────────
fun password_callback(prompt, bullets) {
    prompt_img = Image.Text(prompt, 0.39, 0.70, 0.83, 1, "Sans 14");
    prompt_sprite = Sprite(prompt_img);
    prompt_x = (screen_w - prompt_img.GetWidth()) / 2;
    prompt_sprite.SetPosition(prompt_x, (screen_h / 2) + 130, 5);

    bullet_str = "";
    for (i = 0; i < bullets; i++)
        bullet_str += "● ";

    bullet_img = Image.Text(bullet_str, 0.02, 0.72, 0.83, 1, "Sans 18");
    bullet_sprite = Sprite(bullet_img);
    bx = (screen_w - bullet_img.GetWidth()) / 2;
    bullet_sprite.SetPosition(bx, (screen_h / 2) + 160, 5);
}
Plymouth.SetDisplayPasswordFunction(password_callback);

# ─── Quit ────────────────────────────────────────────────────
fun quit_callback() {
    logo_sprite.SetOpacity(0);
    spinner_sprite.SetOpacity(0);
    progress_bg_sprite.SetOpacity(0);
    progress_fg_sprite.SetOpacity(0);
    status_text.SetOpacity(0);
}
Plymouth.SetQuitFunction(quit_callback);
PLYSCRIPT

ok "Tema Plymouth criado"

# ─── Passo 3: Ativar tema ────────────────────────────────────
echo -e "\n${BOLD}[3/3] Ativando tema...${RESET}"
plymouth-set-default-theme -R "$THEME_NAME" 2>/dev/null && \
    ok "Tema '$THEME_NAME' definido como padrão" || \
    warn "Falha ao definir tema — execute manualmente: plymouth-set-default-theme -R $THEME_NAME"

# Verificar hook do mkinitcpio
if [ -f /etc/mkinitcpio.conf ]; then
    if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
        warn "Adicione 'plymouth' ao HOOKS em /etc/mkinitcpio.conf:"
        echo -e "  ${DIM}HOOKS=(base udev plymouth autodetect ...)${RESET}"
        echo -e "  ${DIM}Depois: sudo mkinitcpio -P${RESET}"
    else
        ok "Hook plymouth já presente no mkinitcpio"
    fi
fi

# Verificar quiet splash no GRUB
if [ -f /etc/default/grub ]; then
    if ! grep -q "splash" /etc/default/grub; then
        warn "Adicione 'splash' ao GRUB_CMDLINE_LINUX_DEFAULT em /etc/default/grub"
        echo -e "  ${DIM}Depois: sudo grub-mkconfig -o /boot/grub/grub.cfg${RESET}"
    fi
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  ✅ Plymouth Covenant instalado!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${DIM}Tema:${RESET}   $PLYMOUTH_DIR/"
echo -e "  ${DIM}Testar:${RESET} sudo plymouthd && sudo plymouth show-splash"
echo -e "  ${DIM}Parar:${RESET}  sudo plymouth quit"
echo ""
echo -e "  ${YELLOW}⚠️  Reinicie para ver o splash de boot${RESET}"
echo ""
