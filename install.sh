#!/usr/bin/env bash
# ==============================================================================
#  Ztun — Script de Instalação Automática 1-Liner
# ==============================================================================
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main/install.sh | sudo bash
#   ou:
#   wget -qO- https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main/install.sh | sudo bash
#
# ==============================================================================

set -euo pipefail

# ── Configurações ──────────────────────────────────────────────────────────────
# Altere para o seu repositório GitHub público no formato "usuario/repositorio"
GITHUB_REPO="${GITHUB_REPO:-"UlekBR/ztun"}"

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

# ── Verificação de Dependências (curl ou wget) ─────────────────────────────────
DL_CMD=""
if command -v curl >/dev/null 2>&1; then
    DL_CMD="curl -sSL -o"
elif command -v wget >/dev/null 2>&1; then
    DL_CMD="wget -q -O"
else
    die "Nem 'curl' nem 'wget' foram encontrados. Instale um deles antes de prosseguir."
fi

# ── Obtenção da Última Tag / Release ──────────────────────────────────────────
info "Buscando a última versão publicada no GitHub ($GITHUB_REPO)..."

RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/latest/download"

# ── Criação de Diretórios ─────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

# ── Download dos Binários ─────────────────────────────────────────────────────
XHTTP_URL="${RELEASE_URL}/xhttp-${ARCH}"
MENU_URL="${RELEASE_URL}/menu-${ARCH}"

info "Baixando xhttp ($ARCH)..."
if ! $DL_CMD "${INSTALL_DIR}/xhttp" "$XHTTP_URL"; then
    die "Falha ao baixar xhttp de: $XHTTP_URL\nVerifique se a Release foi publicada no GitHub."
fi

info "Baixando menu ($ARCH)..."
if ! $DL_CMD "${INSTALL_DIR}/menu" "$MENU_URL"; then
    die "Falha ao baixar menu de: $MENU_URL\nVerifique se a Release foi publicada no GitHub."
fi

# ── Configuração de Permissões e Link Simbólico ────────────────────────────────
chmod +x "${INSTALL_DIR}/xhttp" "${INSTALL_DIR}/menu"
ok "Permissões de execução aplicadas."

ln -sf "${INSTALL_DIR}/menu" "$BIN_LINK"
ok "Atalho criado em $BIN_LINK"

# ── Finalização ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}==============================================================${NC}"
echo -e "${GRN}       Ztun instalado com sucesso em ${INSTALL_DIR}!       ${NC}"
echo -e "${GRN}==============================================================${NC}"
echo ""
echo "Para iniciar e gerenciar o Ztun, digite simplesmente:"
echo -e "  ${BLU}menu${NC}"
echo ""
