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
    die "Este script precisa ser executado como root (use: sudo bash ou execute como root)."
fi

# ── Detecção de Sistema e Arquitetura ─────────────────────────────────────────
info "Detectando sistema operacional e arquitetura..."

OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
    die "O Ztun suporta apenas Linux (detectado: $OS)."
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
        die "Arquitetura não suportada: $ARCH_RAW. O Ztun suporta x86_64 e arm64."
        ;;
esac

ok "Sistema: Linux ($ARCH)"

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
    info "Instalação prévia / atualização do Ztun detectada em ${INSTALL_DIR}."
fi

if [[ -f "$LEGACY_XHTTP_BIN" ]]; then
    MIGRATING_FROM_XHTTP=true
    info "Instalação antiga com o binário 'xhttp' detectada — será migrada para 'ztun'."
fi

if systemctl is-active --quiet ztun 2>/dev/null; then
    WAS_RUNNING=true
    info "O serviço 'ztun' está em execução no momento."
fi

# ── Verificação de Dependências (curl ou wget) ─────────────────────────────────
DL_CMD=""
if command -v curl >/dev/null 2>&1; then
    DL_CMD="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
    DL_CMD="wget -q -O"
else
    die "Nem 'curl' nem 'wget' foram encontrados. Instale um deles antes de prosseguir."
fi

# ── Obtenção dos Binários via Raw GitHub ──────────────────────────────────────
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/refs/heads/${BRANCH}"
info "Baixando binários compilados do repositório ($GITHUB_REPO)..."

# ── Criação de Diretórios ─────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

# ── Download dos Binários ─────────────────────────────────────────────────────
ZTUN_URL="${RAW_BASE_URL}/ztun-${ARCH}"
MENU_URL="${RAW_BASE_URL}/menu-${ARCH}"

info "Baixando ztun-$ARCH de $ZTUN_URL..."
if ! $DL_CMD "${INSTALL_DIR}/ztun.tmp" "$ZTUN_URL"; then
    rm -f "${INSTALL_DIR}/ztun.tmp"
    die "Falha ao baixar ztun-$ARCH de: $ZTUN_URL\nCertifique-se de que os arquivos ztun-${ARCH} e menu-${ARCH} estão na raiz do repositório GitHub."
fi
mv -f "${INSTALL_DIR}/ztun.tmp" "${INSTALL_DIR}/ztun"

info "Baixando menu-$ARCH de $MENU_URL..."
if ! $DL_CMD "${INSTALL_DIR}/menu.tmp" "$MENU_URL"; then
    rm -f "${INSTALL_DIR}/menu.tmp"
    die "Falha ao baixar menu-$ARCH de: $MENU_URL\nCertifique-se de que os arquivos ztun-${ARCH} e menu-${ARCH} estão na raiz do repositório GitHub."
fi
mv -f "${INSTALL_DIR}/menu.tmp" "${INSTALL_DIR}/menu"

# ── Configuração de Permissões e Link Simbólico ────────────────────────────────
chmod +x "${INSTALL_DIR}/ztun" "${INSTALL_DIR}/menu"
ok "Permissões de execução aplicadas."

ln -sf "${INSTALL_DIR}/menu" "$BIN_LINK"
ok "Atalho criado em $BIN_LINK"

# ── Migração de instalações antigas (binário "xhttp" → "ztun") ────────────────
if $MIGRATING_FROM_XHTTP; then
    SERVICE_FILE="/etc/systemd/system/ztun.service"
    if [[ -f "$SERVICE_FILE" ]] && grep -q "ExecStart=.*/xhttp" "$SERVICE_FILE" 2>/dev/null; then
        sed -i "s#ExecStart=.*/xhttp#ExecStart=${INSTALL_DIR}/ztun#" "$SERVICE_FILE"
        systemctl daemon-reload 2>/dev/null || true
        ok "Serviço systemd atualizado para usar o novo binário 'ztun'."
    fi
    rm -f "$LEGACY_XHTTP_BIN"
    ok "Binário antigo 'xhttp' removido (substituído por 'ztun')."
fi

# ── Reinício Automático do Serviço em Atualizações/Reinstalação ──────────────
if $IS_UPDATE || $WAS_RUNNING; then
    if systemctl list-unit-files ztun.service | grep -q ztun.service 2>/dev/null || [[ -f "/etc/systemd/system/ztun.service" ]]; then
        info "Atualização/Reinstalação detectada. Reiniciando serviço 'ztun'..."
        systemctl daemon-reload 2>/dev/null || true
        if systemctl restart ztun 2>/dev/null; then
            ok "Serviço 'ztun' reiniciado automaticamente com sucesso!"
        else
            warn "Não foi possível reiniciar o serviço 'ztun' automaticamente. Verifique com: systemctl status ztun"
        fi
    fi
fi

# ── Finalização ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}==============================================================${NC}"
echo -e "${GRN}       Ztun instalado com sucesso em ${INSTALL_DIR}!       ${NC}"
echo -e "${GRN}==============================================================${NC}"
echo ""
echo "Para iniciar e gerenciar o Ztun, digite simplesmente:"
echo -e "  ${BLU}ztun-menu${NC}"
echo ""
