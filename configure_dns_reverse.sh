#!/bin/bash
# configure_dns_reverse.sh - Configura zona reversa no DNS do Samba

source "$(dirname "$0")/common.sh"

check_root
check_prereqs dialog samba-tool ip awk hostname grep systemctl

# Arquivo de configuração do Samba
SMB_CONF="/etc/samba/smb.conf"

# Flag para controlar se o Samba foi pausado
SAMBA_PAUSED=false

# Credenciais do administrador
ADMIN_USER="${ADMIN_USER:-Administrator}"

# Solicita a senha do administrador NO INÍCIO do script
exec 3>&1
ADMIN_PASS=$(dialog --stdout --title "Senha do Administrador" \
    --passwordbox "Digite a senha do usuário $ADMIN_USER:" 8 50)
[ -z "$ADMIN_PASS" ] && error_exit "Senha não informada."

# Função para executar samba-tool com autenticação (sem expor a senha no ps)
export PASSWD="$ADMIN_PASS"
samba_tool_auth() {
    # Usando variável de ambiente para esconder a senha do ps
    SAMBA_TOOL_PASSWORD="$PASSWD" samba-tool "$@" -U "$ADMIN_USER" --password="$PASSWD"
}

# Testa a autenticação antes de prosseguir (verifica se Samba está rodando)
log "Verificando se o serviço Samba está ativo..."
if ! systemctl is-active --quiet samba; then
    log "Samba não está ativo. Iniciando serviço..."
    systemctl start samba || error_exit "Falha ao iniciar Samba."
    sleep 3
fi

log "Testando autenticação com o Samba..."
if ! samba_tool_auth domain info 127.0.0.1 >/dev/null 2>&1; then
    error_exit "Falha na autenticação. Verifique a senha do administrador ou se o Samba está rodando corretamente."
fi
log "Autenticação bem-sucedida!"

# Trap para garantir que o Samba seja retomado em caso de erro
cleanup_samba() {
    if [ "$SAMBA_PAUSED" = true ]; then
        log "Retomando o serviço Samba..."
        systemctl start samba >/dev/null 2>&1 || true
    fi
}
trap cleanup_samba EXIT

# Função para pausar o Samba
pause_samba() {
    log "Pausando o serviço Samba..."
    systemctl stop samba || error_exit "Falha ao parar o serviço Samba."
    SAMBA_PAUSED=true
    sleep 2
    log "Samba pausado com sucesso."
}

# Função para retomar o Samba
resume_samba() {
    log "Retomando o serviço Samba..."
    systemctl start samba || error_exit "Falha ao iniciar o serviço Samba."
    SAMBA_PAUSED=false
    sleep 3  # Aguarda serviço iniciar completamente
    log "Samba retomado com sucesso."
}

# Função para mostrar configurações atuais
show_current_config() {
    clear
    log "Configurações atuais do smb.conf [global]:"
    echo "=========================================="
    sed -n '/^\[global\]/,/^\[/p' "$SMB_CONF" | head -n -1
    echo "=========================================="
}

# ========== VERIFICAÇÃO INICIAL ==========
# Verifica se o smb.conf existe
if [ ! -f "$SMB_CONF" ]; then
    error_exit "Arquivo $SMB_CONF não encontrado. Verifique a instalação do Samba."
fi

# Mostra configuração atual
show_current_config

log "Iniciando configuração de DNS Reverso..."

# IMPORTANTE: NÃO pausamos o Samba para operações de DNS
# As operações de DNS precisam do serviço rodando
log "NOTA: O serviço Samba continuará ativo durante a configuração do DNS."

# ==========================================

# Obtém informações da rede
exec 3>&1
NETWORK=$(dialog --stdout --title "Rede para DNS Reverso" \
    --inputbox "Digite a rede no formato CIDR (ex: 192.168.1.0/24):" 8 50)
[ -z "$NETWORK" ] && error_exit "Rede não informada."

# Validação básica CIDR
if ! [[ "$NETWORK" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    error_exit "Formato de rede inválido. Use algo como 192.168.1.0/24."
fi

# Extrai a parte da rede (ex: 192.168.1.0)
NETWORK_IP=$(echo "$NETWORK" | cut -d/ -f1)

# Converte a rede para zona reversa (ex: 1.168.192.in-addr.arpa)
# Pega o 3º, 2º e 1º octetos em ordem reversa
IP_PREFIX=$(echo "$NETWORK_IP" | awk -F. '{print $3"."$2"."$1}')
ZONE="${IP_PREFIX}.in-addr.arpa"

# Verifica se a zona já existe
HOST=$(hostname -f)
log "Verificando se a zona $ZONE já existe..."

# Tenta listar a zona para verificar se existe
if samba_tool_auth dns zonelist "$HOST" | grep -q "$ZONE"; then
    log "Zona $ZONE encontrada."
    
    # Pergunta ao usuário se deseja recriar
    exec 3>&1
    RECREATE=$(dialog --stdout --title "Zona já existe" \
        --yesno "A zona reversa $ZONE já existe. Deseja recriá-la?" 7 50)
    RECREATE_RESULT=$?
    
    if [ $RECREATE_RESULT -eq 0 ]; then
        log "Removendo zona existente $ZONE..."
        if ! samba_tool_auth dns zone delete "$HOST" "$ZONE"; then
            error_exit "Falha ao remover zona existente."
        fi
        sleep 2  # Aguarda remoção
    else
        info_box "Operação cancelada."
        exit 0
    fi
else
    log "Zona $ZONE não existe. Prosseguindo com criação..."
fi

# Cria a zona
log "Criando zona reversa $ZONE..."
if ! samba_tool_auth dns zonecreate "$HOST" "$ZONE"; then
    error_exit "Falha ao criar zona reversa."
fi
log "Zona reversa $ZONE criada com sucesso!"

# Aguarda propagação da zona
sleep 2

# Obtém o IP do servidor
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)
if [ -z "$SERVER_IP" ]; then
    error_exit "Não foi possível determinar o IP do servidor."
fi

# Extrai o último octeto e adiciona registro PTR
LAST_OCTET=$(echo "$SERVER_IP" | awk -F. '{print $4}')
HOSTNAME_FQDN=$(hostname -f)

log "Adicionando registro PTR para $HOSTNAME_FQDN ($SERVER_IP)..."
if samba_tool_auth dns add "$HOST" "$ZONE" "$LAST_OCTET" PTR "$HOSTNAME_FQDN"; then
    log "Registro PTR adicionado com sucesso!"
    
    # Verifica se o registro foi realmente adicionado
    log "Verificando registro criado..."
    sleep 2  # Pequena pausa para propagação
    
    if samba_tool_auth dns query "$HOST" "$ZONE" "$LAST_OCTET" PTR >/dev/null 2>&1; then
        log "Verificação bem-sucedida: registro PTR encontrado."
    else
        log "Aviso: Não foi possível verificar o registro PTR imediatamente."
        log "Listando registros da zona:"
        samba_tool_auth dns query "$HOST" "$ZONE" @ ALL
    fi
    
    # Mostra informações da zona criada
    echo
    log "=== CONFIGURAÇÃO CONCLUÍDA COM SUCESSO! ==="
    log "Zona reversa: $ZONE"
    log "Registro PTR: $LAST_OCTET -> $HOSTNAME_FQDN"
    log "IP do servidor: $SERVER_IP"
    echo
    
    # Testes de resolução
    log "Testando resolução direta:"
    nslookup "$HOSTNAME_FQDN" 127.0.0.1 2>/dev/null | grep -A2 "Name:" || log "Aguardando propagação do DNS..."
    
    log "Testando resolução reversa:"
    nslookup "$SERVER_IP" 127.0.0.1 2>/dev/null | grep -A2 "in-addr.arpa" || log "Aguardando propagação do DNS..."
    
    info_box "Zona reversa $ZONE criada com sucesso!\n\nRegistro PTR adicionado:\n$LAST_OCTET -> $HOSTNAME_FQDN\nIP do servidor: $SERVER_IP\n\nTestes de DNS foram executados no console."
    
    log "Configuração concluída com sucesso!"
else
    error_exit "Falha ao adicionar registro PTR."
fi

exit 0