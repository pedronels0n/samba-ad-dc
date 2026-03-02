#!/bin/bash
# common.sh - Funções compartilhadas entre os scripts de configuração do Samba DC
# Esta biblioteca é "source" por todos os scripts; portanto, qualquer opção
# de shell definida aqui é herdada pelos demais.

# Strict mode para evitar erros silenciosos
set -euo pipefail
# reporta a linha em que ocorrer um erro e interrompe a execução
trap 'error_exit "Erro inesperado no script ${BASH_SOURCE[1]:-$(basename "$0")} na linha $LINENO"' ERR

# Cores para output (opcional, usado em mensagens)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Diretório base (onde os scripts estão)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arquivo de log
LOG_FILE="${SCRIPT_DIR}/samba-setup.log"

# Diretórios e configurações globais reutilizáveis
CA_DIR="${CA_DIR:-/root/samba-ca}"       # local padrão para CA e certificados
BACKUP_DIR="${BACKUP_DIR:-/opt/samba_backups}"  # diretório padrão de backups

# Helper para verificar dependências
require_command() {
    if ! command -v "$1" &>/dev/null; then
        error_exit "Comando '$1' não encontrado. Instale-o antes de continuar."
    fi
}

# Verifica uma lista de comandos
check_prereqs() {
    for cmd in "$@"; do
        require_command "$cmd"
    done
}


# Função para log com timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Função para exibir mensagem de erro e sair
error_exit() {
    echo -e "${RED}ERRO: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Função para verificar se o script está sendo executado como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "Este script deve ser executado como root."
    fi
}

# Função para verificar se o dialog está instalado
check_dialog() {
    if ! command -v dialog &> /dev/null; then
        echo "Dialog não está instalado. Deseja instalá-lo? (s/n)"
        read -r answer
        if [[ "$answer" =~ ^[Ss]$ ]]; then
            apt-get update && apt-get install -y dialog || error_exit "Falha ao instalar dialog."
        else
            error_exit "Dialog é necessário para a interface interativa. Abortando."
        fi
    fi
}

# Função para exibir mensagem de informação com dialog
info_box() {
    dialog --title "Informação" --msgbox "$1" 8 50
}

# Função para exibir mensagem de confirmação (sim/não)
confirm_box() {
    dialog --title "Confirmação" --yesno "$1" 7 50
    return $?
}