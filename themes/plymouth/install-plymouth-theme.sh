#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Covenant Plymouth Theme — Instalador
#  Splash de boot e shutdown com logo Covenant sem fundo (transparente)
#  e spinner cyan animado em tela preta pura.
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
echo -e "\n${BOLD}[2/3] Preparando assets com transparência...${RESET}"
mkdir -p "$PLYMOUTH_DIR"

# Procurar logo original
LOGO_SRC=""
for p in "$SCRIPT_DIR/../../assets/covenant-logo.png" \
         "$SCRIPT_DIR/../assets/covenant-logo.png" \
         "/home/$SUDO_USER/Covenant-CachyOS-main/assets/covenant-logo.png" \
         "/home/$SUDO_USER/Kernel/covenant-logo.png"; do
    if [ -f "$p" ]; then
        LOGO_SRC="$p"
        break
    fi
done

if [ -n "$LOGO_SRC" ] && [ -f "$LOGO_SRC" ]; then
    CMD=$(command -v magick || command -v convert || echo "")
    if [ -n "$CMD" ]; then
        # IMPORTANTE: Preservar 100% da transparência do canal alpha (PNG32 sem fundo)
        $CMD "$LOGO_SRC" -resize 450x150 -background none PNG32:"$PLYMOUTH_DIR/covenant-logo.png"
        ok "Logo Covenant gerada com fundo transparente (PNG32)"
    else
        cp "$LOGO_SRC" "$PLYMOUTH_DIR/covenant-logo.png"
        warn "ImageMagick ausente — logo copiada diretamente"
    fi
else
    warn "Logo não encontrada em assets/ — tema usará texto"
fi

# Gerar background preto puro (seamless em qualquer monitor/resolução)
CMD=$(command -v magick || command -v convert || echo "")
if [ -n "$CMD" ]; then
    $CMD -size 1920x1080 xc:"#000000" "$PLYMOUTH_DIR/background.png"
    ok "Background preto puro gerado"

    # Spinner frames (12 frames de anel cyan girando com fundo transparente)
    for i in $(seq 0 11); do
        ANGLE=$((i * 30))
        $CMD -size 48x48 xc:none \
            -fill none -stroke "#06b6d4" -strokewidth 3 \
            -draw "arc 4,4 44,44 $ANGLE,$((ANGLE+90))" \
            -fill none -stroke "#1e293b" -strokewidth 3 \
            -draw "arc 4,4 44,44 $((ANGLE+120)),$((ANGLE+360))" \
            PNG32:"$PLYMOUTH_DIR/spinner-$(printf '%02d' $i).png"
    done
    ok "Spinner: 12 frames transparentes gerados"

    # Barra de progresso para o boot
    $CMD -size 300x6 xc:"#1e293b" PNG32:"$PLYMOUTH_DIR/progress-bg.png"
    $CMD -size 300x6 \
        -define gradient:direction=east \
        gradient:"#0e7490-#06b6d4" \
        PNG32:"$PLYMOUTH_DIR/progress-fg.png"
    ok "Barra de progresso gerada"
else
    warn "ImageMagick ausente"
fi

# Plymouth theme descriptor
cat > "$PLYMOUTH_DIR/$THEME_NAME.plymouth" << EOF
[Plymouth Theme]
Name=Covenant
Description=Covenant-CachyOS boot and shutdown splash — clean transparent logo with cyan spinner
ModuleName=script

[script]
ImageDir=$PLYMOUTH_DIR
ScriptFile=$PLYMOUTH_DIR/$THEME_NAME.script
EOF

# Plymouth script
cat > "$PLYMOUTH_DIR/$THEME_NAME.script" << 'PLYSCRIPT'
# ═══════════════════════════════════════════════════════════════
#  Covenant Plymouth Script
#  Fundo preto puro + logo Covenant 100% transparente + spinner cyan
# ═══════════════════════════════════════════════════════════════

# Dimensões da tela
screen_w = Window.GetWidth();
screen_h = Window.GetHeight();

# ─── Background (Preto puro) ──────────────────────────────────
bg = Image("background.png");
bg_sprite = Sprite();
bg_sprite.SetPosition(0, 0, -100);
if (bg) {
    bg_sprite.SetImage(bg.Scale(screen_w, screen_h));
}

# Modo de execução: "boot", "shutdown", "reboot"
mode = Plymouth.GetMode();
is_shutdown = (mode == "shutdown" || mode == "reboot");

# ─── Logo (Sem fundo / Transparente) ──────────────────────────
logo = Image("covenant-logo.png");
logo_sprite = Sprite();
if (logo) {
    logo_sprite.SetImage(logo);
    logo_x = (screen_w - logo.GetWidth()) / 2;
    logo_y = (screen_h / 2) - logo.GetHeight() - 25;
    logo_sprite.SetPosition(logo_x, logo_y, 1);
}

# ─── Spinner Cyan Animado ─────────────────────────────────────
spinner_frames = [];
for (i = 0; i < 12; i++) {
    if (i < 10)
        spinner_frames[i] = Image("spinner-0" + i + ".png");
    else
        spinner_frames[i] = Image("spinner-" + i + ".png");
}
spinner_sprite = Sprite(spinner_frames[0]);
spinner_x = (screen_w - 48) / 2;
spinner_y = (screen_h / 2) + 25;
spinner_sprite.SetPosition(spinner_x, spinner_y, 2);

frame_count = 0;

fun refresh_callback() {
    frame_count++;
    idx = Math.Int(frame_count / 3) % 12;
    spinner_sprite.SetImage(spinner_frames[idx]);
}
Plymouth.SetRefreshFunction(refresh_callback);

# ─── Barra de Progresso (Apenas no Boot) ───────────────────────
progress_bg = Image("progress-bg.png");
progress_fg = Image("progress-fg.png");

progress_bg_sprite = Sprite();
progress_fg_sprite = Sprite();

if (!is_shutdown && progress_bg && progress_fg) {
    progress_bg_sprite.SetImage(progress_bg);
    progress_bg_x = (screen_w - 300) / 2;
    progress_bg_y = (screen_h / 2) + 90;
    progress_bg_sprite.SetPosition(progress_bg_x, progress_bg_y, 1);
    progress_fg_sprite.SetPosition(progress_bg_x, progress_bg_y, 2);
}

fun boot_progress_callback(duration, progress) {
    if (!is_shutdown && progress >= 0 && progress <= 1 && progress_fg) {
        fill_w = Math.Int(300 * progress);
        if (fill_w > 0) {
            fill = progress_fg.Scale(fill_w, 6);
            progress_fg_sprite.SetImage(fill);
        }
    }
}
Plymouth.SetBootProgressFunction(boot_progress_callback);

# ─── Texto de Status ──────────────────────────────────────────
status_text = Sprite();
status_y = (screen_h / 2) + 85;

fun status_callback(text) {
    txt_img = Image.Text(text, 0.39, 0.70, 0.83, 1, "Sans 11");
    txt_x = (screen_w - txt_img.GetWidth()) / 2;
    status_text.SetPosition(txt_x, status_y, 3);
    status_text.SetImage(txt_img);
}
Plymouth.SetUpdateStatusFunction(status_callback);

# ─── Mensagem de Desligamento / Reinicialização ───────────────
if (is_shutdown) {
    msg = (mode == "reboot") ? "Reiniciando Covenant-CachyOS..." : "Desligando Covenant-CachyOS...";
    status_img = Image.Text(msg, 0.39, 0.45, 0.56, 1, "Sans 11");
    status_x = (screen_w - status_img.GetWidth()) / 2;
    shutdown_text = Sprite(status_img);
    shutdown_text.SetPosition(status_x, status_y, 3);
}

# ─── Senha LUKS (Criptografia) ────────────────────────────────
fun password_callback(prompt, bullets) {
    prompt_img = Image.Text(prompt, 0.39, 0.70, 0.83, 1, "Sans 14");
    prompt_sprite = Sprite(prompt_img);
    prompt_x = (screen_w - prompt_img.GetWidth()) / 2;
    prompt_sprite.SetPosition(prompt_x, (screen_h / 2) + 120, 5);

    bullet_str = "";
    for (i = 0; i < bullets; i++)
        bullet_str += "● ";

    bullet_img = Image.Text(bullet_str, 0.02, 0.72, 0.83, 1, "Sans 18");
    bullet_sprite = Sprite(bullet_img);
    bx = (screen_w - bullet_img.GetWidth()) / 2;
    bullet_sprite.SetPosition(bx, (screen_h / 2) + 150, 5);
}
Plymouth.SetDisplayPasswordFunction(password_callback);

# ─── Encerramento Suave ───────────────────────────────────────
fun quit_callback() {
    if (logo_sprite) logo_sprite.SetOpacity(0);
    if (spinner_sprite) spinner_sprite.SetOpacity(0);
    if (progress_bg_sprite) progress_bg_sprite.SetOpacity(0);
    if (progress_fg_sprite) progress_fg_sprite.SetOpacity(0);
    if (status_text) status_text.SetOpacity(0);
}
Plymouth.SetQuitFunction(quit_callback);
PLYSCRIPT

ok "Tema Plymouth atualizado com suporte a transparência"

# ─── Passo 3: Ativar tema e Reconstruir Initramfs ─────────────
echo -e "\n${BOLD}[3/3] Aplicando tema e atualizando initramfs...${RESET}"
plymouth-set-default-theme -R "$THEME_NAME" 2>/dev/null && \
    ok "Tema '$THEME_NAME' definido e initramfs atualizado!" || \
    warn "Execute manualmente para aplicar: plymouth-set-default-theme -R $THEME_NAME"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  ✅ Plymouth Covenant Transparente Instalado!${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${DIM}Tema:${RESET}   $PLYMOUTH_DIR/"
echo -e "  ${DIM}Logo:${RESET}   Fundo 100% transparente (sem caixas ou bordas)"
echo -e "  ${DIM}Fundo:${RESET}  Preto puro (seamless)"
echo ""
