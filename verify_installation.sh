#!/bin/bash
# verify_installation.sh - Verifica a instalação do Samba DC

source "$(dirname "$0")/common.sh"

# Verifica root (alguns comandos precisam)
check_root

# Coleta o domínio/realm do smb.conf se possível
if [ -f /etc/samba/smb.conf ]; then
    REALM=$(grep "^[[:space:]]*realm" /etc/samba/smb.conf | awk '{print $2}')
    DOMAIN=$(grep "^[[:space:]]*workgroup" /etc/samba/smb.conf | awk '{print $2}')
fi
# Fallback para hostname se valores estiverem vazios
if [ -z "$DOMAIN" ]; then
    DOMAIN=$(hostname -d 2>/dev/null || true)
fi
if [ -z "$REALM" ]; then
    if [ -n "$DOMAIN" ]; then
        REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
    else
        REALM="$(hostname -d 2>/dev/null | tr '[:lower:]' '[:upper:]')"
    fi
fi

{
    echo "===== Verificando Samba DC ====="
    echo "Data: $(date)"
    echo

    echo "--- Status do serviço samba-ad-dc ---"
    systemctl status samba-ad-dc --no-pager -l
    echo

    echo "--- Verificando portas do Samba (389, 636, 53, 88, 464, 445) ---"
    netstat -tulpn | grep -E '(:389|:636|:53|:88|:464|:445)'
    echo

    echo "--- Teste de resolução DNS SRV ---"
    host -t SRV _ldap._tcp."${DOMAIN,,}.${REALM,,}"
    host -t SRV _kerberos._tcp."${DOMAIN,,}.${REALM,,}"
    echo

    echo "--- Teste de autenticação Kerberos (kinit administrator) ---"
    echo "Por favor, digite a senha do administrador quando solicitado."
    kinit administrator@${REALM}
    klist
} > /tmp/samba-verify.txt 2>&1

dialog --title "Resultado da Verificação" --textbox /tmp/samba-verify.txt 20 80
rm /tmp/samba-verify.txt