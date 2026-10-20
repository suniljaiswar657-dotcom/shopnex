import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function reply(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), { status, headers: corsHeaders });
}

const storefrontIds: Record<number, string> = {
  1: "studio-wireless-headphones",
  2: "smart-fitness-watch",
  3: "everyday-sling-bag",
  4: "minimal-desk-lamp",
  5: "portable-bluetooth-speaker",
  6: "insulated-travel-bottle",
  7: "soft-glow-table-light",
  8: "wireless-charging-pad",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !serviceKey || !anonKey) return reply(500, { error: "Server configuration is incomplete" });

  let input: any;
  try { input = await req.json(); } catch { return reply(400, { error: "Invalid JSON body" }); }

  const customerName = String(input?.customer?.name ?? "").trim();
  const customerPhone = String(input?.customer?.phone ?? "").trim();
  const address = String(input?.customer?.address ?? "").trim();
  const requestedItems = input?.items;

  if (customerName.length < 2 || customerName.length > 100) return reply(400, { error: "Enter a valid full name" });
  if (!/^[0-9+() -]{10,20}$/.test(customerPhone)) return reply(400, { error: "Enter a valid phone number" });
  if (address.length < 8 || address.length > 500) return reply(400, { error: "Enter a valid delivery address" });
  if (input?.paymentMethod !== "cod") return reply(400, { error: "Online payments are not enabled yet. Choose COD for now." });
  if (!Array.isArray(requestedItems) || requestedItems.length < 1 || requestedItems.length > 30) return reply(400, { error: "Cart is empty or contains too many items" });

  const normalized = new Map<number, number>();
  for (const item of requestedItems) {
    const id = Number(item?.id);
    const quantity = Number(item?.quantity);
    if (!Number.isInteger(id) || !storefrontIds[id] || !Number.isInteger(quantity) || quantity < 1 || quantity > 50) {
      return reply(400, { error: "Invalid cart item" });
    }
    normalized.set(id, (normalized.get(id) ?? 0) + quantity);
  }
  const items = [...normalized.entries()].map(([id, quantity]) => ({ slug: storefrontIds[id], quantity }));

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  let customerId: string | null = null;
  const authHeader = req.headers.get("Authorization");
  if (authHeader && authHeader.startsWith("Bearer ")) {
    const token = authHeader.slice(7);
    if (token !== anonKey) {
      const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
      const { data } = await userClient.auth.getUser();
      customerId = data.user?.id ?? null;
    }
  }

  const { data, error } = await admin.rpc("create_shopnex_order", {
    p_customer_name: customerName,
    p_customer_phone: customerPhone,
    p_address_line: address,
    p_payment_method: "cod",
    p_customer_id: customerId,
    p_items: items,
  });

  if (error || !data) {
    console.error("Order RPC failed", error?.message);
    const message = error?.message ?? "";
    if (/unavailable|stock|quantity|cart|invalid|too high/i.test(message)) return reply(400, { error: message });
    return reply(500, { error: "Could not create order. Please try again." });
  }

  return reply(201, { order: { orderNumber: data.order_number, totalInr: data.total_inr, status: data.order_status, createdAt: data.created_at } });
});
