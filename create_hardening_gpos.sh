#!/bin/bash
# create_hardening_gpos.sh - Cria as GPOs de hardening
# Remove temporariamente o full_audit para evitar problemas com sysvolreset

# Verifica se é root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Este script deve ser executado como root. Use: sudo $0"
    exit 1
fi

# Verifica se o Samba está rodando
if ! systemctl is-active --quiet samba-ad-dc; then
    echo "❌ O serviço samba-ad-dc não está ativo. Inicie-o primeiro."
    exit 1
fi

# Pede a senha do Administrator
echo -n "Digite a senha do usuário Administrator do domínio: "
read -s ADMIN_PASS
echo

# Define arquivos importantes
SMB_CONF="/etc/samba/smb.conf"
BACKUP_SMB="${SMB_CONF}.gpo-creation.bak.$(date +%Y%m%d%H%M%S)"

# ========== 1. Backup do smb.conf ==========
echo "Criando backup do smb.conf em $BACKUP_SMB ..."
cp "$SMB_CONF" "$BACKUP_SMB"

# ========== 2. Remoção temporária do full_audit ==========
echo "Removendo temporariamente full_audit das seções [sysvol] e [netlogon]..."
sed -i '/^\[sysvol\]/,/^\[/ s/vfs objects = dfs_samba4 acl_xattr full_audit/vfs objects = dfs_samba4 acl_xattr/' "$SMB_CONF"
sed -i '/^\[netlogon\]/,/^\[/ s/vfs objects = dfs_samba4 acl_xattr full_audit/vfs objects = dfs_samba4 acl_xattr/' "$SMB_CONF"

echo "Reiniciando o Samba para aplicar a mudança..."
systemctl restart samba-ad-dc
sleep 3
if ! systemctl is-active --quiet samba-ad-dc; then
    echo "❌ Falha ao reiniciar o Samba. Abortando."
    exit 1
fi

# ========== 3. Execução do sysvolreset ==========
echo "Executando samba-tool ntacl sysvolreset..."
if ! samba-tool ntacl sysvolreset; then
    echo "❌ Erro ao executar ntacl sysvolreset. Abortando."
    exit 1
fi

# ========== 4. Criação das GPOs ==========
# Lista completa das GPOs desejadas
GPOS=(
    "PC_WinServer IE 11 PC"
    "User_WinServer IE 11 User"
    "PC_WinServer Def Antivirus"
    "DC_WinServer DC"
    "DC_WinServer DC Sec"
    "PC_WinServer MS"
    "PC_Win10 IE 11 PC"
    "User_Win10 IE 11 User"
    "PC_Win10 Bitlocker"
    "PC_Win10 PC"
    "PC_Win10 Defender Antivirus"
    "PC_Win10 Domain Sec"
    "User_Win10 User"
    "PC_Win11 IE 11 PC"
    "PC_Win11 IE 11 User"
    "PC_Win11 Bitlocker"
    "PC_Win11 PC"
    "PC_Win11 Defender Antivirus"
    "PC_Win11 Domain Sec"
    "User_Win11 User"
)

TOTAL=${#GPOS[@]}
SUCESSO=0
FALHA=0
EXISTENTES=()

# Obtém lista de GPOs já existentes (ignorando saída de erro)
echo "Obtendo lista de GPOs existentes..."
while IFS= read -r line; do
    if [[ "$line" =~ "display name:" ]]; then
        nome=$(echo "$line" | cut -d: -f2- | sed 's/^ //')
        EXISTENTES+=("$nome")
    fi
done < <(samba-tool gpo listall 2>/dev/null)

echo "GPOs já existentes: ${#EXISTENTES[@]}"
echo "-----------------------------------"

for GPO in "${GPOS[@]}"; do
    # Verifica se já existe
    existe=0
    for e in "${EXISTENTES[@]}"; do
        if [[ "$e" == "$GPO" ]]; then
            existe=1
            break
        fi
    done

    if [[ $existe -eq 1 ]]; then
        echo "⚠️  GPO já existe: $GPO (pulando)"
        continue
    fi

    echo -n "Criando: $GPO ... "
    if samba-tool gpo create "$GPO" -U Administrator --password="$ADMIN_PASS" > /dev/null 2>&1; then
        echo "✅"
        ((SUCESSO++))
    else
        echo "❌"
        ((FALHA++))
    fi
done

# ========== 5. Aviso final ==========
echo "========== RESUMO =========="
echo "Total de GPOs na lista: $TOTAL"
echo "Já existiam: $((TOTAL - SUCESSO - FALHA))"
echo "Criadas agora: $SUCESSO"
echo "Falhas: $FALHA"

if [ $FALHA -gt 0 ]; then
    echo "❌ Algumas GPOs falharam. Execute manualmente com --debug para diagnóstico."
fi

echo ""
echo "⚠️  ATENÇÃO: O full_audit foi REMOVIDO temporariamente do smb.conf."
echo "   Após importar as políticas no Windows, execute o script de finalização:"
echo "   sudo ./finalize_samba_security.sh"
echo ""
echo "Backup do smb.conf original: $BACKUP_SMB"

exit 0