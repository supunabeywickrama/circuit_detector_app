# Premium UI/UX + Auth + Subscriptions + Cloud DB Overhaul

The goal is to transform the E-Component Detector from a basic functional app into a polished, professional-grade product with authentication, subscription tiers, and cloud-backed history.

## User Review Required

> [!IMPORTANT]
> **Database Choice:** The plan uses **Supabase** (hosted PostgreSQL) instead of raw self-managed PostgreSQL. Supabase provides a free tier, auto-generates REST APIs, has a built-in Flutter SDK, and includes pre-built auth (email, Google, Apple).
> This saves weeks of work vs. spinning up your own Postgres server, writing JWT auth, and building REST endpoints from scratch.
> If you specifically want self-managed PostgreSQL, let me know — but Supabase is the better fit for a mobile app.

> [!IMPORTANT]
> **Subscription Payments:** Real payment processing (Stripe/RevenueCat/Play Store billing) requires app store accounts, webhook servers, and significant infrastructure. For this phase, I'll build the **subscription UI, tier logic, and gating** with Supabase as the source of truth, but actual payment integrations will be mocked. You can plug in Stripe later.

## Proposed Changes

The work is split into 5 phases, each building on the previous.

---

### Phase 1 — Premium Design System & UI Assets

Generate custom premium backgrounds and establish a cohesive design language.

#### [NEW] `lib/theme/app_theme.dart`
- Premium dark & light `ThemeData` with curated HSL color palette
- Custom fonts (Google Fonts: Outfit for headings, Inter for body)
- Global design tokens: spacing, radii, gradients, shadows
- Glassmorphism card decorators

#### [NEW] `lib/theme/gradients.dart`
- Reusable gradient presets for buttons, backgrounds, cards
- Premium color constants (cyan-blue, deep violet, emerald, amber)

#### [MODIFY] `pubspec.yaml`
- Add `google_fonts`, `supabase_flutter`, `shared_preferences`, `flutter_svg`, `cached_network_image`
- Add new asset entries for generated backgrounds

#### [NEW] Generated background images (via image generation tool):
- `assets/images/login_bg.webp` — futuristic circuit board aesthetic
- `assets/images/home_bg_premium.webp` — dark gradient with circuit traces
- `assets/images/settings_bg.webp` — subtle dark texture
- `assets/images/subscription_bg.webp` — premium gold/dark gradient

---

### Phase 2 — Authentication (Login/Register)

#### [NEW] `lib/services/auth_service.dart`
- Supabase auth wrapper: `signUp()`, `signIn()`, `signOut()`, `getCurrentUser()`, `resetPassword()`
- Session persistence via Supabase SDK
- Auth state stream for reactive UI

#### [NEW] `lib/pages/login_page.dart`
- Premium login screen with:
  - Email + password fields with glassmorphism cards
  - "Remember me" toggle
  - "Forgot password" link
  - "Create Account" navigation
  - Animated circuit-themed background
  - Form validation with inline errors

#### [NEW] `lib/pages/register_page.dart`
- Registration form: name, email, password, confirm password
- Terms & conditions checkbox
- Auto-login on successful registration
- Same premium aesthetic as login

#### [NEW] `lib/pages/forgot_password_page.dart`
- Simple email input → sends reset link via Supabase

#### [MODIFY] `lib/main.dart`
- Initialize Supabase client on startup
- Auth gate: show `LoginPage` if not authenticated, `HomePage` if authenticated
- Multi-provider setup: `ThemeProvider`, auth state

---

### Phase 3 — Cloud History with Supabase/PostgreSQL

#### Backend changes:

#### [NEW] `backend/db.py`
- Supabase client initialization
- Functions: `save_detection()`, `get_history()`, `delete_detection()`, `get_user_stats()`
- `scans` table schema:
  ```sql
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  timestamp TIMESTAMPTZ DEFAULT NOW(),
  thumbnail_url TEXT,
  detections JSONB,
  component_counts JSONB,
  resistor_values TEXT[],
  ic_values TEXT[],
  total_components INTEGER,
  image_count INTEGER,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
  ```

#### [MODIFY] `backend/app.py`
- New endpoints:
  - `POST /api/history` — save scan with user_id (from JWT)
  - `GET /api/history` — fetch user's scans (paginated)
  - `DELETE /api/history/{id}` — delete a scan
  - `GET /api/user/stats` — total scans, components found, etc.
- JWT middleware to extract user_id from Supabase auth token

#### Flutter changes:

#### [NEW] `lib/services/cloud_history_service.dart`
- Upload scan results to Supabase
- Fetch cloud history with pagination
- Delete from cloud
- Sync local ↔ cloud

#### [MODIFY] `lib/pages/history_page.dart`
- Toggle: Local / Cloud history tabs
- Cloud entries show sync badge
- Pull-to-refresh for cloud data
- Premium card-based design (replace plain ListTile)

---

### Phase 4 — Subscription System

#### [NEW] Supabase table `subscriptions`:
```sql
id UUID PRIMARY KEY,
user_id UUID REFERENCES auth.users(id),
plan TEXT CHECK (plan IN ('free', 'monthly', 'yearly')),
status TEXT CHECK (status IN ('active', 'cancelled', 'expired')),
started_at TIMESTAMPTZ,
expires_at TIMESTAMPTZ,
created_at TIMESTAMPTZ DEFAULT NOW()
```

#### [NEW] `lib/pages/subscription_page.dart`
- Premium subscription screen with:
  - Three plan cards: Free / Monthly ($4.99) / Yearly ($39.99)
  - Feature comparison table
  - Animated "Most Popular" badge on yearly
  - Current plan indicator
  - Gradient CTA buttons

#### [NEW] `lib/services/subscription_service.dart`
- Check current plan from Supabase
- Feature gating:
  - **Free:** 5 scans/day, local history only, blur warning
  - **Monthly:** Unlimited scans, cloud history, GPT-4o OCR, export
  - **Yearly:** All Monthly features + priority support badge

#### [MODIFY] `lib/pages/home_page.dart`
- Show current plan badge in AppBar
- Gate features behind subscription check
- Premium visual upgrade

---

### Phase 5 — Premium Pages Overhaul

#### [MODIFY] `lib/pages/home_page.dart`
- Full redesign:
  - Animated gradient background
  - Glassmorphism action cards (not buttons)
  - User avatar + greeting in header
  - Quick stats row (total scans, components found)
  - Floating bottom nav hints
  - Subtle particle/circuit animation

#### [MODIFY] `lib/pages/camera_page.dart`
- Premium overlay: frosted glass control bar
- Animated capture button with ripple
- Shot counter with gradient pill
- Quality meter (live blur score)

#### [MODIFY] `lib/pages/results_page.dart`
- Card-based detection results (not plain text)
- Component icons per type
- Expandable cards with crop preview
- Gradient section headers
- Share button generates styled summary image

#### [MODIFY] `lib/pages/settings_page.dart`
- Full redesign removing max angles & aspect ratio
- Sections:
  - **Account:** Profile info, email, sign out
  - **Subscription:** Current plan + upgrade button
  - **Appearance:** Dark/light mode toggle
  - **Detection:** Blur warning toggle, confidence threshold slider
  - **Data:** Clear local history, export all data
  - **About:** App version, licenses, feedback link
- Each section in a premium glassmorphism card

## Open Questions

> [!IMPORTANT]
> 1. **Supabase vs Self-managed PostgreSQL:** Supabase gives you free hosted Postgres + auth + realtime + file storage. Do you approve using Supabase? Or do you want me to set up raw PostgreSQL that you'd need to host yourself?

> [!WARNING]
> 2. **Subscription Pricing:** I've used placeholder prices ($4.99/month, $39.99/year). Should I adjust these? What features exactly should be gated for free users?

> [!NOTE]
> 3. **Google/Apple Sign-In:** Do you want social auth (Google, Apple) in addition to email/password? This requires configuring OAuth credentials in Google Cloud Console / Apple Developer Portal.

## Verification Plan

### Automated Tests
- `flutter analyze` — zero lint errors
- Backend: `python -c "import app; print('OK')"` — loads cleanly
- Health check: `curl http://localhost:8000/health`

### Manual Verification
1. Run Flutter app → should show Login page first
2. Register a new account → auto-redirect to Home
3. Take a scan → verify results display with premium cards
4. Check History page → cloud sync indicator visible
5. Open Settings → verify all sections render correctly
6. Open Subscription page → verify plan cards display
7. Sign out → returns to Login page
8. Test dark mode toggle across all pages
