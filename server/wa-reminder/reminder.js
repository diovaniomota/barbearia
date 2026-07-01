#!/usr/bin/env node
/**
 * Lembrete automático de agendamentos via WhatsApp.
 *
 * Roda na VPS agendado por cron a cada ~5 min.
 * Clientes normais:  1 lembrete N horas antes (configurável em app_settings).
 * Clientes do plano: 2 lembretes — 24h antes + N horas antes.
 *
 * Requisitos: Node 18+. Zero dependências externas.
 *
 * Variáveis de ambiente:
 *   SUPABASE_URL*          ex: https://xxxx.supabase.co
 *   SUPABASE_SERVICE_KEY*  service_role key
 *   WA_URL                 default http://localhost:3001
 *   WA_API_KEY             se vazio, lê wa_api_key de app_settings
 *   TZ_OFFSET              fuso dos agendamentos (default -03:00 / Brasil)
 */

'use strict';

const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY || '';
const WA_URL       = (process.env.WA_URL || 'http://localhost:3001').replace(/\/$/, '');
let   WA_API_KEY   = process.env.WA_API_KEY || '';
const TZ_OFFSET    = process.env.TZ_OFFSET || '-03:00';

const DEFAULT_TPL =
  '⏰ Lembrete do seu horário!\n\n' +
  'Olá {{cliente}}! Seu horário é hoje às {{hora}}.\n' +
  '✂️ Serviço: {{servico}}\n' +
  '💈 Profissional: {{barbeiro}}\n\n' +
  'Te esperamos! 👋';

const DEFAULT_NORMAL_TPL_24H =
  '📅 Lembrete do seu agendamento!\n\n' +
  'Olá {{cliente}}! Seu horário é amanhã às {{hora}}.\n' +
  '✂️ Serviço: {{servico}}\n' +
  '💈 Profissional: {{barbeiro}}\n\n' +
  'Te esperamos amanhã! 👋';

const DEFAULT_PLAN_TPL_24H =
  '📅 Lembrete do seu plano!\n\n' +
  'Olá {{cliente}}! Seu horário de plano é amanhã às {{hora}}.\n' +
  '✂️ Serviço: {{servico}}\n' +
  '💈 Profissional: {{barbeiro}}\n' +
  '{{pix}}\n' +
  'Te esperamos amanhã! 👋';

const DEFAULT_PLAN_TPL_1H =
  '⏰ Quase na hora!\n\n' +
  'Olá {{cliente}}! Seu horário de plano é hoje às {{hora}}.\n' +
  '✂️ Serviço: {{servico}}\n' +
  '💈 Profissional: {{barbeiro}}\n' +
  '{{pix}}\n' +
  'Te esperamos daqui a pouco! 🙌';

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('[reminder] Faltam SUPABASE_URL e/ou SUPABASE_SERVICE_KEY.');
  process.exit(1);
}

// ── Supabase REST ─────────────────────────────────────────────────────────────

function sb(path, init = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
}

// ── Datas / fuso ──────────────────────────────────────────────────────────────

function brDate(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(d);
}

function minutesUntil(dateStr, timeStr) {
  const t = timeStr.slice(0, 5);
  const apptMs = Date.parse(`${dateStr}T${t}:00${TZ_OFFSET}`);
  return (apptMs - Date.now()) / 60_000;
}

function timeToMin(t) {
  const [h, m] = t.slice(0, 5).split(':').map(Number);
  return h * 60 + m;
}

// ── Mensagem ──────────────────────────────────────────────────────────────────

function buildMessage(tpl, v) {
  const msg = tpl
    .replaceAll('{{cliente}}', v.cliente)
    .replaceAll('{{data}}',    v.data)
    .replaceAll('{{hora}}',    v.hora)
    .replaceAll('{{servico}}', v.servico)
    .replaceAll('{{barbeiro}}',v.barbeiro)
    .replaceAll('{{pix}}',     v.pix || '');
  // Remove a linha em branco deixada quando {{pix}} veio vazio (cliente paga no cartão).
  return msg.replace(/\n[ \t]*\n/g, '\n');
}

async function sendWhatsapp(phone, message) {
  const clean = String(phone).replace(/[^0-9]/g, '');
  if (!clean) return false;
  const full = clean.startsWith('55') ? clean : `55${clean}`;
  try {
    const res = await fetch(`${WA_URL}/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': WA_API_KEY },
      body: JSON.stringify({ phone: full, message }),
    });
    if (!res.ok) console.warn(`[reminder] /send ${res.status} p/ ${full}`);
    return res.ok;
  } catch (e) {
    console.warn(`[reminder] erro /send: ${e.message}`);
    return false;
  }
}

// Agrupa linhas consecutivas (de 30 em 30 min) em bookings distintos
function splitRuns(items) {
  const runs = [];
  let cur = [];
  for (const it of items) {
    if (!cur.length) { cur.push(it); continue; }
    const gap = timeToMin(it.appointment_time) - timeToMin(cur[cur.length - 1].appointment_time);
    if (gap === 30) cur.push(it);
    else { runs.push(cur); cur = [it]; }
  }
  if (cur.length) runs.push(cur);
  return runs;
}

// ── Configurações ─────────────────────────────────────────────────────────────

async function loadSettings() {
  const keys = [
    'wa_api_key', 'wa_enabled', 'wa_reminder_template',
    'reminder_normal_hours',
    'wa_reminder_template_24h',
    'wa_plan_reminder_template_24h',
    'wa_plan_reminder_template_1h',
  ];
  const res = await sb(`app_settings?select=key,value&key=in.(${keys.join(',')})`);
  const rows = await res.json();
  const map = {};
  if (Array.isArray(rows)) for (const r of rows) map[r.key] = r.value;
  return map;
}

// ── Clientes de plano (forma de pagamento / chave Pix) ────────────────────────

async function loadPlanClients() {
  const res = await sb('plan_clients?select=phone,payment_method,pix_key');
  const rows = await res.json();
  const map = new Map();
  if (Array.isArray(rows)) {
    for (const r of rows) {
      const digits = String(r.phone || '').replace(/[^0-9]/g, '');
      if (digits) map.set(digits, r);
    }
  }
  return map;
}

function pixLineFor(planClients, phone) {
  const digits = String(phone || '').replace(/[^0-9]/g, '');
  const pc = planClients.get(digits);
  const isPix = (pc?.payment_method || '').toUpperCase() === 'PIX';
  if (!isPix) return '';
  return pc.pix_key
    ? `🔑 Pagamento via Pix: ${pc.pix_key}`
    : '🔑 Pagamento via Pix — confirme a chave com o barbeiro.';
}

// ── Patch de flags de lembrete ────────────────────────────────────────────────

async function markReminder(ids, field) {
  const res = await sb(`appointments?id=in.(${ids.join(',')})`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ [field]: true }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    console.error(`[reminder] PATCH ${field} falhou (${res.status}): ${body}`);
  }
}

// ── Principal ─────────────────────────────────────────────────────────────────

async function main() {
  const settings    = await loadSettings();
  const planClients = await loadPlanClients();

  if (settings.wa_enabled !== 'true') {
    console.log('[reminder] WhatsApp desativado. Nada a fazer.');
    return;
  }
  if (!WA_API_KEY) WA_API_KEY = settings.wa_api_key || '';
  if (!WA_API_KEY) {
    console.error('[reminder] Sem API key do WhatsApp.');
    return;
  }

  const normalHours   = Math.max(1, parseInt(settings.reminder_normal_hours || '1', 10));
  const normalLeadMin = normalHours * 60;
  const tplNormal     = settings.wa_reminder_template          || DEFAULT_TPL;
  const tplNormal24h  = settings.wa_reminder_template_24h      || DEFAULT_NORMAL_TPL_24H;
  const tplPlan24h    = settings.wa_plan_reminder_template_24h || DEFAULT_PLAN_TPL_24H;
  const tplPlan1h     = settings.wa_plan_reminder_template_1h  || DEFAULT_PLAN_TPL_1H;

  // Busca agendamentos dos próximos 2 dias (cobre tanto normal quanto 24h)
  const dates = [brDate(0), brDate(1), brDate(2)];
  const sel =
    'select=id,appointment_date,appointment_time,customer_name,customer_phone,' +
    'is_plan_client,reminder_sent,reminder_24h_sent,' +
    'barbers(name),services(name)';
  const res = await sb(
    `appointments?${sel}` +
    `&appointment_date=in.(${dates.join(',')})` +
    `&status=in.(scheduled,confirmed)` +
    // traz linhas onde pelo menos um dos lembretes ainda não foi enviado
    `&or=(reminder_sent.eq.false,reminder_24h_sent.eq.false)`,
  );
  const rows = await res.json();
  if (!Array.isArray(rows)) {
    console.error('[reminder] Erro ao buscar agendamentos:', rows);
    return;
  }

  // Agrupa por cliente + data + barbeiro para unir serviços consecutivos
  const byKey = new Map();
  for (const r of rows) {
    const key = `${r.customer_phone}|${r.appointment_date}|${r.barbers?.name || ''}`;
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(r);
  }

  let sent = 0;

  for (const [, items] of byKey) {
    items.sort((a, b) => a.appointment_time.localeCompare(b.appointment_time));

    for (const run of splitRuns(items)) {
      const first    = run[0];
      const m        = minutesUntil(first.appointment_date, first.appointment_time);
      const isPlan   = first.is_plan_client === true;
      const servicos = run.map(i => i.services?.name).filter(Boolean).join(', ');
      const hora     = first.appointment_time.slice(0, 5);
      const [y, mo, d] = first.appointment_date.split('-');
      const ids      = run.map(i => i.id);

      const vars = {
        cliente:  first.customer_name || 'cliente',
        data:     `${d}/${mo}/${y}`,
        hora,
        servico:  servicos || 'serviço',
        barbeiro: first.barbers?.name || '',
        pix:      isPlan ? pixLineFor(planClients, first.customer_phone) : '',
      };

      // ── Lembrete de 24h (só para agendamentos que NÃO são hoje) ──
      // Se o agendamento for hoje, vai direto para o lembrete normal para
      // não mandar template com "amanhã" num horário que é ainda hoje.
      if (first.reminder_24h_sent === false && m > normalLeadMin && m <= 1500 && first.appointment_date !== brDate(0)) {
        const tpl = isPlan ? tplPlan24h : tplNormal24h;
        const msg = buildMessage(tpl, vars);
        const ok  = await sendWhatsapp(first.customer_phone, msg);
        if (ok) {
          await markReminder(ids, 'reminder_24h_sent');
          sent++;
          console.log(`[reminder] 24h → ${first.customer_phone} — ${hora}`);
        }
        continue; // não processa o lembrete normal nesta rodada
      }

      // ── Lembrete normal (todos os clientes não lembrados ainda) ──────────
      if (first.reminder_sent === false && m > 0 && m <= normalLeadMin) {
        const tpl = isPlan ? tplPlan1h : tplNormal;
        const msg = buildMessage(tpl, vars);
        const ok  = await sendWhatsapp(first.customer_phone, msg);
        if (ok) {
          await markReminder(ids, 'reminder_sent');
          // Se for plano e o 24h ainda não foi marcado, marca também
          if (isPlan && first.reminder_24h_sent === false) {
            await markReminder(ids, 'reminder_24h_sent');
          }
          sent++;
          console.log(`[reminder] ${normalHours}h → ${first.customer_phone} — ${hora}`);
        }
      }
    }
  }

  console.log(`[reminder] concluído. ${sent} lembrete(s) enviado(s).`);
}

main().catch(e => {
  console.error('[reminder] erro fatal:', e);
  process.exit(1);
});
