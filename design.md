# DocSift — UI/UX Design Specification Document (design.md)

## 1. Design Philosophy & Vision

DocSift is an offline-first, zero-trust personal knowledge repository and encrypted vault application. The design language is built on four core principles:

- **Glanceable Security:** High-contrast visual cues (shield glyphs, lock badges, verified pills) continuously reinforce the vault's state of encryption and protection.
- **Zero-Trust UI Architecture:** Sensitive data is never displayed unmasked by default, screens block background recording/screenshots, and decrypted memory is cleared upon navigation.
- **Frictionless Navigation:** A tactile 6-digit numeric keypad, instant biometric fallbacks, and a balanced 6-category layout deliver sub-two-second access to stored files.
- **Conversational Retrieval:** A dedicated on-device AI assistant enables natural language querying directly against stored documents with verified source attribution.

---

## 2. Design Tokens & Foundations

### 2.1 Color Palette

| Design Token | Hex Code | Visual Application / Semantics |
|---|---|---|
| Primary Navy (`$color-primary`) | `#2B3C5A` | App bars, lock screen backdrop, primary headings, active bottom navigation. |
| Accent Emerald (`$color-accent`) | `#27AE60` | Primary CTAs, active PIN indicators, FAB, chat user bubbles, verified badges. |
| Surface Neutral (`$color-surface`) | `#F0F3F2` | Global background canvas, search bar fill, secondary container borders. |
| Card Canvas (`$color-card`) | `#FFFFFF` | Item list containers, category grid cards, elevated detail surfaces. |
| Peach Accent (`$color-peach`) | `#FF58FA / #FF8A8A` | Category icon backdrop for Documents and Media. |
| Destructive Red (`$color-danger`) | `#FF6B6B` | Delete actions, destructive modals, validation error outlines. |
| Text Primary (`$color-text-main`) | `#1A202C` | High-contrast body text, primary item titles. |
| Text Secondary (`$color-text-muted`) | `#718096` | Metadata (timestamps, file sizes, categories), input placeholders. |

### 2.2 Typography

| Hierarchy Level | Style & Weight | Size | Line Height | Usage Context |
|---|---|---|---|---|
| Display H1 | Inter SemiBold (600) | 28px | 34px | Splash screen brand title, onboarding greetings. |
| Heading H2 | Inter SemiBold (600) | 20px | 26px | App bar titles, lock screen status, section headers. |
| Heading H3 | Inter SemiBold (600) | 16px | 22px | Category card headers, item titles, modal headings. |
| Body Regular | Inter Regular (400) | 14px | 20px | Credential labels, search input, AI chat messages. |
| Caption / Meta | Inter Medium (500) | 12px | 16px | File size tags, timestamps, secondary badges. |
| Keypad Numeral | Inter Regular (400) | 24px | 28px | Numeric PIN matrix digits. |

### 2.3 Iconography & Layout Spacing

- **Icon Style:** Monoline outline icons (24×24dp bounding box, 2dp uniform stroke width) featuring rounded stroke terminals (`StrokeCap.round`).
- **Spatial Grid:** 8-point base grid system (8px, 16px, 24px, 32px).
- **Border Radii:**
  - Cards and Category Containers: `16px`
  - Text Fields & Search Bars: `12px`
  - Primary Action Buttons & Pills: `24px` (fully rounded)
  - Keypad Buttons: `12px` to `16px` rounded rects
- **Elevation & Shadows:**
  - Default Card: `box-shadow: 0px 4px 12px rgba(43, 60, 90, 0.05);`
  - Floating Action Button (FAB): `box-shadow: 0px 8px 16px rgba(39, 174, 96, 0.25);`

---

## 3. Information Architecture & Navigation Flow

```
DocSift Root Controller
 ├── 1. Onboarding & Authentication Flow
 │    ├── Screen 1: Splash Screen
 │    ├── Screen 2: Onboarding Intro
 │    ├── Screen 3: Create PIN
 │    ├── Screen 4: Confirm PIN
 │    └── Screen 5: Vault Lock Screen (PIN / Biometrics)
 └── 2. Authenticated Vault Application (Bottom Navigation Controller)
      ├── [Tab 1] Vault Dashboard (Screen 6)
      │    ├── Search Engine Integration
      │    ├── Category Sub-Views:
      │    │    ├── Screen 7: Passwords Category
      │    │    ├── Screen 8: Documents Category
      │    │    └── Screen 9: Identity Category
      │    ├── Screen 10: Item Detail View (Masked Credentials & File Preview)
      │    ├── Screen 11: Add Item Picker (Bottom Sheet Modal)
      │    └── Screen 12: Add Password / Add Record Entry Form
      ├── [Tab 2] On-Device AI Assistant (Screen 13: DocSift AI Chat)
      └── [Tab 3] Vault Settings & Hardening (Screen 14)
```

---

## 4. Comprehensive Screen-by-Screen Specifications

### 4.1 Onboarding & Authentication Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  1. Splash   │ ──> │ 2. Onboarding│ ──> │3. Create PIN │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                 │
┌──────────────┐     ┌──────────────┐            │
│5. Lock Screen│ <── │4. Confirm PIN│ <──────────┘
└──────────────┘     └──────────────┘
```

**Screen 1: Splash Screen**
- **Header / Branding:** Centered emerald green rounded shield icon housing a checkmark glyph (`#27AE60`).
- **Typography:** Display title "DocSift" (H1, 28px, White), followed by subtitle: "Your secure vault. Always with you."
- **Background:** Solid Primary Navy (`#2B3C5A`).
- **System Logic:** Checks hardware keystore via `flutter_secure_storage`. If a Master Vault Key exists, transitions directly to Screen 5 (Lock Screen); if uninitialized, routes to Screen 2 (Onboarding).

**Screen 2: Onboarding Walkthrough**
- **Visual Artwork:** Centered illustration of two users collaborating in front of a vault safe door.
- **Copy:** Title "Welcome to DocSift", body: "Your safe place to store your passwords, documents, IDs, cards and more."
- **Actions:**
  - Primary Button: Full-width Emerald pill button labeled "Next" (`#27AE60`).
  - Secondary Text Button: Centered text link "Skip" (`#718096`).

**Screen 3 & 4: Create & Confirm 6-Digit PIN**
- **Header:** "Create your PIN" (Screen 3) / "Confirm your PIN" (Screen 4).
- **Instructional Subtext:** "Choose a 6-digit PIN to secure your vault" / "Re-enter your 6-digit PIN".
- **PIN Input Indicators:** 6 horizontal circular dot nodes spaced by 12px.
  - Unfilled: 12px diameter circle with light slate border (`#CBD5E0`).
  - Filled: 12px solid Emerald disc (`#27AE60`).
- **Numeric Keypad:** Custom 3×4 matrix (1–9, empty space, 0, backspace icon).
- **Execution Logic:** On 6th digit of Confirmation, computes Argon2id hash with hardware salt, securely stores credential, and unlocks the database session.

**Screen 5: Vault Lock Screen**
- **Visual Atmosphere:** Immersive deep navy canvas (`#2B3C5A`) with dark elevated keypad buttons (`#384D70`).
- **Status Badging:** Centered shield lock icon, title "DocSift Locked", subtext "Enter your PIN to continue".
- **Keypad Customization:** Bottom-left key displays the hardware Biometric glyph (FaceID/Fingerprint) for instant biometric unlock.
- **Rate Limiting:** Disables keypad inputs for 30 seconds after 5 consecutive incorrect attempts.

### 4.2 Vault Dashboard & Category Hub

**Screen 6: Dashboard (Vault Home)**
- **App Bar:**
  - Greeting title: "Good morning, User!" (H2, `#2B3C5A`).
  - Trailing verification icon: Green shield badge confirming vault encrypted state.
- **Search Engine Input:** Full-width rounded field (`#FFFFFF` background, `#F0F3F2` border) with prefix search icon and placeholder "Search anything...".
- **Category Grid (2 Columns × 3 Rows):**
  - Passwords: Navy/Blue Key icon, label "Passwords", item counter badge (e.g., 12 items).
  - Identity: Emerald ID card icon, label "Identity", item counter badge (e.g., 5 items).
  - Cards: Amber Credit Card icon, label "Cards", item counter badge (e.g., 4 items).
  - Notes: Orange Sticky Note icon, label "Notes", item counter badge (e.g., 18 items).
  - Documents: Pink Document icon, label "Documents", item counter badge (e.g., 15 items).
  - Media: Purple Media icon, label "Media", item counter badge (e.g., 8 items).
- **Recently Accessed Section:**
  - Section Header: "Recently Accessed" (H3 SemiBold).
  - List items displaying file type thumbnail, credential name, access timestamp, and chevron navigation arrow.
- **Global Navigation:**
  - Floating Action Button (FAB): Bottom-right emerald circular button (`#27AE60`) with + icon.
  - Bottom Navigation Bar: 3 destinations: Vault (Home), DocSift AI (Chat), Settings (Gear).

### 4.3 Category Browsing Screens

**Screen 7: Passwords Category Screen**
- Top Navigation: Leading back chevron, title "Passwords", trailing search trigger.
- Record List: Card rows for third-party services (Google, Instagram, Facebook, etc.)
  - Leading Service Brand Avatar
  - Content: Service Title and masked Username
  - Trailing: Security verified check badge and 3-dot context menu

**Screen 8: Documents Category Screen**
- Document Cards: File format badge (PDF, DOCX, XLSX, TXT), filename, file size, last modified date.

**Screen 9: Identity Category Screen**
- Identity Records: Green identity badge, credential classification, masked registration number.

### 4.4 Item Detail & Creation Flows

**Screen 10: Item Detail View**
- App Bar: Back arrow, document title, Edit / Share / Delete trailing actions.
- Metadata List: Full Name, Identity Number (masked with reveal toggle), DOB, Address, Notes.

**Screen 11: Add Item Picker (Modal Bottom Sheet)**
- Categories: Password, Identity, Card, Document, Note, Media.

**Screen 12: Add Password Screen**
- Form: Service Title, Email/Username, Password (obscured + toggle), Website URL, Notes.
- Submit: Full-width Emerald pill "Save" button.

### 4.5 Intelligence & System Administration

**Screen 13: Local AI Assistant (DocSift AI)**
- App Bar: Robot/shield avatar, title "DocSift AI", status pill "Your secure assistant".
- User Bubbles: Right-aligned emerald (`#27AE60`) with white text.
- AI Bubbles: Left-aligned white elevated container with source file citation.
- Query Bar: Bottom pill input with mic icon and circular send trigger.

**Screen 14: Settings Screen**
- Profile Header: Local avatar, username, local identifier badge.
- Settings Groups: Security, Vault Settings, Categories, AI Settings, Appearance, About.
- Footer: Emerald pill "Log Out / Lock Vault" button.

---

## 5. Security & UI Hardening Specifications

```
                      App Backgrounded / Minimized
                                 │
                                 ▼
               ┌───────────────────────────────────┐
               │     AppLifecycleState.paused       │
               └─────────────────┬─────────────────┘
                                 │
                ┌────────────────┴────────────────┐
                ▼                                 ▼
    [Window Canvas Layer]               [Process RAM Buffers]
                │                                 │
                ▼                                 ▼
      Apply FLAG_SECURE:                 Zero-Fill Plaintext:
   • Prohibit screenshots              • Overwrite PIN buffers
   • Obscure Task Switcher             • Clear decrypted files
   • Block screen recording            • Clear system clipboard
```

- **System Window Obscuring:** `FLAG_SECURE` on Android, canvas obscuring on iOS across all authenticated screens.
- **Volatile Memory Sanitization:** Decrypted data zero-filled on navigation away.
- **Sensitive Identifier Masking:** All identity numbers render masked by default.
- **Auto-Lock Lifecycle:** `AppLifecycleState.inactive/paused` → pop to Lock Screen.

---

## 6. Frontend Implementation Checklist (Flutter)

- [ ] Initialize theme: `#2B3C5A` (Primary) and `#27AE60` (Accent) with Inter typography.
- [ ] Implement go_router: `/splash`, `/onboarding`, `/create-pin`, `/confirm-pin`, `/lock`, `/dashboard`, `/category/:id`, `/item/:id`, `/add`, `/ai-chat`, `/settings`.
- [ ] Construct custom numeric keypad widget with biometric authentication integration.
- [ ] Build Dashboard category grid with dynamic item count badges from SQLCipher queries.
- [ ] Integrate `flutter_windowmanager` to enable `FLAG_SECURE` across all authenticated views.
- [ ] Connect on-device AI chat interface to local ONNX inference pipeline.
