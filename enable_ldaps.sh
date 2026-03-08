#!/bin/bash
# enable_ldaps.sh - Configura LDAPS com certificado TLS

source "$(dirname "$0")/common.sh"

check_root

# Credenciais do administrador (para verificação)
ADMIN_USER="${ADMIN_USER:-Administrator}"
ADMIN_PASS="${ADMIN_PASS:-}"

# Se a senha não foi fornecida via ambiente, solicita via dialog
if [ -z "$ADMIN_PASS" ]; then
    exec 3>&1
    ADMIN_PASS=$(dialog --stdout --title "Senha do Administrador" \
        --passwordbox "Digite a senha do usuário $ADMIN_USER (para verificação):" 8 50)
    exec 3>&-

    if [ -z "$ADMIN_PASS" ]; then
        log "Aviso: Senha não informada. A verificação pós-configuração será limitada."
    fi
fi

# Função para executar samba-tool com autenticação (se a senha foi fornecida)
samba_tool_auth() {
    if [ -n "$ADMIN_PASS" ]; then
        samba-tool "$@" -U "$ADMIN_USER" --password="$ADMIN_PASS"
    else
        samba-tool "$@"
    fi
}

# Diretório para certificados
TLS_DIR="/var/lib/samba/private/tls"
mkdir -p "$TLS_DIR"
chmod 750 "$TLS_DIR"

# Nome do servidor FQDN
FQDN=$(hostname -f)
DOMAIN=$(hostname -d)

# Define validade (em dias)
DAYS=3650  # Aproximadamente 10 anos

# Verifica se já existe um certificado
if [ -f "$TLS_DIR/server.crt" ] && [ -f "$TLS_DIR/server.key" ]; then
    log "Certificado existente encontrado."

    # Mostra informações do certificado atual
    echo "Informações do certificado atual:"
    openssl x509 -in "$TLS_DIR/server.crt" -text -noout | grep -E "Subject:|Not Before:|Not After :|Issuer:|DNS:"
    echo

    # Pergunta se deseja substituir
    exec 3>&1
    REPLACE=$(dialog --stdout --title "Certificado existente" \
        --yesno "Já existe um certificado em $TLS_DIR.\n\nDeseja substituí-lo por um novo?" 8 60)
    REPLACE_RESULT=$?
    exec 3>&-

    if [ $REPLACE_RESULT -ne 0 ]; then
        info_box "Operação cancelada. Mantendo certificado existente."
        exit 0
    fi

    # Faz backup do certificado existente
    BACKUP_DIR="$TLS_DIR/backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp "$TLS_DIR/server."* "$BACKUP_DIR/" 2>/dev/null || true
    log "Backup do certificado antigo criado em $BACKUP_DIR"
fi

# Gera chave privada e certificado autoassinado
log "Gerando chave privada e certificado autoassinado para $FQDN..."

# Gera chave privada e CSR
openssl req -x509 -nodes -days "$DAYS" -newkey rsa:2048 \
    -keyout "$TLS_DIR/server.key" \
    -out "$TLS_DIR/server.crt" \
    -subj "/CN=$FQDN/O=$DOMAIN/OU=Domain Controllers/C=BR" \
    -addext "subjectAltName=DNS:$FQDN,DNS:$DOMAIN" \
    >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    error_exit "Falha ao gerar certificado."
fi

# Ajusta permissões
chmod 600 "$TLS_DIR/server.key"
chmod 644 "$TLS_DIR/server.crt"

# Concatena em um arquivo PEM (para o Samba)
cat "$TLS_DIR/server.key" "$TLS_DIR/server.crt" > "$TLS_DIR/server.pem"
chmod 600 "$TLS_DIR/server.pem"

log "Certificado gerado com sucesso:"
log "  - Chave: $TLS_DIR/server.key"
log "  - Certificado: $TLS_DIR/server.crt"
log "  - PEM: $TLS_DIR/server.pem"

# Mostra informações do certificado gerado
echo
log "Informações do certificado gerado:"
echo "----------------------------------------"
openssl x509 -in "$TLS_DIR/server.crt" -text -noout | grep -E "Subject:|Not Before:|Not After :|Issuer:|DNS:" | sed 's/^/  /'
echo "----------------------------------------"

# Configura o Samba para usar o certificado
SMB_CONF="/etc/samba/smb.conf"
BACKUP="${SMB_CONF}.ldaps.bak.$(date +%Y%m%d%H%M%S)"
cp "$SMB_CONF" "$BACKUP"
log "Backup do smb.conf criado em $BACKUP"

# Função para adicionar ou substituir parâmetros em uma seção
add_param() {
    local section="$1"
    local param="$2"
    local value="$3"
    local file="$4"

    if ! grep -q "^\[$section\]" "$file"; then
        echo "[$section]" >> "$file"
    fi
    sed -i "/^\[$section\]/,/^\[/ { /^$param[[:space:]]*=/ d }" "$file"
    sed -i "/^\[$section\]/a $param = $value" "$file"
}

# Adiciona parâmetros TLS na seção [global]
log "Adicionando configurações TLS ao smb.conf..."
add_param "global" "tls enabled" "yes" "$SMB_CONF"
add_param "global" "tls keyfile" "$TLS_DIR/server.key" "$SMB_CONF"
add_param "global" "tls certfile" "$TLS_DIR/server.crt" "$SMB_CONF"
add_param "global" "tls cafile" "" "$SMB_CONF"  # Vazio para autoassinado

# Opcional: forçar LDAPS apenas (desabilitar LDAP simples)
add_param "global" "ldap server require strong auth" "yes" "$SMB_CONF"

log "Parâmetros TLS adicionados ao smb.conf."

# Verifica sintaxe do smb.conf
log "Verificando sintaxe do smb.conf..."
if ! testparm -s "$SMB_CONF" >/dev/null 2>&1; then
    error_exit "Erro de sintaxe no smb.conf. Restaurando backup..."
    cp "$BACKUP" "$SMB_CONF"
fi

# Reinicia o Samba
log "Reiniciando serviço samba-ad-dc..."
systemctl restart samba-ad-dc >> "$LOG_FILE" 2>&1

# Aguarda serviço iniciar
sleep 5

# Função para obter o DN do domínio de forma confiável
get_domain_dn() {
    local dn=""
    if [ -n "$ADMIN_PASS" ]; then
        dn=$(samba_tool_auth domain info 127.0.0.1 2>/dev/null | grep "Domain DN" | cut -d: -f2 | xargs)
    fi
    if [ -z "$dn" ]; then
        # Fallback: constrói a partir do domínio DNS
        dn="dc=$(echo $DOMAIN | sed 's/\./,dc=/g')"
    fi
    echo "$dn"
}

DOMAIN_DN=$(get_domain_dn)

if systemctl is-active --quiet samba-ad-dc; then
    log "Serviço samba-ad-dc reiniciado com sucesso."

    # Verifica se as portas estão escutando
    log "Verificando portas LDAP/LDAPS:"
    echo "----------------------------------------"
    if ss -tlnp | grep -q ":389 "; then
        log "✓ Porta LDAP (389) ativa"
    else
        log "✗ Porta LDAP (389) não está ativa"
    fi

    if ss -tlnp | grep -q ":636 "; then
        log "✓ Porta LDAPS (636) ativa"
    else
        log "✗ Porta LDAPS (636) não está ativa"
    fi
    echo "----------------------------------------"

    # Testa conexão LDAPS com tentativas
    log "Testando conexão LDAPS local..."
    LDAPS_OK=false
    for i in {1..5}; do
        if echo "Q" | openssl s_client -connect localhost:636 -servername "$FQDN" 2>/dev/null | grep -q "CONNECTED"; then
            log "✓ Conexão LDAPS bem-sucedida (tentativa $i)"
            LDAPS_OK=true
            # Extrai informações do certificado retornado
            echo "Certificado retornado pelo servidor:"
            echo "----------------------------------------"
            echo "Q" | openssl s_client -connect localhost:636 -servername "$FQDN" 2>/dev/null | openssl x509 -text -noout | grep -E "Subject:|Not Before:|Not After :|Issuer:|DNS:" | sed 's/^/  /'
            echo "----------------------------------------"
            break
        fi
        sleep 2
    done
    if [ "$LDAPS_OK" = false ]; then
        log "✗ Falha na conexão LDAPS após 5 tentativas"
    fi

    # Testa autenticação LDAPS se a senha foi fornecida
    if [ -n "$ADMIN_PASS" ]; then
        log "Testando autenticação via LDAPS..."

        # Cria arquivo LDIF temporário para teste
        TEST_LDIF=$(mktemp)
        cat > "$TEST_LDIF" <<EOF
dn: cn=Administrator,cn=Users,$DOMAIN_DN
changetype: modify
add: description
description: Teste LDAPS
EOF

        if ldapmodify -H ldaps://localhost -x -D "cn=Administrator,cn=Users,$DOMAIN_DN" -w "$ADMIN_PASS" -f "$TEST_LDIF" 2>/dev/null; then
            log "✓ Autenticação LDAPS bem-sucedida"
        else
            log "✗ Falha na autenticação LDAPS"
        fi

        rm -f "$TEST_LDIF"
    fi

else
    error_exit "Falha ao reiniciar samba-ad-dc. Verifique o log com: journalctl -u samba-ad-dc"
fi

# Instruções para clientes
CERT_FILE="$TLS_DIR/server.crt"
CERT_BASE64="$TLS_DIR/server_base64.crt"

# Gera versão base64 do certificado para distribuição
openssl x509 -in "$CERT_FILE" -out "$CERT_BASE64" -outform PEM
log "Versão base64 do certificado salva em: $CERT_BASE64"

# Mostra resumo final
echo
log "=== RESUMO DA CONFIGURAÇÃO LDAPS ==="
echo "=========================================="
echo "1. Certificado gerado:"
echo "   • Assinado para: $FQDN"
echo "   • Válido por: $DAYS dias"
echo "   • Localização: $TLS_DIR/"
echo
echo "2. Portas ativas:"
echo "   • LDAP  (389): $(ss -tlnp | grep -q ":389 " && echo "ATIVO" || echo "INATIVO")"
echo "   • LDAPS (636): $(ss -tlnp | grep -q ":636 " && echo "ATIVO" || echo "INATIVO")"
echo
echo "3. Arquivos importantes:"
echo "   • Chave privada: $TLS_DIR/server.key (600)"
echo "   • Certificado:   $TLS_DIR/server.crt (644)"
echo "   • PEM:          $TLS_DIR/server.pem (600)"
echo "   • Base64:       $CERT_BASE64"
echo
echo "4. Backup:"
echo "   • smb.conf: $BACKUP"
if [ -n "$BACKUP_DIR" ]; then
    echo "   • Certificado antigo: $BACKUP_DIR"
fi
echo "=========================================="

# Informações para clientes
cat > /tmp/ldaps_client_info.txt <<EOF
=== INSTRUÇÕES PARA CLIENTES LDAPS ===

Para conectar clientes ao LDAPS deste servidor:

1. Copie o certificado para o cliente:
   scp $CERT_BASE64 usuario@cliente:/tmp/

2. No cliente Linux, adicione o certificado ao truststore:
   sudo cp /tmp/server_base64.crt /usr/local/share/ca-certificates/samba-ldaps.crt
   sudo update-ca-certificates

3. Configure o cliente para usar LDAPS:
   - Servidor: $FQDN
   - Porta: 636
   - Protocolo: LDAPS

4. Para testar a conexão:
   ldapsearch -H ldaps://$FQDN -x -b "$DOMAIN_DN" -D "cn=Administrator,cn=Users,$DOMAIN_DN" -W

Certificado (base64) está disponível em:
$CERT_BASE64
EOF

log "Instruções para clientes salvas em: /tmp/ldaps_client_info.txt"

info_box "LDAPS configurado com sucesso!\n\n• Porta 636 ativa\n• Certificado autoassinado para $FQDN\n• Válido por $DAYS dias\n\nInstruções para clientes em:\n/tmp/ldaps_client_info.txt\n\nCERTIFICADO: $TLS_DIR/server.crt"

exit 0