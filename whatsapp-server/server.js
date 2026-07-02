// Polyfill Web Crypto para Node.js < 19
if (!globalThis.crypto) {
  globalThis.crypto = require('crypto').webcrypto;
}

const express = require('express');
const cors    = require('cors');
const qrcode  = require('qrcode');
const pino    = require('pino');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
} = require('@whiskeysockets/baileys');
const { Boom } = require('@hapi/boom');
const path = require('path');
const fs   = require('fs');

// ── Config ────────────────────────────────────────────────────────────────────

const PORT    = process.env.PORT    || 3000;
const API_KEY = process.env.API_KEY || 'minha-chave-secreta';

// Apaga o CONTEÚDO da pasta sessao (não o diretório em si, que é bind mount).
// Tenta várias vezes pois o Baileys pode ter arquivos abertos momentaneamente.
function clearSession(retries = 6, delay = 700) {
  return new Promise((resolve) => {
    const attempt = (left) => {
      try {
        if (fs.existsSync('sessao')) {
          for (const f of fs.readdirSync('sessao')) {
            fs.rmSync(path.join('sessao', f), { recursive: true, force: true });
          }
        }
        resolve();
      } catch (e) {
        if (left > 0 && (e.code === 'EBUSY' || e.code === 'ENOTEMPTY')) {
          setTimeout(() => attempt(left - 1), delay);
        } else {
          if (e.code !== 'ENOENT') console.log('Sessão não apagada:', e.message);
          resolve();
        }
      }
    };
    attempt(retries);
  });
}

// ── Estado ────────────────────────────────────────────────────────────────────

let sock        = null;
let qrBase64    = null;
let connected   = false;
let phoneNumber = null;
let retryCount  = 0;
const MAX_RETRIES = 10;

// Cache das últimas mensagens enviadas. Quando o destinatário não consegue
// descriptografar ("Aguardando mensagem"), o WhatsApp pede reenvio e o Baileys
// busca o conteúdo aqui (getMessage) para reenviar com chaves novas.
const messageStore = new Map();
const MESSAGE_STORE_MAX = 500;

function storeMessage(msg) {
  if (!msg?.key?.id || !msg.message) return;
  messageStore.set(msg.key.id, msg.message);
  if (messageStore.size > MESSAGE_STORE_MAX) {
    messageStore.delete(messageStore.keys().next().value);
  }
}

// Watchdog: se ficar desconectado por muito tempo sem QR aguardando leitura
// (conexão zumbi que não dispara evento de desconexão), encerra o processo —
// o Docker (restart: unless-stopped) sobe o container de novo.
const WATCHDOG_MS = 10 * 60 * 1000;
let disconnectedSince = Date.now();
setInterval(() => {
  if (connected || qrBase64 !== null) {
    disconnectedSince = null;
  } else if (disconnectedSince === null) {
    disconnectedSince = Date.now();
  } else if (Date.now() - disconnectedSince > WATCHDOG_MS) {
    console.error('Watchdog: desconectado há mais de 10 min. Encerrando para reiniciar.');
    process.exit(1);
  }
}, 30_000);

// ── Express ───────────────────────────────────────────────────────────────────

const app = express();
app.use(cors());
app.use(express.json());

app.use((req, res, next) => {
  const key = req.headers['x-api-key']
    ?? req.headers['authorization']?.replace('Bearer ', '');
  if (key !== API_KEY) {
    return res.status(401).json({ ok: false, error: 'Chave inválida.' });
  }
  next();
});

// ── Rotas ─────────────────────────────────────────────────────────────────────

app.get('/status', (req, res) => {
  res.json({ connected, phone: phoneNumber, hasQR: qrBase64 !== null });
});

app.get('/qr', (req, res) => {
  if (connected) return res.json({ connected: true, qr: null, phone: phoneNumber });
  res.json({ connected: false, qr: qrBase64 });
});

app.post('/send', async (req, res) => {
  if (!connected) {
    return res.status(503).json({ ok: false, error: 'WhatsApp desconectado.' });
  }
  const { phone, message } = req.body;
  if (!phone || !message) {
    return res.status(400).json({ ok: false, error: 'phone e message obrigatórios.' });
  }
  try {
    const clean    = phone.replace(/[^0-9]/g, '');
    const withCode = clean.startsWith('55') ? clean : `55${clean}`;
    const jid      = withCode + '@s.whatsapp.net';

    console.log(`Enviando para ${jid}...`);

    // Verifica se o número tem WhatsApp
    const [result] = await sock.onWhatsApp(jid);
    if (!result?.exists) {
      console.log(`Número ${jid} não tem WhatsApp.`);
      return res.status(422).json({ ok: false, error: 'Número não encontrado no WhatsApp.' });
    }

    // Usa o JID verificado (pode diferir do informado — números com/sem 9)
    const sent = await sock.sendMessage(result.jid, { text: message });
    storeMessage(sent);
    console.log(`Mensagem enviada para ${result.jid}`);
    res.json({ ok: true });
  } catch (err) {
    console.error('Erro ao enviar:', err.message);
    res.status(500).json({ ok: false, error: err.message });
  }
});

app.post('/logout', async (req, res) => {
  try {
    await sock?.logout();
    connected   = false;
    qrBase64    = null;
    phoneNumber = null;
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// Limpa sessão corrompida e força novo QR
app.post('/reset-session', async (req, res) => {
  try {
    sock?.ev?.removeAllListeners();
    await sock?.ws?.close();
    connected   = false;
    qrBase64    = null;
    phoneNumber = null;
    retryCount  = 0;
    res.json({ ok: true, message: 'Sessão resetada. Novo QR em breve.' });
    clearSession().then(() => setTimeout(connect, 1000));
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ── Conexão WhatsApp ──────────────────────────────────────────────────────────

async function connect() {
  try {
    const { state, saveCreds } = await useMultiFileAuthState('sessao');

    let version;
    try {
      const result = await fetchLatestBaileysVersion();
      version = result.version;
      console.log('Versão Baileys:', version);
    } catch (_) {
      version = [2, 3000, 1015901307];
      console.log('Usando versão padrão Baileys');
    }

    sock = makeWASocket({
      version,
      logger: pino({ level: 'silent' }),
      auth: state,
      // Atende pedidos de reenvio quando o destinatário fica "Aguardando mensagem"
      getMessage: async (key) => {
        const msg = messageStore.get(key.id);
        console.log(`Pedido de reenvio (msg ${key.id}): ${msg ? 'encontrada no cache, reenviando' : 'não encontrada no cache'}`);
        return msg;
      },
    });

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        qrBase64  = await qrcode.toDataURL(qr);
        connected = false;
        console.log('QR Code gerado. Escaneie pelo app.');
      }

      if (connection === 'open') {
        connected   = true;
        qrBase64    = null;
        phoneNumber = sock.user?.id?.split(':')[0] ?? null;
        retryCount  = 0;
        console.log('WhatsApp conectado! Número:', phoneNumber);
      }

      if (connection === 'close') {
        connected = false;
        const code = (lastDisconnect?.error instanceof Boom)
          ? lastDisconnect.error.output.statusCode
          : 0;
        const loggedOut = code === DisconnectReason.loggedOut;
        const rawErr = lastDisconnect?.error;
        console.log('Desconectado (código', code, '). Reconectar:', !loggedOut);
        if (rawErr) console.log('  → Erro bruto:', rawErr?.message ?? rawErr);

        if (loggedOut || (code === 0 && retryCount === 0)) {
          const reason = loggedOut ? 'loggedOut' : 'falha imediata (credenciais inválidas)';
          console.log(`Sessão inválida (${reason}). Limpando e aguardando QR...`);
          retryCount = 0;
          clearSession().then(() => setTimeout(connect, 3000));
        } else if (retryCount < MAX_RETRIES) {
          retryCount++;
          const delay = Math.min(3000 * retryCount, 30000); // backoff até 30s
          console.log(`Tentativa ${retryCount}/${MAX_RETRIES} em ${delay / 1000}s...`);
          setTimeout(connect, delay);
        } else {
          console.error(`Máximo de ${MAX_RETRIES} tentativas atingido. Encerrando — o Docker reinicia o container.`);
          process.exit(1);
        }
      }
    });

  } catch (err) {
    console.error('Erro ao iniciar conexão WhatsApp:', err);
    setTimeout(connect, 5000);
  }
}

// ── Start ─────────────────────────────────────────────────────────────────────

app.listen(PORT, async () => {
  console.log('Servidor rodando na porta', PORT);
  console.log('API_KEY:', API_KEY === 'minha-chave-secreta' ? 'PADRÃO (troque!)' : 'personalizada');
  await connect();
});
