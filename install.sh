#!/usr/bin/env bash
# ==============================================================================
#  Ztun — Script de Instalação Automática 1-Liner
# ==============================================================================
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/UlekBR/ztun/refs/heads/main/install.sh | sudo bash
#   ou:
#   wget -qO- https://raw.githubusercontent.com/UlekBR/ztun/refs/heads/main/install.sh | sudo bash
#
# ==============================================================================

set -euo pipefail

# ── Configurações ──────────────────────────────────────────────────────────────
GITHUB_REPO="${GITHUB_REPO:-"UlekBR/ztun"}"
BRANCH="${BRANCH:-"main"}"

INSTALL_DIR="/opt/ztun"
BIN_LINK="/usr/local/bin/ztun-menu"

# LANGUAGE_BEGIN — compartilhado com os testes isolados de seleção/persistência.
LANGUAGE_FILE="${ZTUN_LANGUAGE_FILE:-/etc/ztun/menu-language}"
MENU_LANGUAGE=pt
valid_language() { [[ "$1" == pt || "$1" == en || "$1" == es ]]; }
msg() {
    case "$MENU_LANGUAGE" in
        en) printf '%s' "$2" ;;
        es) printf '%s' "$3" ;;
        *) printf '%s' "$1" ;;
    esac
}
choose_language() {
    local saved="" selected=""
    if [[ -r "$LANGUAGE_FILE" ]]; then
        IFS= read -r saved < "$LANGUAGE_FILE" || true
        if valid_language "$saved"; then MENU_LANGUAGE="$saved"; fi
    fi
    if [[ -n "${ZTUN_LANGUAGE:-}" ]]; then
        if ! valid_language "$ZTUN_LANGUAGE"; then
            printf '%s\n' 'Idioma / Language: pt, en, es' >&2
            return 1
        fi
        MENU_LANGUAGE="$ZTUN_LANGUAGE"
    elif [[ -t 1 ]] && { exec 3<> /dev/tty; } 2>/dev/null; then
        while true; do
            printf '\nIdioma / Language\n  [1] Português\n  [2] English\n  [3] Español\n' >&3
            printf '%s [%s] › ' "$(msg 'Escolha (Enter: manter)' 'Choose (Enter: keep)' 'Elija (Enter: mantener)')" "$MENU_LANGUAGE" >&3
            IFS= read -r -u 3 selected || break
            case "$selected" in
                '') break ;;
                1|pt) MENU_LANGUAGE=pt; break ;;
                2|en) MENU_LANGUAGE=en; break ;;
                3|es) MENU_LANGUAGE=es; break ;;
                *) printf '%s\n' "$(msg 'Opção inválida.' 'Invalid option.' 'Opción no válida.')" >&3 ;;
            esac
        done
        exec 3>&-
    fi
}
save_language() {
    local parent temporary
    parent="$(dirname -- "$LANGUAGE_FILE")"
    mkdir -p -- "$parent"
    temporary="$(mktemp "${LANGUAGE_FILE}.tmp.XXXXXX")"
    if ! printf '%s\n' "$MENU_LANGUAGE" > "$temporary" || ! chmod 644 "$temporary" || ! mv -f -- "$temporary" "$LANGUAGE_FILE"; then
        rm -f -- "$temporary"
        return 1
    fi
}
choose_language
# LANGUAGE_END

# ── Cores para output ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLU}[INFO]${NC}  $*"; }
ok()    { echo -e "${GRN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YLW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERRO]${NC}  $*" >&2; }
die()   { error "$*"; exit 1; }

# ── Verificação de Root ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    die "$(msg "Este script precisa ser executado como root (use: sudo bash ou execute como root)." "This script must run as root (use sudo bash or run as root)." "Este script debe ejecutarse como root (use sudo bash o ejecute como root).")"
fi

# ── Detecção de Sistema e Arquitetura ─────────────────────────────────────────
info "$(msg "Detectando sistema operacional e arquitetura..." "Detecting operating system and architecture..." "Detectando el sistema operativo y la arquitectura...")"

OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
    die "$(msg "O Ztun suporta apenas Linux (detectado: $OS)." "Ztun only supports Linux (detected: $OS)." "Ztun solo admite Linux (detectado: $OS).")"
fi

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    x86_64|amd64)
        ARCH="x86_64"
        ;;
    aarch64|arm64|armv8*)
        ARCH="arm64"
        ;;
    *)
        die "$(msg "Arquitetura não suportada: $ARCH_RAW. O Ztun suporta x86_64 e arm64." "Unsupported architecture: $ARCH_RAW. Ztun supports x86_64 and arm64." "Arquitectura no compatible: $ARCH_RAW. Ztun admite x86_64 y arm64.")"
        ;;
esac

ok "$(msg "Sistema: Linux ($ARCH)" "System: Linux ($ARCH)" "Sistema: Linux ($ARCH)")"

# ── Verificação de Instalação Existente / Atualização ───────────────────────
IS_UPDATE=false
WAS_RUNNING=false
# Até a v0.0.2 o binário do serviço se chamava "xhttp"; foi renomeado para
# "ztun" porque o mesmo processo agora atende HTTP/HTTPS e Binary, não só
# HTTP. Detecta essa instalação antiga para migrar automaticamente abaixo.
LEGACY_XHTTP_BIN="${INSTALL_DIR}/xhttp"
MIGRATING_FROM_XHTTP=false

if [[ -f "${INSTALL_DIR}/ztun" || -f "$LEGACY_XHTTP_BIN" || -f "${INSTALL_DIR}/menu" ]]; then
    IS_UPDATE=true
    info "$(msg "Instalação prévia / atualização do Ztun detectada em ${INSTALL_DIR}." "Existing Ztun installation / update detected at ${INSTALL_DIR}." "Instalación previa / actualización de Ztun detectada en ${INSTALL_DIR}.")"
fi

if [[ -f "$LEGACY_XHTTP_BIN" ]]; then
    MIGRATING_FROM_XHTTP=true
    info "$(msg "Instalação antiga com o binário 'xhttp' detectada — será migrada para 'ztun'." "Legacy installation using 'xhttp' detected — migrating to 'ztun'." "Instalación antigua con el binario 'xhttp' detectada — se migrará a 'ztun'.")"
fi

if systemctl is-active --quiet ztun 2>/dev/null; then
    WAS_RUNNING=true
    info "$(msg "O serviço 'ztun' está em execução no momento." "The 'ztun' service is currently running." "El servicio 'ztun' está en ejecución.")"
fi

# ── Verificação de Dependências (curl ou wget) ─────────────────────────────────
DL_CMD=""
if command -v curl >/dev/null 2>&1; then
    DL_CMD="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
    DL_CMD="wget -q -O"
else
    die "$(msg "Nem 'curl' nem 'wget' foram encontrados. Instale um deles antes de prosseguir." "Neither 'curl' nor 'wget' was found. Install one before continuing." "No se encontró 'curl' ni 'wget'. Instale uno antes de continuar.")"
fi

# ── Obtenção dos Binários via Raw GitHub ──────────────────────────────────────
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/refs/heads/${BRANCH}"
info "$(msg "Baixando binários compilados do repositório ($GITHUB_REPO)..." "Downloading compiled binaries from the repository ($GITHUB_REPO)..." "Descargando binarios compilados del repositorio ($GITHUB_REPO)...")"

# ── Criação de Diretórios ─────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

# ── Download dos Binários ─────────────────────────────────────────────────────
ZTUN_URL="${RAW_BASE_URL}/ztun-${ARCH}"
MENU_URL="${RAW_BASE_URL}/menu-${ARCH}"

info "$(msg "Baixando ztun-$ARCH de $ZTUN_URL..." "Downloading ztun-$ARCH from $ZTUN_URL..." "Descargando ztun-$ARCH de $ZTUN_URL...")"
if ! $DL_CMD "${INSTALL_DIR}/ztun.tmp" "$ZTUN_URL"; then
    rm -f "${INSTALL_DIR}/ztun.tmp"
    die "$(msg "Falha ao baixar ztun-$ARCH de: $ZTUN_URL\nCertifique-se de que os arquivos ztun-${ARCH} e menu-${ARCH} estão na raiz do repositório GitHub." "Failed to download ztun-$ARCH from: $ZTUN_URL\nCheck that ztun-${ARCH} and menu-${ARCH} exist at the GitHub repository root." "Error al descargar ztun-$ARCH de: $ZTUN_URL\nCompruebe que ztun-${ARCH} y menu-${ARCH} estén en la raíz del repositorio GitHub.")"
fi
mv -f "${INSTALL_DIR}/ztun.tmp" "${INSTALL_DIR}/ztun"

info "$(msg "Baixando menu-$ARCH de $MENU_URL..." "Downloading menu-$ARCH from $MENU_URL..." "Descargando menu-$ARCH de $MENU_URL...")"
if ! $DL_CMD "${INSTALL_DIR}/menu.tmp" "$MENU_URL"; then
    rm -f "${INSTALL_DIR}/menu.tmp"
    die "$(msg "Falha ao baixar menu-$ARCH de: $MENU_URL\nCertifique-se de que os arquivos ztun-${ARCH} e menu-${ARCH} estão na raiz do repositório GitHub." "Failed to download menu-$ARCH from: $MENU_URL\nCheck that ztun-${ARCH} and menu-${ARCH} exist at the GitHub repository root." "Error al descargar menu-$ARCH de: $MENU_URL\nCompruebe que ztun-${ARCH} y menu-${ARCH} estén en la raíz del repositorio GitHub.")"
fi
mv -f "${INSTALL_DIR}/menu.tmp" "${INSTALL_DIR}/menu"

# ── Configuração de Permissões e Link Simbólico ────────────────────────────────
chmod +x "${INSTALL_DIR}/ztun" "${INSTALL_DIR}/menu"
ok "$(msg "Permissões de execução aplicadas." "Executable permissions applied." "Permisos de ejecución aplicados.")"

ln -sf "${INSTALL_DIR}/menu" "$BIN_LINK"
ok "$(msg "Atalho criado em $BIN_LINK" "Shortcut created at $BIN_LINK" "Acceso directo creado en $BIN_LINK")"
save_language

# ── Migração de instalações antigas (binário "xhttp" → "ztun") ────────────────
if $MIGRATING_FROM_XHTTP; then
    SERVICE_FILE="/etc/systemd/system/ztun.service"
    if [[ -f "$SERVICE_FILE" ]] && grep -q "ExecStart=.*/xhttp" "$SERVICE_FILE" 2>/dev/null; then
        sed -i "s#ExecStart=.*/xhttp#ExecStart=${INSTALL_DIR}/ztun#" "$SERVICE_FILE"
        systemctl daemon-reload 2>/dev/null || true
        ok "$(msg "Serviço systemd atualizado para usar o novo binário 'ztun'." "systemd service updated to use the new 'ztun' executable." "Servicio systemd actualizado para usar el nuevo binario 'ztun'.")"
    fi
    rm -f "$LEGACY_XHTTP_BIN"
    ok "$(msg "Binário antigo 'xhttp' removido (substituído por 'ztun')." "Old 'xhttp' executable removed (replaced by 'ztun')." "Binario antiguo 'xhttp' eliminado (reemplazado por 'ztun').")"
fi

# Delega a subárvore da unit para os workers, preservando o ExecStart existente.
mkdir -p /etc/systemd/system/ztun.service.d
cat > /etc/systemd/system/ztun.service.d/20-workers.conf <<'ZTUN_WORKERS_UNIT'
[Service]
Delegate=yes
CPUAccounting=yes
MemoryAccounting=yes
KillMode=control-group
ZTUN_WORKERS_UNIT
systemctl daemon-reload

# ── Reinício Automático do Serviço em Atualizações/Reinstalação ──────────────
if $IS_UPDATE || $WAS_RUNNING; then
    if systemctl list-unit-files ztun.service | grep -q ztun.service 2>/dev/null || [[ -f "/etc/systemd/system/ztun.service" ]]; then
        info "$(msg "Atualização/Reinstalação detectada. Reiniciando serviço 'ztun'..." "Update/reinstallation detected. Restarting 'ztun'..." "Actualización/reinstalación detectada. Reiniciando 'ztun'...")"
        systemctl daemon-reload 2>/dev/null || true
        if systemctl restart ztun 2>/dev/null; then
            ok "$(msg "Serviço 'ztun' reiniciado automaticamente com sucesso!" "Service 'ztun' restarted successfully!" "¡Servicio 'ztun' reiniciado correctamente!")"
        else
            warn "$(msg "Não foi possível reiniciar o serviço 'ztun' automaticamente. Verifique com: systemctl status ztun" "Could not restart 'ztun' automatically. Check: systemctl status ztun" "No se pudo reiniciar 'ztun' automáticamente. Revise: systemctl status ztun")"
        fi
    fi
fi

# ── Finalização ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}==============================================================${NC}"
echo -e "${GRN}$(msg "       Ztun instalado com sucesso em ${INSTALL_DIR}!       " "       Ztun installed successfully at ${INSTALL_DIR}!       " "       ¡Ztun instalado correctamente en ${INSTALL_DIR}!       ")${NC}"
echo -e "${GRN}==============================================================${NC}"
echo ""
echo "$(msg "Para iniciar e gerenciar o Ztun, digite simplesmente:" "To start and manage Ztun, run:" "Para iniciar y administrar Ztun, ejecute:")"
echo -e "  ${BLU}ztun-menu${NC}"
echo ""
