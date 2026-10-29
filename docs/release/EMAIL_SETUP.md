# Auth emails (sign-up code, password reset)

## Why sign-up email "doesn't work"

Supabase's **built-in** email sender is for testing only:

- It sends **only to email addresses of members of your Supabase organisation**.
- It sends only a few emails per hour.

Any other address simply never gets a mail. Real users need a custom SMTP
sender.

## Quick unblock for testing (pick one)

| Option | How |
|---|---|
| A. Turn off confirmation while testing | Authentication → Sign In / Providers → Email → **Confirm email: OFF**. Sign-up logs straight in. **Turn it back ON before launch.** |
| B. Create test users by hand | Authentication → Users → **Add user** → Create new user → tick **Auto Confirm User** |
| C. Use your own address | Sign up with the email that owns the Supabase organisation (built-in sender delivers to members) |

## Production: custom SMTP (needed before launch)

Use a transactional email service and send from your own domain,
e.g. `no-reply@hux.co.in`.

| Service | Free tier (check current pricing) | Notes |
|---|---|---|
| **Resend** | ~3,000/month | Easiest setup; guide exists for Supabase |
| **Brevo** | ~300/day | Good free tier |
| **Zoho ZeptoMail** | Pay-as-you-go, cheap | India-based; good if you use Zoho Mail |
| **Amazon SES** | Very cheap | Most setup work; needs production access request |

**Steps (example: Resend):**

1. Sign up, then **Domains → Add domain**: `hux.co.in` (or a subdomain such
   as `mail.hux.co.in`).
2. At your domain registrar's DNS, add the records it shows: **SPF**
   (TXT), **DKIM** (TXT/CNAME) and, recommended, **DMARC**:
   `_dmarc` TXT `v=DMARC1; p=none; rua=mailto:privacy@hux.co.in`.
   Wait until the domain shows **Verified**.
3. Create an **API key** (it is the SMTP password).
4. Supabase → **Authentication → Emails → SMTP Settings → Enable custom SMTP**:

   | Field | Value |
   |---|---|
   | Sender email | `no-reply@hux.co.in` |
   | Sender name | `HUX` |
   | Host | `smtp.resend.com` |
   | Port | `465` |
   | Username | `resend` |
   | Password | the API key |
   | Minimum interval | 60 s |

5. Supabase → **Authentication → Rate Limits**: raise "emails per hour"
   (e.g. 100) now that your own SMTP is set.
6. Keep the SMTP password only in the Supabase dashboard (never in the repo).

## Email templates (Authentication → Emails → Templates)

HUX uses **codes, not links**. A link in an email opens a browser, not the
app.

**Confirm signup**

- Subject: `Your HUX code: {{ .Token }}`
- Body:

```html
<h2>Welcome to HUX</h2>
<p>Your confirmation code is:</p>
<p style="font-size:28px;letter-spacing:6px"><strong>{{ .Token }}</strong></p>
<p>Enter it in the app. It expires in 15 minutes.</p>
<p>If you didn't sign up for HUX, you can ignore this email.</p>
```

**Reset password**

- Subject: `Your HUX password reset code: {{ .Token }}`
- Body: same as above, with "reset your password" instead of "confirm".

**Settings**

| Setting | Value | Why |
|---|---|---|
| Authentication → Sign In / Providers → Email → **Email OTP Expiration** | `900` (15 min) | Matches the app's countdown (`verify_code_screen.dart`) |
| **Email OTP Length** | `6` | The app accepts 6–10 digits |
| **Confirm email** | ON for launch | |

## Check it works

1. Sign up in the app with a fresh address (not a team member).
2. The "Confirm your email" screen should open.
3. The code should arrive within about 1 minute (check spam the first time).
4. Enter it: you're signed in and see the privacy notice.
5. Supabase → Authentication → **Logs** shows SMTP errors if mail fails.
