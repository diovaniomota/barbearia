# Lembrete automático de agendamentos (WhatsApp)

Script que roda na **VPS** (junto do servidor WhatsApp) e envia um lembrete
**~1 hora antes** de cada agendamento. Sem dependências — só precisa de **Node 18+**.

Agendamentos com vários serviços (linhas consecutivas, ex: 9h + 9h30) recebem
**um único lembrete** listando todos os serviços.

---

## 1. Banco (uma vez)

No **Supabase → SQL Editor**, rode o arquivo:
`lib/supabase/reminder_migration.sql`

Ele cria a coluna `reminder_sent` (evita lembrete duplicado) e o template padrão.

## 2. Copiar para a VPS

```bash
# Na VPS:
mkdir -p /opt/wa-reminder
# copie reminder.js e run.sh.example para /opt/wa-reminder/
```

## 3. Configurar

```bash
cd /opt/wa-reminder
cp run.sh.example run.sh
nano run.sh        # preencha SUPABASE_URL e SUPABASE_SERVICE_KEY
chmod +x run.sh
```

> A **service_role key** está em: Supabase → Settings → API → `service_role` (secret).
> Ela só fica na VPS, nunca no app/navegador.

## 4. Testar manualmente

```bash
./run.sh
```

Deve imprimir `[reminder] concluído. N lembrete(s) enviado(s).`
(Crie um agendamento de teste para daqui ~1h e rode de novo para ver o envio.)

## 5. Agendar no cron (a cada 5 min)

```bash
crontab -e
```

Adicione a linha:

```cron
*/5 * * * * /opt/wa-reminder/run.sh >> /var/log/wa-reminder.log 2>&1
```

Pronto. A cada 5 minutos o script verifica e envia os lembretes da próxima hora.
Acompanhe o log com: `tail -f /var/log/wa-reminder.log`

---

## Variáveis (run.sh)

| Variável               | Obrigatória | Padrão                  | Descrição |
|------------------------|-------------|-------------------------|-----------|
| `SUPABASE_URL`         | sim         | —                       | URL do projeto Supabase |
| `SUPABASE_SERVICE_KEY` | sim         | —                       | service_role key |
| `WA_URL`               | não         | `http://localhost:3001` | servidor WhatsApp na própria VPS |
| `WA_API_KEY`           | não         | (lê de app_settings)    | chave do servidor WhatsApp |
| `LEAD_MINUTES`         | não         | `60`                    | antecedência do lembrete |
| `TZ_OFFSET`            | não         | `-03:00`                | fuso dos horários |

## Personalizar a mensagem

Edite a linha `wa_reminder_template` na tabela `app_settings` (Supabase).
Placeholders: `{{cliente}}` `{{data}}` `{{hora}}` `{{servico}}` `{{barbeiro}}`.
