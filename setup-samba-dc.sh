#!/bin/bash
# setup-samba-dc.sh - Script principal para configuração do Samba DC
# Autor: ...
# Descrição: Interface dialog para executar as etapas de configuração.

# Carrega funções comuns
source "$(dirname "$0")/common.sh"

# Verifica root e dialog
check_root
check_dialog

while true; do
    # Exibe o menu principal
    CHOICE=$(dialog --clear --stdout --title "Configuração do Samba DC" \
        --menu "Escolha uma opção:" 18 60 10 \
        1 "Instalar pacotes necessários" \
        2 "Configurar Kerberos" \
        3 "Provisionar domínio AD" \
        4 "Configurar serviços" \
        5 "Verificar instalação" \
        6 "Executar todas as etapas (1-4)" \
        7 "Sair")

    case $CHOICE in
        1)
            bash "$SCRIPT_DIR/install_packages.sh"
            ;;
        2)
            bash "$SCRIPT_DIR/configure_kerberos.sh"
            ;;
        3)
            bash "$SCRIPT_DIR/provision_domain.sh"
            ;;
        4)
            bash "$SCRIPT_DIR/configure_services.sh"
            ;;
        5)
            bash "$SCRIPT_DIR/verify_installation.sh"
            ;;
        6)
            # Executa sequencialmente
            bash "$SCRIPT_DIR/install_packages.sh" && \
            bash "$SCRIPT_DIR/configure_kerberos.sh" && \
            bash "$SCRIPT_DIR/provision_domain.sh" && \
            bash "$SCRIPT_DIR/configure_services.sh" && \
            info_box "Todas as etapas concluídas com sucesso!"
            ;;
        7|"")
            clear
            echo "Saindo. Até mais!"
            exit 0
            ;;
    esac
done