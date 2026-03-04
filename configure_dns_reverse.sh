#!/bin/bash
# configure_dns_reverse.sh - Configura zona reversa no DNS do Samba

source "$(dirname "$0")/common.sh"

check_root
check_prereqs dialog samba-tool ip awk hostname systemctl grep

# Arquivo de configuração do Samba
SMB_CONF="/etc/samba/smb.conf"

# Flag para controlar se o Samba foi pausado
SAMBA_PAUSED=false

# Trap para garantir que o Samba seja retomado mesmo em caso de erro
cleanup_samba() {
    if [ "$SAMBA_PAUSED" = true ]; then
        log "Garantindo retomada do serviço Samba..."
        systemctl start samba >/dev/null 2>&1 || true
    fi
}
trap cleanup_samba EXIT

# Função para pausar o Samba
pause_samba() {
    log "Pausando o serviço Samba..."
    systemctl stop samba || error_exit "Falha ao parar o serviço Samba."
    SAMBA_PAUSED=true
    log "Samba pausado com sucesso."
}

# Função para retomar o Samba
resume_samba() {
    log "Retomando o serviço Samba..."
    systemctl start samba || error_exit "Falha ao iniciar o serviço Samba."
    SAMBA_PAUSED=false
    log "Samba retomado com sucesso."
}

# Função para extrair um parâmetro do smb.conf (seção global)
extract_smb_parameter() {
    local param="${1,,}" # converte para minúsculas
    grep -A 1000 "^\[global\]" "$SMB_CONF" | grep -i "^$param\s*=" | sed 's/.*=\s*//;s/\s*$//' | head -1
}

# Função para verificar se um parâmetro existe no smb.conf
check_smb_parameter() {
    local param="$1"
    grep -A 1000 "^\[global\]" "$SMB_CONF" | grep -iq "^$param\s*=" && return 0 || return 1
}

# Função para verificar configurações do smb.conf para DNS Reverso
verify_smb_conf() {
    local missing_params=()
    
    log "Verificando configurações de DNS Reverso no $SMB_CONF..."
    
    # Parâmetros obrigatórios para DNS reverso
    local required_params=(
        "server role"
        "realm"
        "netbios name"
        "workgroup"
        "interfaces"
        "bind interfaces only"
    )
    
    info_box "Iniciando verificação de configuração do smb.conf para DNS Reverso.\n\nSerão verificados os seguintes parâmetros:\n• server role\n• realm\n• netbios name\n• workgroup\n• interfaces\n• bind interfaces only"
    
    # Verifica cada parâmetro
    for param in "${required_params[@]}"; do
        if ! check_smb_parameter "$param"; then
            missing_params+=("$param")
        fi
    done
    
    # Exibe resultado
    if [ ${#missing_params[@]} -eq 0 ]; then
        info_box "✓ Todas as configurações obrigatórias foram encontradas no smb.conf!"
        log "Verificação OK: Todas as configurações estão presentes."
        return 0
    else
        local error_msg="As seguintes configurações estão FALTANDO no smb.conf:\n\n"
        for param in "${missing_params[@]}"; do
            error_msg+="• $param\n"
        done
        error_msg+="\nPor favor, adicione estas configurações antes de continuar."
        info_box "$error_msg"
        log "FALHA na verificação: Parâmetros faltando: ${missing_params[*]}"
        return 1
    fi
}

# Função para mostrar configurações atuais
show_current_config() {
    clear
    log "Configurações atuais do smb.conf [global]:"
    echo "=========================================="
    
    local params=(
        "server role"
        "realm"
        "netbios name"
        "workgroup"
        "interfaces"
        "bind interfaces only"
        "dns forwarder"
        "ad dc functional level"
        "idmap_ldb:use rfc2307"
    )
    
    for param in "${params[@]}"; do
        local value=$(extract_smb_parameter "$param")
        if [ -n "$value" ]; then
            printf "%-30s = %s\n" "$param" "$value"
        else
            printf "%-30s = [NÃO CONFIGURADO]\n" "$param"
        fi
    done
    echo "=========================================="
}

# ========== VERIFICAÇÃO INICIAL ==========
# Verifica se o smb.conf existe
if [ ! -f "$SMB_CONF" ]; then
    error_exit "Arquivo $SMB_CONF não encontrado. Verifique a instalação do Samba."
fi

# Pausa o serviço Samba
pause_samba

# Mostra configuração atual
show_current_config

# Verifica as configurações do smb.conf
verify_smb_conf || error_exit "Configure o smb.conf conforme o exemplo fornecido e tente novamente."

log "Todas as verificações iniciais passaram com sucesso!"

# ==========================================

# Obtém informações da rede
exec 3>&1
NETWORK=$(dialog --stdout --title "Rede para DNS Reverso" \
    --inputbox "Digite a rede no formato CIDR (ex: 192.168.1.0/24):" 8 50)
[ -z "$NETWORK" ] && error_exit "Rede não informada."
# validação básica CIDR
if ! [[ "$NETWORK" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    error_exit "Formato de rede inválido. Use algo como 192.168.1.0/24."
fi

# Converte a rede para zona reversa (ex: 1.168.192.in-addr.arpa)
IP_PREFIX=$(echo "$NETWORK" | cut -d/ -f1 | awk -F. '{print $3"."$2"."$1}')
ZONE="${IP_PREFIX}.in-addr.arpa"

# Verifica se a zona já existe
HOST=$(hostname -f)
if samba-tool -U Administrator dns zoneinfo "$HOST" "$ZONE" >/dev/null 2>&1; then
    confirm_box "A zona reversa $ZONE já existe. Deseja recriá-la?"
    if [ $? -eq 0 ]; then
        samba-tool dns zone delete "$HOST" "$ZONE" -U Administrator
    else
        info_box "Operação cancelada."
        exit 0
    fi
fi

# Cria a zona
log "Criando zona reversa $ZONE..."
samba-tool -U Administrator dns zonecreate "$HOST" "$ZONE"
if [ $? -ne 0 ]; then
    error_exit "Falha ao criar zona reversa."
fi

# Obtém o IP do servidor (assumindo que a interface configurada tem o IP)
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)
if [ -z "$SERVER_IP" ]; then
    error_exit "Não foi possível determinar o IP do servidor."
fi

# Extrai o último octeto e adiciona registro PTR
LAST_OCTET=$(echo "$SERVER_IP" | awk -F. '{print $4}')
HOSTNAME_FQDN=$(hostname -f)

log "Adicionando registro PTR para $HOSTNAME_FQDN ($SERVER_IP)..."
samba-tool -U Administrator dns add "$HOST" "$ZONE" "$LAST_OCTET" PTR "$HOSTNAME_FQDN"
if [ $? -eq 0 ]; then
    # Retoma o serviço Samba
    resume_samba
    info_box "Zona reversa $ZONE criada e registro PTR adicionado para $HOSTNAME_FQDN."
    log "Configuração concluída com sucesso!"
else
    # Retoma o serviço mesmo em caso de erro
    resume_samba
    error_exit "Falha ao adicionar registro PTR."
fi