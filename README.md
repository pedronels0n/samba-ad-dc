# Samba AD DC Automation Framework

> Framework completo e modular para provisionamento automatizado de um Samba Active Directory Domain Controller em ambientes Debian/Ubuntu

![Platform](https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-blue?style=flat-square)
![Samba](https://img.shields.io/badge/Samba-4.19+-green?style=flat-square)
![Security](https://img.shields.io/badge/Security-Hardening%20%26%20TLS-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-lightgrey?style=flat-square)

---

## 📋 Índice

1. [Visão Geral](#visão-geral)
2. [Pré-requisitos](#pré-requisitos)
3. [Arquitetura de Scripts](#arquitetura-de-scripts)
4. [Instalação Rápida](#instalação-rápida)
5. [Fluxo Detalhado de Execução](#fluxo-detalhado-de-execução)
6. [Descrição Individual dos Scripts](#descrição-individual-dos-scripts)
7. [Validação de Ambiente](#validação-de-ambiente)
8. [Hardening & Segurança](#hardening--segurança)
9. [LDAPS/PKI e Certificados](#ldapspki-e-certificados)
10. [Troubleshooting](#troubleshooting)
11. [Manutenção Operacional](#manutenção-operacional)
12. [Referências & Compliance](#referências--compliance)

---

## Visão Geral

Este projeto automatiza o provisionamento completo de um **Samba AD DC** com foco em:

- ✅ **Provisionamento automatizado** — Domain Controller, DNS integrado, Kerberos
- ✅ **Hardening & Segurança** — Assinatura SMB, criptografia, auditoria completa
- ✅ **PKI Interna** — Geração de CA e certificados wildcard com LDAPS/TLS
- ✅ **Políticas de Senha** — Políticas GLOBAL e granulares (PSOs) conforme best practices
- ✅ **GPOs inteligentes** — Remoção de padrão, criação de policies de hardening
- ✅ **Auditoria integrada** — full_audit, rsyslog, logrotate automático

**Autenticação interativa**: todos os comandos `samba-tool` que requerem privilégios usam `-U Administrator` e solicitam senha no prompt, evitando senhas em linha de comando.

---

## Pré-requisitos

### Hardware

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| vCPU | 2 | 4+ |
| RAM | 2 GB | 4-8 GB |
| Disco | 20 GB | 50 GB+ |
| Rede | 1 interface | 2+ (gerenciamento separado) |

### Sistema Operacional

- **Debian 10+** ou **Ubuntu 18.04+**
- Repositórios atualizados
- **Sem** serviços Samba pré-existentes rodando
- **IP estático** configurado
- **Hostname FQDN** definido (ex: `dc1.example.local`)

### Portas de Rede (inbound)

| Porta | Protocolo | Serviço | Descrição |
|-------|-----------|---------|-----------|
| 53 | TCP/UDP | DNS | Resolução de nomes |
| 88 | TCP/UDP | Kerberos | Autenticação Kerberos |
| 135 | TCP | RPC | Mapeador de endpoints |
| 389 | TCP/UDP | LDAP | Protocolo LDAP |
| 445 | TCP | SMB | Protocolo SMB3 |
| 464 | TCP/UDP | Kerberos | Mudança de senha |
| 636 | TCP | LDAPS | LDAP sobre TLS (opcional, após setup_ca.sh) |

---

## Arquitetura de Scripts

```
.
├── common.sh                          # Funções utilitárias globais
├── install_packages.sh                # Instalação de dependências
├── set_network.sh                     # Configuração de rede estática
├── set_hostname.sh                    # Configuração de hostname/FQDN
├── configure_kerberos.sh              # Ajustes Kerberos/krb5.conf
├── provision_domain.sh                # Provisionamento do domínio AD
├── setup-samba-dc.sh                  # Orquestrador principal
│
├── [SEGURANÇA & HARDENING]
├── harden_samba.sh                    # Hardening SMB, signing, auditoria
├── configure_pso.sh                   # Políticas de senha GLOBAL e PSOs
├── configure_dns_reverse.sh           # Zona reversa DNS
├── create_hardening_gpos.sh           # GPOs de hardening (usando -U Administrator)
├── remove_default_gpos.sh             # Remoção de GPOs padrão
│
├── [CERTIFICADOS & LDAPS]
├── setup_ca.sh                        # Gera CA interna + wildcard cert
├── enable_ldaps.sh                    # Configura LDAPS com cert autoassinado
├── configure_ldaps_with_wildcard.sh   # Usa wildcard cert para LDAPS
│
├── [UTILIDADES]
├── verify_installation.sh             # Testes pós-instalação
├── samba_backup.sh                    # Backup de /var/lib/samba
├── samba_restore.sh                   # Restore de backup
├── raise_functional_level.sh          # Atualiza nível funcional do domínio
│
└── gpowin/                            # Templates GPO Windows (importar manualmente)
```

---

## Instalação Rápida

### 1️⃣ Preparação Inicial

```bash
# Clone ou copie todos os scripts para uma máquina Debian/Ubuntu limpa
cd /path/to/samba-scripts

# Torne executáveis
chmod +x *.sh

# Verifique se está como root
sudo whoami  # deve exibir 'root'
```

### 2️⃣ Configuração de Rede e Hostname

```bash
# Define IP estático e atualiza /etc/hosts com o IP real da máquina
sudo ./set_network.sh

# Define FQDN do servidor (ex: dc1.example.local)
sudo ./set_hostname.sh
```

### 3️⃣ Provisionamento do Domínio

```bash
# Executa o orquestrador completo (instalação + provisionamento + hardening)
sudo ./setup-samba-dc.sh

# OU execute scripts individuais se preferir controlar cada etapa:
sudo ./install_packages.sh
sudo ./configure_kerberos.sh
sudo ./provision_domain.sh
sudo ./configure_services.sh
```

### 4️⃣ Hardening e Políticas

```bash
# Aplica hardening SMB + auditoria + logging configurado
sudo ./harden_samba.sh

# Cria e aplica políticas de senha GLOBAL e PSOs
sudo ./configure_pso.sh  # Solicitará senha de Administrator

# Cria zona reversa DNS e registros PTR
sudo ./configure_dns_reverse.sh  # Solicitará senha de Administrator
```

### 5️⃣ Certificados e LDAPS (Opcional)

```bash
# Cria CA interna e certificado wildcard
sudo ./setup_ca.sh

# Configura Samba para usar o certificado wildcard
sudo ./configure_ldaps_with_wildcard.sh  # Solicitará senha de Administrator

# Verifica porta 636 (LDAPS)
ss -tulpn | grep :636
```

### 6️⃣ GPOs e Limpeza (Opcional)

```bash
# Remove GPOs padrão (Remove temporariamente full_audit, reinicia, limpa LDB e pastas)
sudo ./remove_default_gpos.sh  # Solicitará senha de Administrator

# Cria GPOs customizadas de hardening
sudo ./create_hardening_gpos.sh  # Solicitará senha de Administrator interativamente
```

### 7️⃣ Verificação Final

```bash
# Executa testes automatizados pós-instalação
sudo ./verify_installation.sh
```

---

## Fluxo Detalhado de Execução

### Ordem Recomendada (Produção)

```
1. set_network.sh              ← Rede estática
   ↓
2. set_hostname.sh             ← FQDN + /etc/hosts
   ↓
3. install_packages.sh         ← Dependências
   ↓
4. configure_kerberos.sh       ← Kerberos/krb5.conf
   ↓
5. provision_domain.sh         ← Provisionamento AD
   ↓
6. configure_services.sh       ← Habilita samba-ad-dc
   ↓
7. verify_installation.sh      ← Checagens iniciais
   ↓
8. harden_samba.sh             ← Hardening SMB, signing, audit
   ↓
9. configure_pso.sh            ← Política de senha GLOBAL + PSOs
   ↓
10. configure_dns_reverse.sh   ← Zona reversa DNS (opcional)
    ↓
11. setup_ca.sh                ← CA interna + wildcard cert
    ↓
12. configure_ldaps_with_wildcard.sh ← LDAPS/TLS
    ↓
13. remove_default_gpos.sh     ← Remove GPOs padrão (opcional)
    ↓
14. create_hardening_gpos.sh   ← Cria GPOs de hardening (opcional)
```

---

## Descrição Individual dos Scripts

### Core Scripts

#### `common.sh`
Biblioteca compartilhada com funções utilitárias:
- `log()` — Escreve em log com timestamp
- `error_exit()` — Erro fatal com exit
- `check_root()` — Valida se é root
- `check_prereqs()` — Valida comandos/pacotes
- `dialog` wrappers para interface gráfica

#### `install_packages.sh`
Instala todas as dependências necessárias:
- Samba, samba-tool, samba-dsdb-modules
- Kerberos, LDAP tools
- OpenSSL, bind-utilities
- dialog, rsyslog, logrotate

#### `set_network.sh`
Configura rede estática (netplan ou ifupdown):
- Menu para escolher interface
- Solicita IP/CIDR, gateway, DNS1/DNS2
- **Importante**: Atualiza `/etc/hosts` com o IP real da máquina (não 127.0.1.1)
- Reinicia networking e exibe summary

#### `set_hostname.sh`
Define FQDN e atualiza `/etc/hosts`:
- Solicita FQDN (ex: `dc1.example.local`)
- Define via `hostnamectl`
- Remove entradas antigas e adiciona nova entry com IP local

#### `configure_kerberos.sh`
Ajustes iniciais de Kerberos:
- Detecta domínio a partir do hostname
- Valida/cria `/etc/krb5.conf`
- Configura realms e domínios

#### `provision_domain.sh`
**Passo crítico** — Provisiona o domínio Samba AD:
- Solicita nome do domínio (ex: `example.local`)
- Executa `samba-tool domain provision --use-rfc2307 ...`
- Configura permissões, SYSVOL, netlogon
- Gera Kerberos DB

#### `configure_services.sh`
Habilita e inicia serviços:
- `samba-ad-dc` (principal)
- Desabilita `smbd`, `nmbd`, `winbind` legados
- Configura entradas DNS resolver para localhost
- Gerencia systemd

#### `setup-samba-dc.sh`
Orquestrador interativo que encadeia scripts:
- Menu principal com opções
- Log centralizado
- Pode parar em qualquer erro

### Security Scripts

#### `harden_samba.sh`
Aplica hardening SMB e auditoria conforme o manual:

**Mudanças no smb.conf `[global]`:**
- `restrict anonymous = 2` — Bloqueia listagem anônima
- `disable netbios = yes` + `smb ports = 445` — SMB3 apenas
- `load printers = no` + `printing = bsd` + `disable spoolss = yes` — Desabilita impressão
- `ntlm auth = mschapv2-and-ntlmv2-only` — NTLMv1/RC4 proibido
- `server signing = mandatory` + `client signing = mandatory` — Assinatura obrigatória
- `smb encrypt = auto` — Criptografia SMB3
- `rpc server dynamic port range = 50000-55000` — Portas RPC restritas (de 11500+ para ~5500)
- `vfs objects = full_audit` — Auditoria de operações
- `log level = 1 auth_audit:3 dsdb_audit:3 ...` — Logging detalhado

**Insere `full_audit` em `[sysvol]` e `[netlogon]`:**
- Rastreia pwrite, mkdirat, unlinkat, fchmod, fchown, openat, renameat
- Facility local7, priority NOTICE

**Cria arquivos de auditoria:**
- `/etc/rsyslog.d/00-samba-audit.conf` — Direciona facility local7 para `/var/log/samba/audit.log`
- `/etc/logrotate.d/samba-audit` — Rotação semanal (8 backups, compressão)

**Hardening Kerberos:**
- Atualiza `/etc/krb5.conf` com `default_etypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96`
- Remove DES/RC4 legado

#### `configure_pso.sh`
Políticas de senha conforme o manual (usa `-U Administrator`):

1. **Exibe** política atual via `samba-tool domain passwordsettings show`

2. **Aplica política GLOBAL:**
   ```
   --complexity=on (requisitos de complexidade)
   --history-length=24 (24 senhas anteriores)
   --min-pwd-length=14
   --min-pwd-age=1 dia
   --max-pwd-age=90 dias
   --account-lockout-threshold=5 tentativas
   --account-lockout-duration=30 minutos
   --reset-account-lockout-after=30 minutos
   ```

3. **Cria PSO `Admin_Policy` (prioridade 1):**
   - Mais restritiva para Domain Admins
   - min-pwd-length=20, history=30, lockout=3/60

4. **Cria PSO `Global_Policy` (prioridade 2):**
   - Política geral para Domain Users
   - min-pwd-length=14, history=20

5. **Valida** mostrando PSO do `administrator`

#### `configure_dns_reverse.sh`
Zona reversa DNS e registros PTR (usa `-U Administrator`):
- Solicita rede no formato CIDR (ex: `192.168.1.0/24`)
- Calcula zone reversa (`1.168.192.in-addr.arpa`)
- Extrai IP servidor e cria registro PTR
- Essencial para reverse lookups e mail

#### `create_hardening_gpos.sh`
Cria GPOs customizadas (usa `-U Administrator`, senha interativa):
- Lista de 20+ GPOs pré-definidas (Windows Server, Windows 10/11)
- Inclui IE 11, Bitlocker, Defender, Domain Security
- Barra de progresso (dialog --gauge)
- Registra erros para retry

#### `remove_default_gpos.sh`
Remove GPOs padrão do Samba (usa `-U Administrator`):

**Fase de pré-limpeza:**
- Instala `ldb-tools` se necessário
- Faz backup de smb.conf

**Fase de remoção:**
1. Remove `full_audit` temporariamente de `[sysvol]` e `[netlogon]`
2. Reinicia Samba
3. Executa `samba-tool ntacl sysvolreset` (redefine permissões AD)
4. Lista GPOs atuais para conferência
5. Deleta objetos LDB de ambas as GPOs padrão (User, Machine, Container)
6. Remove pastas físicas em `/var/lib/samba/sysvol/.../Policies/`

GPOs removidas:
- Default Domain Policy (`{31B2F340-016D-11D2-945F-00C04FB984F9}`)
- Default Domain Controllers Policy (`{6AC1786C-016F-11D2-945F-00C04FB984F9}`)

### Certificate & LDAPS Scripts

#### `setup_ca.sh`
Cria CA interna e certificado wildcard (10 anos):
- Gera chave RSA 4096 para CA
- Certificado autoassinado do CA
- Cria CSR para wildcard (`*.exemplo.local`)
- Assina com CA usando SAN com DNS e FQDN
- Salva em `/root/samba-ca/` e copia para `/etc/ssl/certs` e `/etc/ssl/private`
- Atualiza `smb.conf` se existir

#### `enable_ldaps.sh`
Configura LDAPS com certificado autoassinado:
- Gera self-signed em `/var/lib/samba/private/tls/`
- Configura `tls enabled = yes` e parâmetros no smb.conf
- Testa porta 636

#### `configure_ldaps_with_wildcard.sh`
Usa wildcard CA para LDAPS (mais robusto):
- Copia arquivos de `setup_ca.sh` para `/var/lib/samba/private/tls/`
- Configura smb.conf com wildcard + CA
- Reinicia Samba
- Modo preferido em produção

### Utility Scripts

#### `verify_installation.sh`
Testes automatizados pós-instalação:
- Verifica status e portas
- Testa DNS, Kerberos, LDAP/LDAPS
- Valida domínio

#### `samba_backup.sh`
Backup de `/var/lib/samba` e `/etc/samba`:
- Comprime com tar.gz
- Timestamped

#### `samba_restore.sh`
Restaura backup anterior

#### `raise_functional_level.sh`
Atualiza nível funcional do domínio (ex: 2016 → 2019)

---

## Validação de Ambiente

Use estes comandos para validar a máquina antes de executar os scripts:

### ✅ Checklist Rápido

```bash
# 1. Usuário root?
sudo whoami  # deve exibir 'root'

# 2. IP estático?
ip -4 addr show | grep -v 127.0.0.1
# Exemplo esperado: inet 192.168.1.10/24 ...

# 3. Hostname FQDN?
hostname -f  # esperado: dc1.example.local
hostname -d  # esperado: example.local

# 4. Sem Samba legado rodando?
systemctl status smbd nmbd winbind 2>&1 | grep -i inactive

# 5. Portas disponíveis? (antes de provisionar)
ss -tulpn | grep -E ':(53|88|135|389|445|464)'
# Nada deve estar em listen (ou apenas Samba-related)
```

### 🔍 Validação Pós-Instalação

```bash
# Samba rodando?
systemctl status samba-ad-dc
# output: active (running)

# Portas listening?
ss -tulpn | grep -E ':(53|88|135|389|445|464|636)'
# Todas devem estar em LISTEN

# DNS funcionando?
host -t SRV _ldap._tcp.$(hostname -d)

# Kerberos funcionando?
kinit Administrator@$(hostname -d | tr '[:lower:]' '[:upper:]')
# Solicitará senha, depois:
klist
# output: principal Administrator@EXAMPLE.LOCAL ...

# LDAP funcionando?
ldapsearch -H ldap://localhost -x -D "Administrator@$(hostname -d)" -W -b "dc=$(hostname -d | sed 's/\./,dc=/g')" "(sAMAccountName=administrator)" | head -20

# LDAPS (se configurado)?
LDAPTLS_CACERT=/var/lib/samba/private/tls/ca.crt \
  ldapsearch -H ldaps://$(hostname -f) -x -D "Administrator@$(hostname -d)" -W -b "dc=$(hostname -d | sed 's/\./,dc=/g')" "(sAMAccountName=administrator)" | head -20
```

### 📊 Onde Olhar se Falhar

| Problema | Log | Comando |
|----------|-----|---------|
| Samba não inicia | `/var/log/samba/` | `journalctl -u samba-ad-dc -b` |
| DNS falha | `/var/log/samba/` | `samba-tool dns query localhost EXAMPLE.LOCAL @ A` |
| Kerberos falha | `/var/log/krb5kdc.log` | `kinit -v Administrator` |
| LDAP refuses | `/var/log/samba/` | `ldapcert -H ldap://localhost` |
| Auditoria não aparece | `/var/log/samba/audit.log` | `tail -f /var/log/samba/audit.log` |

---

## Hardening & Segurança

### Checklist de Segurança (pós-deployment)

- **SMB:** assinatura obrigatória (`server signing = mandatory`)
- **NTLMv1:** desabilitado (`ntlm auth = mschapv2-and-ntlmv2-only`)
- **Criptografia:** SMB encrypt ativo (`auto` permitido, `mandatory` mais restritivo)
- **Auditoria:** `full_audit` em `[global]`, `[sysvol]`, `[netlogon]`
- **Logging:** nivel 1 com auth_audit, dsdb_audit, json_audit
- **Kerberos:** apenas AES256/AES128 (DES/RC4 removidos)
- **Porta RPC:** range restrito `50000-55000` (economiza ~11k portas)
- **Senhas:** política GLOBAL + PSOs granulares
- **DNS Reverso:** zona configurada e registros PTR
- **TLS/LDAPS:** CA interna + certificado wildcard (port 636)

### Mudanças em smb.conf (harden_samba.sh)

```ini
[global]
restrict anonymous = 2
disable netbios = yes
smb ports = 445
load printers = no
printing = bsd
printcap name = /dev/null
disable spoolss = yes
ntlm auth = mschapv2-and-ntlmv2-only
rpc server dynamic port range = 50000-55000
server signing = mandatory
client signing = mandatory
smb encrypt = auto
vfs objects = dfs_samba4 acl_xattr full_audit
full_audit:prefix = IP=%I|USER=%u|MACHINE=%m|VOLUME=%S
full_audit:success = pwrite renameat mkdirat unlinkat fchmod fchown openat
full_audit:failure = none
full_audit:facility = local7
full_audit:priority = NOTICE
log level = 1 auth_audit:3 auth_json_audit:3 dsdb_audit:3 dsdb_json_audit:3 winbind:2
logging = file
max log size = 10000
tls enabled = yes
tls keyfile = /var/lib/samba/private/tls/server.key
tls certfile = /var/lib/samba/private/tls/server.crt
tls cafile = /var/lib/samba/private/tls/ca.crt
ldap server require strong auth = yes

[sysvol]
vfs objects = dfs_samba4 acl_xattr full_audit
full_audit:failure = none
full_audit:success = pwrite renameat mkdirat unlinkat fchmod fchown openat
full_audit:prefix = IP=%I|USER=%u|MACHINE=%m|VOLUME=%S
full_audit:facility = local7
full_audit:priority = NOTICE

[netlogon]
vfs objects = dfs_samba4 acl_xattr full_audit
full_audit:failure = none
full_audit:success = pwrite renameat mkdirat unlinkat fchmod fchown openat
full_audit:prefix = IP=%I|USER=%u|MACHINE=%m|VOLUME=%S
full_audit:facility = local7
full_audit:priority = NOTICE
```

---

## LDAPS/PKI e Certificados

### Workflow Certificados

```
setup_ca.sh
├─ Gera CA privada (RSA 4096)
├─ Gera certificado CA autoassinado
├─ Gera chave wildcard
├─ Cria CSR com SAN
├─ Assina CSR com CA
└─ Copia para /etc/ssl/certs e /etc/ssl/private

                ↓

configure_ldaps_with_wildcard.sh
├─ Copia arquivos para /var/lib/samba/private/tls/
├─ Configura smb.conf (tls_keyfile, tls_certfile, tls_cafile)
└─ Reinicia samba-ad-dc

                ↓

Resultado: porta 636 (LDAPS) ativa com certificado wildcard assinado
```

### Testes LDAPS

```bash
# Ver certificado
openssl s_client -connect $(hostname -f):636 -showcerts

# Teste LDAPSEARCH (com CA local)
LDAPTLS_CACERT=/var/lib/samba/private/tls/ca.crt \
  ldapsearch -H ldaps://$(hostname -f) -x \
  -D "administrator@$(hostname -d)" -W \
  -b "dc=$(hostname -d | sed 's/\./,dc=/g')" \
  "(sAMAccountName=administrator)"

# Teste com STARTTLS (porta 389 → TLS)
LDAPTLS_CACERT=/var/lib/samba/private/tls/ca.crt \
  ldapsearch -H ldap://$(hostname -f) -ZZ -x \
  -D "administrator@$(hostname -d)" -W \
  -b "dc=$(hostname -d | sed 's/\./,dc=/g')" \
  "(sAMAccountName=administrator)"
```

---

## Troubleshooting

### Samba não inicia após provisioning

**Sintoma:** `systemctl status samba-ad-dc` mostra erro

**Solução:**
```bash
journalctl -u samba-ad-dc -b -n 50  # Últimas 50 linhas
cat /var/log/samba/log.samba
# Procure por: bind, permission denied, database locked

# Tente:
systemctl stop samba-ad-dc
samba -D -i  # Executa em foreground para debug
```

### DNS não resolve nomes do domínio

**Sintoma:** `host example.local` falha

**Solução:**
```bash
# Verifique /etc/resolv.conf
cat /etc/resolv.conf  # deve ter: nameserver 127.0.0.1

# Consulte o Samba DNS diretamente
samba_dnsupdate

# Tente:
dig example.local @localhost +trace
host -t SRV _ldap._tcp.example.local
```

### Kerberos falha ao iniciar uma sessão

**Sintoma:** `kinit Administrator` retorna erro

**Solução:**
```bash
# Verifique horário (diferença de mais de 5 min causa falha)
timedatectl status
sudo timedatectl set-ntp true

# Recrie o keytab
samba-tool domain exportkeytab /etc/krb5.keytab

# Teste:
kinit -v Administrator  # -v para verbose

# Verifique krb5.conf
cat /etc/krb5.conf
```

### LDAP autentica mas retorna sem atributos

**Sintoma:** ldapsearch autentia mas retorna vazio ou erros de permission

**Solução:**
```bash
# Verifique permissões SYSVOL
samba-tool ntacl sysvolreset

# Redefina Forest Info
samba-tool forest root_trust_instance

# Reinicie
systemctl restart samba-ad-dc
```

### Auditoria não registra eventos

**Sintoma:** `/var/log/samba/audit.log` não criado ou vazio

**Solução:**
```bash
# Verifique rsyslog
systemctl status rsyslog
cat /etc/rsyslog.d/00-samba-audit.conf  # deve redirecionar local7

# Reinicie rsyslog
systemctl restart rsyslog

# Forçe evento de teste
sudo touch /var/lib/samba/sysvol/example.local/Policies/test-audit.txt

# Confira log
tail -f /var/log/samba/audit.log
```

### Porta LDAPS (636) não responde

**Sintoma:** `ss -tulpn | grep 636` não mostra samba

**Solução:**
```bash
# Verifique certificados em smb.conf
grep -A 5 "tls_" /etc/samba/smb.conf

# Confirme arquivos existem
ls -la /var/lib/samba/private/tls/

# Tente:
sudo ./setup_ca.sh  # regenera CA
sudo ./configure_ldaps_with_wildcard.sh  # reconfigura
systemctl restart samba-ad-dc

# Teste manualmente
openssl s_client -connect localhost:636

```

### GPO não aparece no Windows

**Sintoma:** `gpmc.msc` não lista GPO criada

**Solução:**
```bash
# Confirme que GPO foi criada
samba-tool -U Administrator gpo listall

# Verifique permissões sysvol
samba-tool ntacl sysvolreset

# Limpe cache Windows (no cliente):
gpupdate /force
```

---

## Manutenção Operacional

### Backup & Restore

```bash
# Backup automático
sudo ./samba_backup.sh
# Gera: /var/backups/samba_backup_YYYYMMDD_HHMMSS.tar.gz

# Restore
sudo ./samba_restore.sh
# Solicita arquivo de backup
```

### Monitoramento de Logs

```bash
# Auditoria (full_audit)
tail -f /var/log/samba/audit.log | grep -i "USER=administrator"

# Autenticação Kerberos
tail -f /var/log/auth.log | grep -i krb

# Samba geral
journalctl -u samba-ad-dc -f

# Aplicar filtro de tempo
journalctl -u samba-ad-dc --since "2 hours ago"
```

### Rotação de Logs

Configurado automaticamente via `/etc/logrotate.d/samba` e `/etc/logrotate.d/samba-audit`:
- Semanal
- 8 backups
- Comprimido automaticamente

Forçar rotação:
```bash
logrotate -f /etc/logrotate.d/samba
logrotate -f /etc/logrotate.d/samba-audit
```

### Renovação de Certificados

Certificados têm validade de 10 anos. Para renovar:

```bash
# Gera novo par CA + wildcard
sudo ./setup_ca.sh

# Atualiza Samba para usar novo cert
sudo ./configure_ldaps_with_wildcard.sh

# Distribui CA para clientes (importar em trusted roots)
```

---

## Referências & Compliance

### Aligned com Manual Martinsec
✅ Políticas de senha GLOBAL + PSOs  
✅ Hardening SMB (signing, NTLMv2, sem NetBIOS)  
✅ Auditoria full_audit + rsyslog  
✅ LDAPS/TLS com PKI interna  
✅ Zona DNS reversa  
✅ Restrição RPC (50000-55000)  
✅ Hardening Kerberos (AES only)  
✅ Remoção GPOs padrão  

### Compliance & Boas Práticas
- **LGPD:** Logs auditáveis, certificados TLS, autenticação forte
- **ISO 27001:** Hardening, assinatura, criptografia, auditoria
- **CIS Benchmarks:** Samba 4.x hardening

---

## Licença

**MIT License** — Use livremente em ambientes corporativos, educacionais e laboratoriais.

---

**Última atualização:** 2026-03-03  
**Versão:** 1.0.0  
**Status:** Production-Ready