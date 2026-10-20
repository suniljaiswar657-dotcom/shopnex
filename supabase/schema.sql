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
