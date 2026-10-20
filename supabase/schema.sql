-- SHOPNEX production schema (Postgres / Supabase)
-- Apply only to the dedicated SHOPNEX Supabase project.
-- This file intentionally does not create public order-insert policies.
-- Guest orders must be created through the trusted create-order Edge Function.

create extension if not exists pgcrypto;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text not null default '',
  category text not null,
  price_inr integer not null check (price_inr >= 0),
  compare_at_price_inr integer check (compare_at_price_inr is null or compare_at_price_inr >= price_inr),
  image_url text,
  emoji text not null default '🛍️',
  badge text,
  rating numeric(2,1) not null default 0 check (rating >= 0 and rating <= 5),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('SN-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 12))),
  customer_id uuid references auth.users(id) on delete set null,
  customer_name text not null check (char_length(trim(customer_name)) between 2 and 100),
  customer_phone text not null check (char_length(trim(customer_phone)) between 10 and 20),
  address_line text not null check (char_length(trim(address_line)) between 8 and 500),
  payment_method text not null check (payment_method in ('cod','razorpay')),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed','refunded')),
  order_status text not null default 'placed' check (order_status in ('placed','confirmed','packed','shipped','delivered','cancelled')),
  subtotal_inr integer not null check (subtotal_inr >= 0),
  shipping_inr integer not null default 0 check (shipping_inr >= 0),
  total_inr integer not null check (total_inr = subtotal_inr + shipping_inr),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price_inr integer not null check (unit_price_inr >= 0),
  quantity integer not null check (quantity between 1 and 50),
  line_total_inr integer not null check (line_total_inr = unit_price_inr * quantity),
  created_at timestamptz not null default now()
);

-- Admin access is based on trusted app_metadata, never editable user_metadata.
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "Anyone can view active products" on public.products;
create policy "Anyone can view active products"
on public.products for select to anon, authenticated
using (is_active = true);

drop policy if exists "Admins can manage products" on public.products;
create policy "Admins can manage products"
on public.products for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Customers can view their own orders" on public.orders;
create policy "Customers can view their own orders"
on public.orders for select to authenticated
using ((select auth.uid()) = customer_id);

drop policy if exists "Admins can view and manage all orders" on public.orders;
create policy "Admins can view and manage all orders"
on public.orders for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Customers can view their own order items" on public.order_items;
create policy "Customers can view their own order items"
on public.order_items for select to authenticated
using (exists (
  select 1 from public.orders o
  where o.id = order_id and o.customer_id = (select auth.uid())
));

drop policy if exists "Admins can view and manage all order items" on public.order_items;
create policy "Admins can view and manage all order items"
on public.order_items for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- Do not grant anon/authenticated INSERT on orders/order_items.
-- Trusted Edge Function using server-side SUPABASE_SERVICE_ROLE_KEY creates orders.
-- Never put the service-role key in index.html, a NEXT_PUBLIC_* variable, or GitHub.

grant select on public.products to anon, authenticated;
grant select on public.orders, public.order_items to authenticated;
grant insert, update, delete on public.products to authenticated;
grant update, delete on public.orders, public.order_items to authenticated;

-- Explicit server-side role permissions for trusted Edge Functions.
grant all privileges on public.products, public.orders, public.order_items to service_role;


-- Starter catalogue. Replace sample content/prices/stock before accepting real customers.
insert into public.products (slug,name,description,category,price_inr,compare_at_price_inr,emoji,badge,rating,stock_quantity,is_active)
values
 ('studio-wireless-headphones','Studio Wireless Headphones','Wireless everyday listening headphones','Tech',2499,3299,'🎧','BESTSELLER',4.8,100,true),
 ('smart-fitness-watch','Smart Fitness Watch','Smart watch for daily activity','Tech',1899,2499,'⌚','POPULAR',4.7,100,true),
 ('everyday-sling-bag','Everyday Sling Bag','Compact everyday carry bag','Lifestyle',999,1299,'🎒','NEW',4.6,100,true),
 ('minimal-desk-lamp','Minimal Desk Lamp','Minimal light for your desk','Home',799,1099,'💡','VALUE PICK',4.5,100,true),
 ('portable-bluetooth-speaker','Portable Bluetooth Speaker','Portable speaker for everyday use','Tech',1499,1999,'🔊','TRENDING',4.7,100,true),
 ('insulated-travel-bottle','Insulated Travel Bottle','Reusable insulated travel bottle','Lifestyle',499,699,'🥤','DAILY ESSENTIAL',4.6,100,true),
 ('soft-glow-table-light','Soft Glow Table Light','Warm table lighting','Home',1199,1599,'🪔','NEW',4.5,100,true),
 ('wireless-charging-pad','Wireless Charging Pad','Wireless charging pad','Tech',899,1199,'🔋','SMART PICK',4.6,100,true)
on conflict (slug) do nothing;

-- Atomic order creation: lock products, calculate prices in the database, decrement stock,
-- and write order + line items in a single transaction. Invoker privileges are retained.
create or replace function public.create_shopnex_order(
  p_customer_name text,
  p_customer_phone text,
  p_address_line text,
  p_payment_method text,
  p_customer_id uuid,
  p_items jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_subtotal integer := 0;
  v_item jsonb;
  v_slug text;
  v_qty integer;
  v_product public.products%rowtype;
begin
  if char_length(trim(p_customer_name)) < 2 or char_length(trim(p_customer_name)) > 100 then
    raise exception 'Invalid customer name';
  end if;
  if char_length(trim(p_customer_phone)) < 10 or char_length(trim(p_customer_phone)) > 20 then
    raise exception 'Invalid phone number';
  end if;
  if char_length(trim(p_address_line)) < 8 or char_length(trim(p_address_line)) > 500 then
    raise exception 'Invalid delivery address';
  end if;
  if p_payment_method <> 'cod' then raise exception 'Online payments are not enabled'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 30 then
    raise exception 'Invalid cart';
  end if;

  -- First pass validates availability and calculates the authoritative total while locking rows.
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_slug := v_item ->> 'slug';
    v_qty := (v_item ->> 'quantity')::integer;
    if v_qty < 1 or v_qty > 50 then raise exception 'Invalid item quantity'; end if;
    select * into v_product from public.products where slug = v_slug and is_active = true for update;
    if not found then raise exception 'Product unavailable'; end if;
    if v_product.stock_quantity < v_qty then raise exception 'Insufficient stock for %', v_product.name; end if;
    v_subtotal := v_subtotal + (v_product.price_inr * v_qty);
  end loop;
  if v_subtotal > 10000000 then raise exception 'Order total too high'; end if;

  insert into public.orders (customer_id, customer_name, customer_phone, address_line, payment_method, payment_status, order_status, subtotal_inr, shipping_inr, total_inr)
  values (p_customer_id, trim(p_customer_name), trim(p_customer_phone), trim(p_address_line), 'cod', 'pending', 'placed', v_subtotal, 0, v_subtotal)
  returning id, order_number into v_order_id, v_order_number;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_slug := v_item ->> 'slug';
    v_qty := (v_item ->> 'quantity')::integer;
    select * into v_product from public.products where slug = v_slug and is_active = true for update;
    insert into public.order_items (order_id, product_id, product_name, unit_price_inr, quantity, line_total_inr)
    values (v_order_id, v_product.id, v_product.name, v_product.price_inr, v_qty, v_product.price_inr * v_qty);
    update public.products set stock_quantity = stock_quantity - v_qty, updated_at = now() where id = v_product.id;
  end loop;

  return jsonb_build_object('id', v_order_id, 'order_number', v_order_number, 'total_inr', v_subtotal, 'order_status', 'placed', 'created_at', now());
end;
$$;

revoke all on function public.create_shopnex_order(text,text,text,text,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.create_shopnex_order(text,text,text,text,uuid,jsonb) to service_role;
