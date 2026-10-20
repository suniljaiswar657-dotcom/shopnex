# SHOPNEX

A responsive, single-store ecommerce storefront starter. Built with plain HTML, CSS and JavaScript so the initial storefront can be previewed without installing dependencies.

## Current features

- Mobile-first responsive storefront with animated hero
- Product cards and category filters
- Live product search
- Add-to-cart and quantity controls
- Cart item count and subtotal in INR
- Cart persists across refreshes in the same browser using local storage
- Checkout form validates basic customer details
- Demo orders are saved locally in the browser and can be exported as JSON
- Accessible cart drawer and keyboard Escape close
- Supabase-ready schema with RLS policies and sample catalogue seed
- Server-side order function designed to calculate totals from database prices and update stock atomically
- Admin dashboard source at `/admin.html` for authenticated order status and product/stock management
- No external runtime libraries

## Run locally

Open `index.html` in a browser. No build command or package installation is required.

## Deploy to Vercel

1. Sign in to Vercel.
2. Select **Add New → Project**.
3. Import the GitHub repository `suniljaiswar657-dotcom/shopnex`.
4. If Vercel asks for a framework preset, choose **Other**.
5. Leave Build Command and Output Directory empty for this plain static HTML version.
6. Deploy. Verify the resulting URL before sharing it.

## Important status and limitations

This is still a frontend prototype. The displayed catalogue and ratings are sample content. The cart and demo orders use browser local storage and stay on that device/browser; they are NOT sent to a server or store operator. The checkout form is not production order processing, and selecting COD or online payment does not arrange delivery or take payment. Supabase is not yet connected to a dedicated SHOPNEX project. The admin dashboard and Edge Function are source files only until a project is selected, schema is applied, secrets are configured, and the function is deployed. Shipping, Razorpay/UPI payment verification, email notifications, rate limiting, and production tests are not connected yet.

Never commit API secrets, Supabase service-role keys, payment gateway secrets, or `.env` files to a public repository. Add real payment processing only with server-side order creation and verified payment signatures/webhooks.

## Suggested next implementation phase

1. Create/select a dedicated SHOPNEX Supabase project and configure the public URL/publishable key in `shopnex-config.js`.
2. Apply `supabase/schema.sql`; seed catalogue rows and verify RLS policies.
3. Deploy `supabase/functions/create-order/index.ts` and verify required Edge Function secrets.
4. Set trusted `app_metadata.role = admin` for the store operator and test `/admin.html` with a real admin login.
5. Place a real COD test order and verify the order and line items in the database before accepting customers.
6. Add Razorpay with server-side signature/webhook verification, shipping/notifications, rate limiting, automated tests, and production review.
