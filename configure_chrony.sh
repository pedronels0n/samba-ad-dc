#!/bin/bash
# configure_chrony.sh - Configura o Chrony para sincronização de tempo
# com servidores NTP brasileiros e allow para a rede local

source "$(dirname "$0")/common.sh"

# Verifica root
check_root
check_prereqs chronyd dialog mkdir chown chmod systemctl

# Verifica se o chrony está instalado
if ! command -v chronyd &> /dev/null; then
    error_exit "Chrony não está instalado. Execute primeiro a instalação de pacotes."
fi

# Solicita a rede local para allow (formato CIDR, ex: 192.168.1.0/24)
exec 3>&1
LOCAL_NET=$(dialog --stdout --title "Rede Local para sincronização NTP" \
    --inputbox "Digite a rede local que poderá sincronizar com este servidor NTP (formato CIDR, ex: 192.168.1.0/24):" 10 60)
if [ -z "$LOCAL_NET" ]; then
    error_exit "Rede não informada. O chrony será configurado sem permissão de acesso de clientes."
fi

# Validação básica do formato CIDR
if ! [[ "$LOCAL_NET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    error_exit "Formato inválido. Use CIDR (ex: 192.168.1.0/24)."
fi

# Define os servidores NTP brasileiros (podem ser adicionados mais)
NTP_SERVERS=(
    "a.st1.ntp.br"
    "b.st1.ntp.br"
    "c.st1.ntp.br"
    "ntp.ufsc.br"
)

# Backup do arquivo de configuração original
CONF_FILE="/etc/chrony/chrony.conf"
BACKUP_FILE="${CONF_FILE}.bak.$(date +%Y%m%d%H%M%S)"
if [ -f "$CONF_FILE" ]; then
    cp "$CONF_FILE" "$BACKUP_FILE"
    log "Backup de $CONF_FILE criado em $BACKUP_FILE"
fi

# Gera novo arquivo de configuração
{
    echo "# Configuração gerada por script de Samba DC"
    echo "# Servidores NTP públicos brasileiros"
    for server in "${NTP_SERVERS[@]}"; do
        echo "pool $server iburst"
    done
    
    echo ""
    echo "# Permitir sincronização para a rede local"
    echo "allow $LOCAL_NET"
    
    echo ""
    echo "# Diretório de drift e arquivos de log"
    echo "driftfile /var/lib/chrony/chrony.drift"
    echo "makestep 1.0 3"
    echo "rtcsync"
    echo "logdir /var/log/chrony"
    
    echo ""
    echo "# Configuração para ntp_signd (Samba AD DC)"
    echo "ntpsigndsocket /var/lib/samba/ntp_signd"
    
} > "$CONF_FILE"

log "Arquivo $CONF_FILE gerado com servidores NTP brasileiros e allow $LOCAL_NET."

# Ajusta permissões do diretório ntp_signd (criado pelo Samba durante provisionamento)
# Se ainda não existir, criaremos com as permissões corretas para o futuro
NTP_SIGND_DIR="/var/lib/samba/ntp_signd"
if [ ! -d "$NTP_SIGND_DIR" ]; then
    mkdir -p "$NTP_SIGND_DIR"
    log "Diretório $NTP_SIGND_DIR criado."
fi

# Verifica se o grupo _chrony existe; cria se não existir
if ! getent group _chrony > /dev/null; then
    log "Grupo _chrony não encontrado. Criando..."
    groupadd -r _chrony || log "Falha ao criar grupo _chrony"
fi

# Ajusta proprietário e permissões (será ajustado novamente após provisionamento)
chown -f root:_chrony "$NTP_SIGND_DIR" 2>/dev/null || true
chmod 750 "$NTP_SIGND_DIR"
log "Permissões do $NTP_SIGND_DIR ajustadas: owner root:_chrony, permissões 750."

# Habilita e reinicia o chrony
systemctl enable chrony >> "$LOG_FILE" 2>&1
systemctl restart chrony >> "$LOG_FILE" 2>&1

# Verifica se o serviço está ativo
if systemctl is-active chrony > /dev/null; then
    log "Chrony reiniciado com sucesso."
    info_box "Chrony configurado:\n- Servidores: ${NTP_SERVERS[*]}\n- Allow: $LOCAL_NET\n- Permissões do ntp_signd ajustadas."
else
    error_exit "Falha ao reiniciar o chrony. Verifique o log."
fi