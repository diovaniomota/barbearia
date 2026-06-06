#!/usr/bin/env node
/**
 * Lembrete automático de agendamentos via WhatsApp.
 *
 * Roda na VPS (junto do servidor WhatsApp), agendado por cron a cada ~5 min.
 * Para cada agendamento que começa em ~LEAD_MINUTES, envia UM lembrete.
 * Agendamentos de múltiplos serviços (linhas consecutivas, ex: 9h e 9h30)
 * são agrupados em um único lembrete listando todos os serviços.
 *
 * Requisitos: Node 18+ (usa fetch nativo). Zero dependências (sem npm install).
 *
 * Variáveis de ambiente (defina em run.sh ou no systemd):
 *   SUPABASE_URL*          ex: https://xxxx.supabase.co
 *   SUPABASE_SERVICE_KEY*  service_role key (Supabase → Settings → API)
 *   WA_URL                 default http://localhost:3001
 *   WA_API_KEY             se vazio, lê wa_api_key de app_settings
 *   LEAD_MINUTES           antecedência do lembrete (default 60)
 *   TZ_OFFSET              fuso dos agendamentos (default -03:00 / Brasil)
 *   (* obrigatório)
 */

'use strict';

const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY || '';
const WA_URL       = (process.env.WA_URL || 'http://localhost:3001').replace(/\/$/, '');
let   WA_API_KEY   = process.env.WA_API_KEY || '';
const LEAD_MINUTES = parseInt(process.env.LEAD_MINUTES || '60', 10);
const TZ_OFFSET    = process.env.TZ_OFFSET || '-03:00';

const DEFAULT_TPL =
  '⏰ Lembrete do seu horário!\n\n' +
  'Olá {{cliente}}! Seu horário é hoje às {{hora}}.\n' +
  '✂️ Serviço: {{servico}}\n' +
  '💈 Profissional: {{barbeiro}}\n\n' +
  'Te esperamos! 👋';

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('[reminder] Faltam SUPABASE_URL e/ou SUPABASE_SERVICE_KEY.');
  process.exit(1);
}

// ── Helpers Supabase REST ─────────────────────────────────────────────────────

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

// Data YYYY-MM-DD no fuso America/Sao_Paulo (offsetDays: 0 = hoje, 1 = amanhã)
function brDate(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(d);
}

// Minutos até o horário do agendamento (negativo se já passou)
function minutesUntil(dateStr, timeStr) {
  const t = timeStr.slice(0, 5); // "HH:MM"
  const apptMs = Date.parse(`${dateStr}T${t}:00${TZ_OFFSET}`);
  return (apptMs - Date.now()) / 60000;
}

function timeToMin(t) {
  const [h, m] = t.slice(0, 5).split(':').map(Number);
  return h * 60 + m;
}

// ── Mensagem ──────────────────────────────────────────────────────────────────

function buildMessage(tpl, v) {
  return tpl
    .replaceAll('{{cliente}}', v.cliente)
    .replaceAll('{{data}}', v.data)
    .replaceAll('{{hora}}', v.hora)
    .replaceAll('{{servico}}', v.servico)
    .replaceAll('{{barbeiro}}', v.barbeiro);
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
    if (!res.ok) {
      console.warn(`[reminder] /send retornou ${res.status} para ${full}`);
    }
    return res.ok;
  } catch (e) {
    console.warn(`[reminder] erro ao chamar /send: ${e.message}`);
    return false;
  }
}

// Divide os itens (já ordenados por hora) em "corridas" de slots consecutivos
// de 30min — cada corrida é um agendamento (booking) distinto.
function splitRuns(items) {
  const runs = [];
  let cur = [];
  for (const it of items) {
    if (cur.length === 0) { cur.push(it); continue; }
    const prev = cur[cur.length - 1];
    const gap = timeToMin(it.appointment_time) - timeToMin(prev.appointment_time);
    if (gap === 30) cur.push(it);
    else { runs.push(cur); cur = [it]; }
  }
  if (cur.length) runs.push(cur);
  return runs;
}

// ── Principal ─────────────────────────────────────────────────────────────────

async function loadSettings() {
  const res = await sb(
    'app_settings?select=key,value&key=in.(wa_api_key,wa_enabled,wa_reminder_template)',
  );
  const rows = await res.json();
  const map = {};
  if (Array.isArray(rows)) for (const r of rows) map[r.key] = r.value;
  return map;
}

async function main() {
  const settings = await loadSettings();

  if (settings.wa_enabled !== 'true') {
    console.log('[reminder] WhatsApp desativado nas configurações. Nada a fazer.');
    return;
  }
  if (!WA_API_KEY) WA_API_KEY = settings.wa_api_key || '';
  if (!WA_API_KEY) {
    console.error('[reminder] Sem API key do WhatsApp (env WA_API_KEY ou app_settings.wa_api_key).');
    return;
  }
  const tpl = settings.wa_reminder_template || DEFAULT_TPL;

  // Busca agendamentos de hoje e amanhã, ativos e ainda não lembrados.
  const dates = [brDate(0), brDate(1)];
  const sel =
    'select=id,appointment_date,appointment_time,customer_name,customer_phone,' +
    'barbers(name),services(name)';
  const url =
    `appointments?${sel}` +
    `&appointment_date=in.(${dates.join(',')})` +
    `&status=in.(scheduled,confirmed,in_progress)` +
    `&reminder_sent=eq.false`;

  const res = await sb(url);
  const rows = await res.json();
  if (!Array.isArray(rows)) {
    console.error('[reminder] Erro ao buscar agendamentos:', rows);
    return;
  }

  // Agrupa por cliente + data + barbeiro e separa em bookings consecutivos.
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
      const first = run[0];
      const m = minutesUntil(first.appointment_date, first.appointment_time);
      if (!(m > 0 && m <= LEAD_MINUTES)) continue; // ainda não está na janela

      const servicos = run.map((i) => i.services?.name).filter(Boolean).join(', ');
      const hora = first.appointment_time.slice(0, 5);
      const [y, mo, d] = first.appointment_date.split('-');
      const msg = buildMessage(tpl, {
        cliente: first.customer_name || 'cliente',
        data: `${d}/${mo}/${y}`,
        hora,
        servico: servicos || 'serviço',
        barbeiro: first.barbers?.name || '',
      });

      const ok = await sendWhatsapp(first.customer_phone, msg);
      if (ok) {
        const ids = run.map((i) => i.id);
        await sb(`appointments?id=in.(${ids.join(',')})`, {
          method: 'PATCH',
          headers: { Prefer: 'return=minimal' },
          body: JSON.stringify({ reminder_sent: true }),
        });
        sent++;
        console.log(`[reminder] enviado p/ ${first.customer_phone} — ${servicos} às ${hora}`);
      }
    }
  }

  console.log(`[reminder] concluído. ${sent} lembrete(s) enviado(s).`);
}

main().catch((e) => {
  console.error('[reminder] erro fatal:', e);
  process.exit(1);
});
