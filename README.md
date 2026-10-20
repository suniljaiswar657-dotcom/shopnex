# SHOPNEX

A responsive, single-store ecommerce storefront starter. Built with plain HTML, CSS and JavaScript so the initial storefront can be previewed without installing dependencies.

## Current features

- Mobile-first responsive storefront with animated hero
- Product cards and category filters
- Live product search
- Add-to-cart and quantity controls
- Cart item count and subtotal in INR
- Accessible cart drawer and keyboard Escape close
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

This is the initial frontend only. The displayed catalogue and ratings are sample content; the cart is stored in browser memory and resets on refresh. Checkout intentionally does not create orders or collect payment. Supabase authentication/database, admin product management, shipping, order creation, Razorpay/UPI payment verification, email notifications, and production tests are not connected yet.

Never commit API secrets, Supabase service-role keys, payment gateway secrets, or `.env` files to a public repository. Add real payment processing only with server-side order creation and verified payment signatures/webhooks.

## Suggested next implementation phase

1. Connect Supabase project and schema.
2. Add server-side product catalogue and secure admin role checks.
3. Persist cart and create orders via server-side transactional logic.
4. Add COD and Razorpay checkout with signature/webhook verification.
5. Add automated tests and verify production deployment.
