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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return reply(500, { error: "Server configuration is incomplete" });

  let input: any;
  try { input = await req.json(); } catch { return reply(400, { error: "Invalid JSON body" }); }

  const customerName = String(input?.customer?.name ?? "").trim();
  const customerPhone = String(input?.customer?.phone ?? "").trim();
  const address = String(input?.customer?.address ?? "").trim();
  const paymentMethod = String(input?.paymentMethod ?? "cod");
  const requestedItems = input?.items;

  if (customerName.length < 2 || customerName.length > 100) return reply(400, { error: "Enter a valid full name" });
  if (!/^[0-9+() -]{10,20}$/.test(customerPhone)) return reply(400, { error: "Enter a valid phone number" });
  if (address.length < 8 || address.length > 500) return reply(400, { error: "Enter a valid delivery address" });
  if (paymentMethod !== "cod") return reply(400, { error: "Online payments are not enabled yet. Choose COD for now." });
  if (!Array.isArray(requestedItems) || requestedItems.length < 1 || requestedItems.length > 30) return reply(400, { error: "Cart is empty or contains too many items" });

  const normalized = new Map<number, number>();
  for (const item of requestedItems) {
    const id = Number(item?.id);
    const quantity = Number(item?.quantity);
    if (!Number.isInteger(id) || id < 1 || !Number.isInteger(quantity) || quantity < 1 || quantity > 50) {
      return reply(400, { error: "Invalid cart item" });
    }
    normalized.set(id, (normalized.get(id) ?? 0) + quantity);
  }

  // The browser-supplied price is ignored. Prices are read from the trusted catalogue.
  const catalog = [
    { id: 1, slug: "studio-wireless-headphones", name: "Studio Wireless Headphones", category: "Tech", price_inr: 2499, emoji: "🎧", stock_quantity: 100, is_active: true },
    { id: 2, slug: "smart-fitness-watch", name: "Smart Fitness Watch", category: "Tech", price_inr: 1899, emoji: "⌚", stock_quantity: 100, is_active: true },
    { id: 3, slug: "everyday-sling-bag", name: "Everyday Sling Bag", category: "Lifestyle", price_inr: 999, emoji: "🎒", stock_quantity: 100, is_active: true },
    { id: 4, slug: "minimal-desk-lamp", name: "Minimal Desk Lamp", category: "Home", price_inr: 799, emoji: "💡", stock_quantity: 100, is_active: true },
    { id: 5, slug: "portable-bluetooth-speaker", name: "Portable Bluetooth Speaker", category: "Tech", price_inr: 1499, emoji: "🔊", stock_quantity: 100, is_active: true },
    { id: 6, slug: "insulated-travel-bottle", name: "Insulated Travel Bottle", category: "Lifestyle", price_inr: 499, emoji: "🥤", stock_quantity: 100, is_active: true },
    { id: 7, slug: "soft-glow-table-light", name: "Soft Glow Table Light", category: "Home", price_inr: 1199, emoji: "🪔", stock_quantity: 100, is_active: true },
    { id: 8, slug: "wireless-charging-pad", name: "Wireless Charging Pad", category: "Tech", price_inr: 899, emoji: "🔋", stock_quantity: 100, is_active: true },
  ];

  const items = [...normalized.entries()].map(([id, quantity]) => {
    const product = catalog.find((p) => p.id === id && p.is_active);
    if (!product) return null;
    return { product_id: null, product_name: product.name, unit_price_inr: product.price_inr, quantity, line_total_inr: product.price_inr * quantity };
  });
  if (items.some((item) => item === null)) return reply(400, { error: "One or more products are unavailable" });
  const safeItems = items as Array<{ product_id: null; product_name: string; unit_price_inr: number; quantity: number; line_total_inr: number }>;
  const subtotal = safeItems.reduce((sum, item) => sum + item.line_total_inr, 0);
  if (!Number.isSafeInteger(subtotal) || subtotal > 10_000_000) return reply(400, { error: "Order total is outside the allowed range" });

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const authHeader = req.headers.get("Authorization");
  let customerId: string | null = null;
  if (authHeader) {
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data } = await userClient.auth.getUser();
    customerId = data.user?.id ?? null;
  }

  // Insert header, then lines. Roll back the header if inserting line items fails.
  const { data: order, error: orderError } = await admin.from("orders").insert({
    customer_id: customerId,
    customer_name: customerName,
    customer_phone: customerPhone,
    address_line: address,
    payment_method: "cod",
    payment_status: "pending",
    order_status: "placed",
    subtotal_inr: subtotal,
    shipping_inr: 0,
    total_inr: subtotal,
  }).select("id, order_number, total_inr, order_status, created_at").single();

  if (orderError || !order) {
    console.error("Order header insert failed", orderError?.message);
    return reply(500, { error: "Could not create order. Please try again." });
  }

  const { error: itemsError } = await admin.from("order_items").insert(safeItems.map((item) => ({ ...item, order_id: order.id })));
  if (itemsError) {
    await admin.from("orders").delete().eq("id", order.id);
    console.error("Order items insert failed", itemsError.message);
    return reply(500, { error: "Could not save order items. Please try again." });
  }

  return reply(201, { order: { orderNumber: order.order_number, totalInr: order.total_inr, status: order.order_status, createdAt: order.created_at } });
});
