// Supabase Edge Function — send-whatsapp
// Deploy: supabase functions deploy send-whatsapp

const GRAPH_VERSION = 'v19.0';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, content-type',
      },
    });
  }

  try {
    const { phone, message, accessToken, phoneNumberId } = await req.json();

    if (!phone || !message || !accessToken || !phoneNumberId) {
      return Response.json({ ok: false, error: 'Parâmetros ausentes.' }, { status: 400 });
    }

    const url = `https://graph.facebook.com/${GRAPH_VERSION}/${phoneNumberId}/messages`;

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to: phone,
        type: 'text',
        text: { body: message },
      }),
    });

    const data = await res.json();

    return Response.json(
      { ok: res.ok, data },
      {
        status: res.ok ? 200 : res.status,
        headers: { 'Access-Control-Allow-Origin': '*' },
      },
    );
  } catch (err) {
    return Response.json(
      { ok: false, error: String(err) },
      { status: 500, headers: { 'Access-Control-Allow-Origin': '*' } },
    );
  }
});
