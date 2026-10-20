# SHOPNEX Supabase setup

This folder contains the production database schema and a server-side order-creation Edge Function. It is intentionally separate from the static frontend.

## Important current status

These files are committed source code, not proof that a Supabase project has been connected. Do not claim orders are live until the schema and function are deployed to a dedicated SHOPNEX project and a real test order is read back from the database.

## Setup sequence

1. Create or select a dedicated Supabase project for SHOPNEX. Do not reuse the unrelated projects in the account.
2. Apply `schema.sql` in the Supabase SQL Editor.
3. Seed `public.products` with the store's actual catalogue and inventory.
4. Deploy `functions/create-order/index.ts` as the `create-order` Edge Function.
5. Configure the function's server-side environment variables using Supabase secrets. Never commit secrets or place the service-role key in browser code.
6. Connect the storefront checkout to the function and only show success after it returns HTTP 201.
7. Verify a test order and its order_items rows in the database; then run Supabase security advisors.

## Security notes

- Public users can read active products only.
- Guest order creation is intended to go through the server-side Edge Function; direct anonymous INSERT on orders/order_items is not granted.
- Customer order visibility is restricted to the authenticated owner; admins are checked using trusted `app_metadata.role = 'admin'`, not user-editable metadata.
- The function currently uses the same eight starter products and sample prices as the storefront. Before taking real orders, move the catalogue lookup to the database and implement a single database transaction/RPC for header + line items, inventory locking, rate limits, spam protection, and shipping/tax policy.
- COD is the only accepted method. Razorpay is deliberately rejected until server-side payment order creation and signature/webhook verification are implemented.
- The current HTML checkout remains local-demo-only until its browser handler is replaced with a call to the deployed function.
