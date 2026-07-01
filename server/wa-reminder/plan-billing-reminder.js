#!/usr/bin/env node
/**
 * Lembrete de vencimento da mensalidade do plano (diferente do lembrete de
 * agendamento em reminder.js — este é sobre a cobrança do plano em si).
 *
 * Roda na VPS uma vez por dia, ao meio-dia (ex: cron "0 12 * * *").
 * Para cada plan_client com `due_day` preenchido:
 *   - 7 dias antes do vencimento: "Resta uma semana para vencer".
 *   - No dia do vencimento: "Seu plano venceu hoje" + chave Pix (se a forma
 *     de pagamento do cliente for PIX) ou nada (se for cartão/outro).
 *
 * Requisitos: Node 18+. Zero dependências externas.
 *
 * Variáveis de ambiente (mesmas do reminder.js):
 *   SUPABASE_URL*          ex: https://xxxx.supabase.co
 *   SUPABASE_SERVICE_KEY*  service_role key
 *   WA_URL                 default http://localhost:3001
 *   WA_API_KEY             se vazio, lê wa_api_key de app_settings
 */

'use strict';

const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY || '';
const WA_URL       = (process.env.WA_URL || 'http://localhost:3001').replace(/\/$/, '');
let   WA_API_KEY   = process.env.WA_API_KEY || '';

const DEFAULT_WEEK_TPL =
  '⏳ Resta uma semana para o vencimento do seu plano {{plano}}, {{cliente}}!\n\n' +
  'Barbearia Toni Dinis 💈';

const DEFAULT_DUE_TPL =
  '📌 Olá {{cliente}}! Seu plano {{plano}} na Barbearia Toni Dinis venceu hoje.\n' +
  '{{pix}}\n' +
  'Obrigado pela confiança! 💈';

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('[plan-billing] Faltam SUPABASE_URL e/ou SUPABASE_SERVICE_KEY.');
  process.exit(1);
}

// ── Supabase REST ────────────────────────────────────────────────────────────

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

// ── Datas ────────────────────────────────────────────────────────────────────

function brDate(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(d);
}

function addDays(dateStr, n) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() + n);
  return dt.toISOString().slice(0, 10);
}

function nextMonth(y, m) {
  return m === 12 ? { y: y + 1, m: 1 } : { y, m: m + 1 };
}

// Dia de vencimento (1-31) aplicado a um mês, com clamp pro último dia
// existente (ex: due_day=31 em abril vira 30/04).
function billingDateForMonth(dueDay, y, m) {
  const lastDay = new Date(Date.UTC(y, m, 0)).getUTCDate(); // dia 0 do mês seguinte
  const day = Math.min(dueDay, lastDay);
  return `${y}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

// ── Mensagem ─────────────────────────────────────────────────────────────────

function buildMessage(tpl, v) {
  const msg = tpl
    .replaceAll('{{cliente}}', v.cliente)
    .replaceAll('{{plano}}',   v.plano)
    .replaceAll('{{pix}}',     v.pix || '');
  return msg.replace(/\n[ \t]*\n/g, '\n');
}

function pixLineFor(client) {
  const isPix = (client.payment_method || '').toUpperCase() === 'PIX';
  if (!isPix) return '';
  return client.pix_key
    ? `🔑 Pagamento via Pix: ${client.pix_key}`
    : '🔑 Pagamento via Pix — confirme a chave com o barbeiro.';
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
    if (!res.ok) console.warn(`[plan-billing] /send ${res.status} p/ ${full}`);
    return res.ok;
  } catch (e) {
    console.warn(`[plan-billing] erro /send: ${e.message}`);
    return false;
  }
}

// ── Configurações ────────────────────────────────────────────────────────────

async function loadSettings() {
  const keys = [
    'wa_api_key', 'wa_enabled',
    'wa_plan_due_week_template',
    'wa_plan_due_today_template',
  ];
  const res = await sb(`app_settings?select=key,value&key=in.(${keys.join(',')})`);
  const rows = await res.json();
  const map = {};
  if (Array.isArray(rows)) for (const r of rows) map[r.key] = r.value;
  return map;
}

async function markSent(id, field, dateStr) {
  const res = await sb(`plan_clients?id=eq.${id}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ [field]: dateStr }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    console.error(`[plan-billing] PATCH ${field} falhou (${res.status}): ${body}`);
  }
}

// ── Principal ────────────────────────────────────────────────────────────────

async function main() {
  const settings = await loadSettings();

  if (settings.wa_enabled !== 'true') {
    console.log('[plan-billing] WhatsApp desativado. Nada a fazer.');
    return;
  }
  if (!WA_API_KEY) WA_API_KEY = settings.wa_api_key || '';
  if (!WA_API_KEY) {
    console.error('[plan-billing] Sem API key do WhatsApp.');
    return;
  }

  const tplWeek = settings.wa_plan_due_week_template  || DEFAULT_WEEK_TPL;
  const tplDue  = settings.wa_plan_due_today_template || DEFAULT_DUE_TPL;

  const res = await sb(
    'plan_clients?select=id,name,phone,plan_name,payment_method,pix_key,due_day,' +
    'plan_week_reminder_sent_for,plan_due_reminder_sent_for' +
    '&due_day=not.is.null',
  );
  const clients = await res.json();
  if (!Array.isArray(clients)) {
    console.error('[plan-billing] Erro ao buscar plan_clients:', clients);
    return;
  }

  const today = brDate(0);
  const [ty, tm] = today.split('-').map(Number);

  let sent = 0;

  for (const client of clients) {
    const dueDay = Number(client.due_day);
    if (!dueDay || dueDay < 1 || dueDay > 31) continue;

    const thisBilling = billingDateForMonth(dueDay, ty, tm);
    const nm           = nextMonth(ty, tm);
    const nextBilling  = billingDateForMonth(dueDay, nm.y, nm.m);

    const vars = {
      cliente: client.name || 'cliente',
      plano:   client.plan_name || 'plano',
      pix:     pixLineFor(client),
    };

    // ── Vencimento hoje ──
    if (today === thisBilling && client.plan_due_reminder_sent_for !== thisBilling) {
      const msg = buildMessage(tplDue, vars);
      const ok  = await sendWhatsapp(client.phone, msg);
      if (ok) {
        await markSent(client.id, 'plan_due_reminder_sent_for', thisBilling);
        sent++;
        console.log(`[plan-billing] vencimento → ${client.phone} (${client.name})`);
      }
    }

    // ── Uma semana antes (cobre o vencimento deste mês e do próximo,
    //    já que perto da virada do mês a data de -7 dias pode cair no mês atual) ──
    const weekBeforeThis = addDays(thisBilling, -7);
    const weekBeforeNext = addDays(nextBilling, -7);

    if (today === weekBeforeThis && client.plan_week_reminder_sent_for !== thisBilling) {
      const msg = buildMessage(tplWeek, vars);
      const ok  = await sendWhatsapp(client.phone, msg);
      if (ok) {
        await markSent(client.id, 'plan_week_reminder_sent_for', thisBilling);
        sent++;
        console.log(`[plan-billing] semana antes → ${client.phone} (${client.name})`);
      }
    } else if (today === weekBeforeNext && client.plan_week_reminder_sent_for !== nextBilling) {
      const msg = buildMessage(tplWeek, vars);
      const ok  = await sendWhatsapp(client.phone, msg);
      if (ok) {
        await markSent(client.id, 'plan_week_reminder_sent_for', nextBilling);
        sent++;
        console.log(`[plan-billing] semana antes → ${client.phone} (${client.name})`);
      }
    }
  }

  console.log(`[plan-billing] concluído. ${sent} lembrete(s) enviado(s).`);
}

main().catch(e => {
  console.error('[plan-billing] erro fatal:', e);
  process.exit(1);
});
