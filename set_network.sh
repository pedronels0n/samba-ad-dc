#!/bin/bash
# set_network.sh - Configura IP fixo (estático) no sistema (Netplan ou ifupdown)

source "$(dirname "$0")/common.sh"

# Verifica root
check_root

# Detecta qual sistema de rede está em uso
if [ -d /etc/netplan ]; then
    NETWORK_MANAGER="netplan"
elif [ -f /etc/network/interfaces ]; then
    NETWORK_MANAGER="ifupdown"
else
    error_exit "Sistema de rede não suportado (apenas netplan ou ifupdown)."
fi

log "Sistema de rede detectado: $NETWORK_MANAGER"

# Lista interfaces de rede disponíveis (ignora loopback)
INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
if [ -z "$INTERFACES" ]; then
    error_exit "Nenhuma interface de rede encontrada."
fi

# Cria um menu com as interfaces
INTERFACE_LIST=""
for iface in $INTERFACES; do
    INTERFACE_LIST="$INTERFACE_LIST $iface -"
done

INTERFACE=$(dialog --stdout --title "Configuração de Rede" \
    --menu "Escolha a interface de rede para configurar IP fixo:" 12 50 5 $INTERFACE_LIST)
if [ -z "$INTERFACE" ]; then
    error_exit "Nenhuma interface selecionada."
fi

# Solicita configurações de IP
exec 3>&1
IP_ADDR=$(dialog --stdout --title "Endereço IP" \
    --inputbox "Digite o endereço IP com máscara (ex: 192.168.1.10/24):" 8 50)
[ -z "$IP_ADDR" ] && error_exit "IP não informado."

GATEWAY=$(dialog --stdout --title "Gateway" \
    --inputbox "Digite o gateway padrão (ex: 192.168.1.1):" 8 50)
[ -z "$GATEWAY" ] && error_exit "Gateway não informado."

DNS1=$(dialog --stdout --title "Servidor DNS Primário" \
    --inputbox "Digite o servidor DNS primário (ex: 8.8.8.8):" 8 50)
[ -z "$DNS1" ] && error_exit "DNS primário não informado."

DNS2=$(dialog --stdout --title "Servidor DNS Secundário (opcional)" \
    --inputbox "Digite o servidor DNS secundário (ou deixe em branco):" 8 50)

# Converte máscara CIDR para netmask se necessário (vamos manter CIDR no netplan, mas no ifupdown precisamos da netmask)
# Para ifupdown, precisamos converter. Vamos fazer uma função simples.
cidr_to_netmask() {
    local cidr=$1
    local mask=$(( 0xffffffff << (32 - cidr) ))
    echo "$(( (mask >> 24) & 0xff )).$(( (mask >> 16) & 0xff )).$(( (mask >> 8) & 0xff )).$(( mask & 0xff ))"
}

# Aplica a configuração conforme o gerenciador
if [ "$NETWORK_MANAGER" = "netplan" ]; then
    # Encontra o arquivo de configuração do netplan (geralmente 01-netcfg.yaml ou similar)
    NETPLAN_FILE=$(find /etc/netplan -name "*.yaml" | head -n1)
    if [ -z "$NETPLAN_FILE" ]; then
        NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
    fi
    
    # Backup
    cp "$NETPLAN_FILE" "$NETPLAN_FILE.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    
    # Cria novo conteúdo
    cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses:
        - $IP_ADDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS1${DNS2:+, }$DNS2]
EOF
    log "Arquivo netplan gerado: $NETPLAN_FILE"
    netplan apply || error_exit "Falha ao aplicar netplan."
    
elif [ "$NETWORK_MANAGER" = "ifupdown" ]; then
    # Extrai IP e CIDR
    IP_NO_CIDR=$(echo "$IP_ADDR" | cut -d/ -f1)
    CIDR=$(echo "$IP_ADDR" | cut -d/ -f2)
    NETMASK=$(cidr_to_netmask "$CIDR")
    
    # Backup do interfaces
    cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)
    
    # Remove configurações antigas da interface (se houver)
    sed -i "/iface $INTERFACE inet/d" /etc/network/interfaces
    sed -i "/auto $INTERFACE/d" /etc/network/interfaces
    
    # Adiciona nova configuração
    {
        echo "auto $INTERFACE"
        echo "iface $INTERFACE inet static"
        echo "    address $IP_NO_CIDR"
        echo "    netmask $NETMASK"
        echo "    gateway $GATEWAY"
        echo "    dns-nameservers $DNS1 $DNS2"
    } >> /etc/network/interfaces
    
    log "Arquivo /etc/network/interfaces atualizado."
    
    # Reinicia a rede (pode ser arriscado via SSH, mas vamos avisar)
    info_box "A configuração foi aplicada. Para ativar, a rede será reiniciada. Se estiver conectado via SSH, a conexão pode cair."
    confirm_box "Deseja reiniciar a rede agora?"
    if [ $? -eq 0 ]; then
        systemctl restart networking || error_exit "Falha ao reiniciar networking."
    else
        info_box "Reinicie a rede manualmente ou reinicie o sistema para aplicar as mudanças."
    fi
fi

info_box "Configuração de rede aplicada para interface $INTERFACE.\nIP: $IP_ADDR\nGateway: $GATEWAY\nDNS: $DNS1 $DNS2"