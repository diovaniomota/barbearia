// Supabase Edge Function — set-barber-password
// Permite que um admin (usuário autenticado não-anônimo) defina diretamente a
// senha de um barbeiro, sem enviar e-mail de redefinição.
//
// Deploy: supabase functions deploy set-barber-password
//
// Usa SUPABASE_SERVICE_ROLE_KEY (injetada automaticamente pelo Supabase no
// runtime) para chamar a Admin API. A service_role NUNCA fica no app cliente.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: cors });
  }

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // 1. Confere que quem chamou está autenticado (= admin, no modelo do app:
    //    qualquer usuário não-anônimo). A tela de Barbeiros já é restrita ao
    //    dono, mas validamos no servidor por segurança.
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace('Bearer ', '').trim();
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false },
    });
    const { data: { user }, error: userErr } = await callerClient.auth.getUser(token);
    if (userErr || !user || user.is_anonymous) {
      return Response.json(
        { ok: false, error: 'Não autorizado.' },
        { status: 401, headers: cors },
      );
    }

    // 2. Lê e valida os parâmetros.
    const { userId, newPassword } = await req.json();
    if (!userId || !newPassword || String(newPassword).length < 6) {
      return Response.json(
        { ok: false, error: 'Informe o barbeiro e uma senha de no mínimo 6 caracteres.' },
        { status: 400, headers: cors },
      );
    }

    // 3. Troca a senha direto via Admin API (service_role).
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });
    const { error } = await admin.auth.admin.updateUserById(String(userId), {
      password: String(newPassword),
    });
    if (error) {
      return Response.json(
        { ok: false, error: error.message },
        { status: 400, headers: cors },
      );
    }

    return Response.json({ ok: true }, { headers: cors });
  } catch (err) {
    return Response.json(
      { ok: false, error: String(err) },
      { status: 500, headers: cors },
    );
  }
});
