#!/usr/bin/env node
/**
 * Gerador de agendamentos recorrentes (clientes do plano).
 *
 * Roda na VPS uma vez por dia (ex: cron "0 2 * * *").
 * Para cada recurring_schedule ativo, cria os agendamentos das próximas
 * WINDOW_DAYS que ainda não existem — janela deslizante, sem acúmulo de um ano.
 *
 * Requisitos: Node 18+. Zero dependências externas.
 *
 * Variáveis de ambiente (mesmas do reminder.js):
 *   SUPABASE_URL*          ex: https://xxxx.supabase.co
 *   SUPABASE_SERVICE_KEY*  service_role key
 *   WINDOW_DAYS            dias à frente (default 30)
 *   TZ_OFFSET              fuso (default -03:00)
 */

'use strict';

const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY || '';
const WINDOW_DAYS  = parseInt(process.env.WINDOW_DAYS || '30', 10);

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('[recurring] Faltam SUPABASE_URL e/ou SUPABASE_SERVICE_KEY.');
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
      Prefer: init.method === 'POST' ? 'return=minimal' : undefined,
      ...(init.headers || {}),
    },
  });
}

// ── Datas ────────────────────────────────────────────────────────────────────

// Data YYYY-MM-DD no fuso São Paulo para offsetDays dias a partir de hoje
function brDate(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400_000);
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(d);
}

// JS day-of-week (0=Dom … 6=Sáb) de uma string "YYYY-MM-DD" sem desvio de fuso
function dowOf(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

// Adiciona `minutes` a uma string "HH:MM:SS" → "HH:MM:SS"
function addMin(timeStr, minutes) {
  const [h, m] = timeStr.slice(0, 5).split(':').map(Number);
  const total = h * 60 + m + minutes;
  const nh = Math.floor(total / 60) % 24;
  const nm = total % 60;
  return `${String(nh).padStart(2, '0')}:${String(nm).padStart(2, '0')}:00`;
}

const DOW_PT = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

// ── Principal ─────────────────────────────────────────────────────────────────

async function main() {
  // 1. Carrega todos os schedules ativos com dados relacionados
  const r = await sb(
    'recurring_schedules?is_active=eq.true' +
    '&select=id,day_of_week,appointment_time,barber_id,service_id,' +
    'plan_clients!plan_client_id(name,phone),' +
    'barbers!barber_id(name),' +
    'services!service_id(name,price,duration_blocks)',
  );
  const schedules = await r.json();
  if (!Array.isArray(schedules) || schedules.length === 0) {
    console.log('[recurring] Nenhum agendamento recorrente ativo.');
    return;
  }
  console.log(`[recurring] ${schedules.length} schedule(s) ativo(s).`);

  // 2. Janela de datas a verificar
  const dates = Array.from({ length: WINDOW_DAYS }, (_, i) => brDate(i));

  let created = 0;
  let skipped = 0;

  for (const sched of schedules) {
    // Normaliza os relacionamentos (podem vir como objeto ou array de 1 item)
    const client  = Array.isArray(sched.plan_clients) ? sched.plan_clients[0] : sched.plan_clients;
    const service = Array.isArray(sched.services)     ? sched.services[0]     : sched.services;

    if (!client?.phone) {
      console.warn(`[recurring] schedule ${sched.id} sem telefone de cliente — pulando.`);
      continue;
    }

    const phone   = String(client.phone).replace(/[^0-9]/g, '');
    const name    = client.name || 'Cliente';
    const blocks  = Number(service?.duration_blocks ?? 1) || 1;
    const price   = Number(service?.price ?? 0);
    const time    = sched.appointment_time; // "HH:MM:SS"

    // Datas desta semana que batem com o day_of_week configurado
    const targets = dates.filter(d => dowOf(d) === sched.day_of_week);

    for (const date of targets) {
      // Verifica se já existe um agendamento neste horário para este cliente/barbeiro
      const chk = await sb(
        `appointments?barber_id=eq.${sched.barber_id}` +
        `&appointment_date=eq.${date}` +
        `&appointment_time=eq.${time}` +
        `&customer_phone=eq.${phone}` +
        `&status=neq.cancelled` +
        `&select=id&limit=1`,
      );
      const existing = await chk.json();
      if (Array.isArray(existing) && existing.length > 0) {
        skipped++;
        continue;
      }

      // Cria um registro por bloco de 30 min (igual ao fluxo do cliente)
      const rows = [];
      for (let k = 0; k < blocks; k++) {
        rows.push({
          barber_id:        sched.barber_id,
          service_id:       sched.service_id,
          appointment_date: date,
          appointment_time: addMin(time, k * 30),
          customer_name:    name,
          customer_phone:   phone,
          status:           'scheduled',
          total_price:      k === 0 ? price : 0,
          is_plan_client:   true,
          source:           'recurring',
          notes:            `Recorrente automático — toda ${DOW_PT[sched.day_of_week]}`,
        });
      }

      const ins = await sb('appointments', {
        method: 'POST',
        body: JSON.stringify(rows),
      });

      if (ins.ok || ins.status === 201) {
        created++;
        console.log(`[recurring] ✓ ${name} em ${date} às ${time.slice(0, 5)}`);
      } else {
        const body = await ins.text();
        console.warn(`[recurring] erro ao criar para ${name} em ${date}: ${body}`);
      }
    }
  }

  console.log(`[recurring] concluído — ${created} criado(s), ${skipped} já existiam.`);
}

main().catch(e => {
  console.error('[recurring] erro fatal:', e);
  process.exit(1);
});
