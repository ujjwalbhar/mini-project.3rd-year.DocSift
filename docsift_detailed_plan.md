# 🗂️ DocSift — Detailed Development Plan

> **Stack:** Flutter 3.x · Riverpod · SQLCipher · PointyCastle · ONNX Runtime · Tesseract OCR

---

## 📁 Target Project Structure

```
docsift/
├── lib/
│   ├── main.dart
│   ├── app.dart                          # MaterialApp + GoRouter root
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_text_styles.dart
│   │   │   └── app_strings.dart
│   │   ├── theme/
│   │   │   ├── app_theme.dart            # Light + Dark ThemeData
│   │   │   └── theme_provider.dart       # Riverpod theme notifier
│   │   ├── router/
│   │   │   └── app_router.dart           # go_router route definitions
│   │   └── utils/
│   │       ├── file_utils.dart
│   │       └── date_utils.dart
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   └── auth_repository.dart  # Argon2id hashing, PIN verify
│   │   │   ├── domain/
│   │   │   │   └── auth_service.dart
│   │   │   └── presentation/
│   │   │       ├── pin_setup_screen.dart
│   │   │       └── pin_lock_screen.dart
│   │   ├── vault/
│   │   │   ├── data/
│   │   │   │   ├── vault_repository.dart # PointyCastle encrypt/decrypt
│   │   │   │   └── key_manager.dart      # flutter_secure_storage VEK
│   │   │   ├── domain/
│   │   │   │   ├── models/
│   │   │   │   │   ├── vault_item.dart
│   │   │   │   │   └── vault_category.dart
│   │   │   │   └── vault_service.dart
│   │   │   └── presentation/
│   │   │       ├── dashboard_screen.dart
│   │   │       ├── categories_screen.dart
│   │   │       ├── document_viewer_screen.dart
│   │   │       └── widgets/
│   │   │           ├── vault_item_card.dart
│   │   │           └── category_chip.dart
│   │   ├── ocr/
│   │   │   ├── data/
│   │   │   │   └── ocr_repository.dart   # Tesseract isolate runner
│   │   │   └── domain/
│   │   │       └── ocr_service.dart
│   │   ├── search/
│   │   │   ├── data/
│   │   │   │   └── search_repository.dart # FTS5 BM25 queries
│   │   │   └── presentation/
│   │   │       └── search_screen.dart
│   │   └── ai/
│   │       ├── data/
│   │       │   ├── embedding_repository.dart  # MiniLM ONNX
│   │       │   └── qa_repository.dart         # DistilBERT ONNX
│   │       ├── domain/
│   │       │   └── rag_service.dart
│   │       └── presentation/
│   │           └── qa_screen.dart
│   └── shared/
│       ├── widgets/
│       │   ├── app_button.dart
│       │   ├── app_text_field.dart
│       │   ├── loading_overlay.dart
│       │   └── empty_state_widget.dart
│       └── providers/
│           └── database_provider.dart    # SQLCipher db singleton
├── assets/
│   ├── models/
│   │   ├── minilm.onnx
│   │   └── distilbert_squad2.onnx
│   ├── tessdata/
│   │   └── eng.traineddata
│   └── icons/
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml           # FLAG_SECURE config
├── ios/
│   └── Runner/
│       └── Info.plist
└── pubspec.yaml
```

---

## 📦 pubspec.yaml — All Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Navigation
  go_router: ^13.0.0

  # State Management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0

  # Database
  sqflite_sqlcipher: ^2.2.0       # SQLCipher wrapper
  path_provider: ^2.1.0
  path: ^1.9.0

  # Encryption
  pointycastle: ^3.7.4             # AES-256-GCM file encryption
  flutter_secure_storage: ^9.0.0   # VEK storage (Keystore/Enclave)
  argon2_flutter: ^1.0.0           # PIN hashing

  # File Handling
  file_picker: ^8.0.0
  open_filex: ^4.4.0
  permission_handler: ^11.3.0
  share_plus: ^9.0.0

  # Parsers & OCR
  flutter_tesseract_ocr: ^0.4.12
  syncfusion_flutter_pdf: ^24.1.0  # PDF text extraction
  archive: ^3.4.0                  # ZIP extraction for DOCX

  # AI / ONNX
  onnxruntime: ^1.18.0             # onnxruntime_flutter

  # UI & UX
  google_fonts: ^6.2.0
  flutter_animate: ^4.5.0
  lottie: ^3.1.0
  cached_network_image: ^3.3.0    # only for avatars/icons

  # Utilities
  uuid: ^4.4.0
  intl: ^0.19.0
  logger: ^2.3.0
  freezed_annotation: ^2.4.0

dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.4.0
  riverpod_generator: ^2.3.0
  flutter_lints: ^4.0.0
```

---

## 🚀 Phase 1 — Scaffolding & UI Prototyping

**Goal:** Working shell app with navigation, design system, and all core screens (no real data yet).

### Tasks

#### 1.1 Project Initialization
- [ ] Run `flutter create docsift --org=com.yourdomain`
- [ ] Set minimum SDK: Android API 26+, iOS 15+
- [ ] Add all `pubspec.yaml` dependencies
- [ ] Configure `flutter_lints` and analysis_options.yaml

#### 1.2 Design System
- [ ] Define color palette in `app_colors.dart`
  - Primary: Deep indigo/violet (privacy/trust feel)
  - Surface: Glassmorphism-ready dark grays
  - Accent: Teal/cyan for AI features
- [ ] Build `AppTheme` with Light + Dark `ThemeData`
- [ ] Set up Google Fonts (e.g., `Inter` or `DM Sans`)
- [ ] Create `ThemeProvider` Riverpod notifier + persistence

#### 1.3 Routing (go_router)
- [ ] Define all named routes:
  - `/` → Splash/Lock check
  - `/setup-pin` → First-time PIN setup
  - `/lock` → PIN entry screen
  - `/dashboard` → Main vault view
  - `/category/:id` → Documents in category
  - `/viewer/:fileId` → Decrypted document viewer
  - `/search` → Search screen
  - `/ask` → AI Q&A screen
  - `/settings` → Settings

#### 1.4 Core Screens (UI Only)
- [ ] **Splash Screen** — animated logo, checks auth state
- [ ] **PIN Setup Screen** — 6-dot PIN input with confirmation
- [ ] **PIN Lock Screen** — same 6-dot input + biometric button
- [ ] **Dashboard Screen** — category grid + recent files + FAB to add
- [ ] **Categories Screen** — filterable grid of document categories
- [ ] **Document Viewer** — placeholder with file metadata
- [ ] **Search Screen** — search bar + result list skeleton
- [ ] **AI Q&A Screen** — chat-style UI with query input

#### 1.5 Shared Widgets
- [ ] `AppButton` — primary, secondary, danger variants
- [ ] `AppTextField` — styled input with validation
- [ ] `PinInputWidget` — 6-dot animated PIN input
- [ ] `VaultItemCard` — document card with icon, name, size, date
- [ ] `CategoryCard` — icon + name + count badge
- [ ] `LoadingOverlay` — blur overlay with spinner
- [ ] `EmptyStateWidget` — illustration + CTA

#### 1.6 Android Hardening (Early)
- [ ] Add `FLAG_SECURE` in `MainActivity.kt` to block screenshots
- [ ] Set `android:excludeFromRecents="true"` in manifest

---

## 🔐 Phase 2 — Vault Architecture & Database

**Goal:** Full encryption pipeline working. Users can import, encrypt, store, and retrieve files.

### Tasks

#### 2.1 SQLCipher Database Setup
- [ ] Create `DatabaseProvider` Riverpod provider (singleton)
- [ ] On first launch, generate random 32-byte DB encryption key
- [ ] Store DB key in `flutter_secure_storage`
- [ ] Define schema:

```sql
-- vault_items table
CREATE TABLE vault_items (
  id TEXT PRIMARY KEY,             -- UUID
  name TEXT NOT NULL,
  original_extension TEXT NOT NULL,
  category_id TEXT,
  encrypted_file_path TEXT NOT NULL,
  file_size_bytes INTEGER,
  mime_type TEXT,
  thumbnail_path TEXT,
  created_at INTEGER NOT NULL,
  modified_at INTEGER NOT NULL,
  is_starred INTEGER DEFAULT 0,
  tags TEXT                         -- JSON array of tag strings
);

-- categories table
CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon_codepoint INTEGER,
  color_value INTEGER,
  created_at INTEGER NOT NULL
);

-- text_chunks table (for FTS/AI)
CREATE TABLE text_chunks (
  id TEXT PRIMARY KEY,
  vault_item_id TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  content TEXT NOT NULL,
  embedding BLOB,                   -- stored float32 array
  FOREIGN KEY (vault_item_id) REFERENCES vault_items(id) ON DELETE CASCADE
);

-- FTS5 virtual table
CREATE VIRTUAL TABLE chunks_fts USING fts5(
  content,
  content='text_chunks',
  content_rowid='rowid'
);
```

#### 2.2 Authentication (Argon2id PIN)
- [ ] `PinSetupScreen` → hash PIN with Argon2id (time=3, mem=64MB, parallelism=1)
- [ ] Store hash in `flutter_secure_storage` (NOT in DB)
- [ ] `PinLockScreen` → re-hash input and compare
- [ ] Generate VEK (32 random bytes) on first setup, store in Keystore
- [ ] Implement biometric unlock as fallback (local_auth package)
- [ ] Auto-lock after 3 failed attempts (wipe in-memory VEK)

#### 2.3 File Encryption (PointyCastle AES-256-GCM)
- [ ] Build `VaultRepository` with:
  - `Future<String> encryptAndStore(File sourceFile)` — returns encrypted file path
  - `Future<Uint8List> decryptToMemory(String encryptedPath)` — returns bytes
  - `Future<void> deleteVaultItem(String encryptedPath)`
- [ ] Encryption format:
  ```
  [4 bytes: IV length][12 bytes: IV][16 bytes: GCM Tag][N bytes: ciphertext]
  ```
- [ ] Encrypted files stored in app's private directory (`getApplicationDocumentsDirectory`)
- [ ] Implement `KeyManager` — loads VEK from secure storage, holds in-memory only while unlocked
- [ ] Memory wipe: override VEK bytes on lock

#### 2.4 File Import Flow
- [ ] FAB on Dashboard triggers `FilePicker.platform.pickFiles()`
- [ ] Show category selector bottom sheet
- [ ] Background `Isolate` encrypts file → saves to vault → inserts DB record
- [ ] Show progress indicator during encryption
- [ ] Support: PDF, DOCX, MD, TXT, JPG, PNG, MP4, ZIP

#### 2.5 File Viewing Flow
- [ ] On tap: decrypt to memory (Uint8List) → display using appropriate viewer
  - PDF → `syncfusion_flutter_pdf` viewer
  - Images → Flutter `Image.memory()`
  - Text → `SelectableText` widget
  - MP4/ZIP → Show metadata only + share option
- [ ] On close: explicit memory wipe of decrypted bytes

---

## 📝 Phase 3 — Data Parsing & OCR Integration

**Goal:** After import, silently extract text from all supported formats via background isolates.

### Tasks

#### 3.1 Isolate Architecture
- [ ] Create `IsolateRunner` utility that:
  - Spins up a new `Isolate` for each heavy task
  - Communicates via `SendPort/ReceivePort`
  - Reports progress updates back to UI stream
- [ ] Text extraction never runs on the main thread

#### 3.2 PDF Text Extraction
- [ ] Use `syncfusion_flutter_pdf` in isolate
- [ ] Extract text page by page
- [ ] Chunk by ~500 tokens (sentence-boundary aware)
- [ ] Insert chunks into `text_chunks` table

#### 3.3 DOCX Text Extraction
- [ ] DOCX is a ZIP file — use `archive` package to extract `word/document.xml`
- [ ] Parse XML with `xml` package to extract raw `<w:t>` text nodes
- [ ] Same chunking and DB insertion

#### 3.4 Markdown / TXT
- [ ] Direct string read after decryption
- [ ] Split by paragraph/heading for chunking

#### 3.5 Image OCR (Tesseract)
- [ ] `flutter_tesseract_ocr` runs in isolate
- [ ] Bundle `eng.traineddata` in `assets/tessdata/`
- [ ] Extract text → chunk → insert to DB
- [ ] For encrypted images: decrypt to temp memory, pass bytes to Tesseract, wipe after

#### 3.6 Extraction Status
- [ ] Add `extraction_status` column to `vault_items`: `pending | processing | done | failed`
- [ ] Show processing indicator on `VaultItemCard` while extraction is running
- [ ] Background queue: process up to 2 files in parallel

---

## 🤖 Phase 4 — AI Integration & Search

**Goal:** BM25 keyword search + full offline semantic Q&A pipeline operational.

### Tasks

#### 4.1 BM25 Keyword Search (SQLite FTS5)
- [ ] Use FTS5 virtual table `chunks_fts` (set up in Phase 2)
- [ ] Keep FTS table in sync with `text_chunks` via triggers
- [ ] `SearchRepository.search(query)`:
  ```sql
  SELECT tc.vault_item_id, tc.content, bm25(chunks_fts) AS score
  FROM chunks_fts
  JOIN text_chunks tc ON chunks_fts.rowid = tc.rowid
  WHERE chunks_fts MATCH ?
  ORDER BY score LIMIT 20;
  ```
- [ ] Build `SearchScreen` — real-time results as user types (debounced 300ms)
- [ ] Result cards: file name, matched chunk preview, BM25 score bar

#### 4.2 ONNX Model Integration
- [ ] Bundle models in `assets/models/`
  - `minilm-l6-v2-quant.onnx` (~23MB) — embeddings
  - `distilbert-base-cased-distilled-squad-quant.onnx` (~85MB) — Q&A
- [ ] Load models once at app start in background using `onnxruntime` package
- [ ] Create `ModelManager` provider — lazy loads, holds `OrtSession` references

#### 4.3 Embedding Generation (MiniLM)
- [ ] After text extraction, run `EmbeddingRepository.generateEmbedding(chunkText)`
- [ ] Tokenize input (max 256 tokens with padding/truncation)
- [ ] Run ONNX inference → get 384-dim float32 embedding
- [ ] Store as `BLOB` in `text_chunks.embedding` column

#### 4.4 Vector Similarity Search
- [ ] Since SQLite has no native vector search, implement in Dart:
  ```dart
  double cosineSimilarity(List<double> a, List<double> b) { ... }
  ```
- [ ] Load all embeddings from DB into memory on search (limit to top-1000 chunks by FTS pre-filter)
- [ ] Rank by cosine similarity → return top-5 chunks as context

#### 4.5 Q&A Inference (DistilBERT SQuAD2)
- [ ] `QaRepository.answer(question, context)`:
  - Concatenate `[CLS] question [SEP] context [SEP]`
  - Tokenize (max 512 tokens)
  - Run ONNX inference → get start/end logits
  - Extract answer span from tokens
  - Return answer string + confidence score
- [ ] **AI Q&A Screen** UI:
  - Chat bubble input at bottom
  - Answer appears with source document card
  - "No answer found" graceful fallback
  - Show which document the answer came from

#### 4.6 Hybrid RAG Pipeline (Orchestration)
- [ ] `RagService.query(userQuestion)`:
  1. Run FTS5 BM25 search → top 10 chunks
  2. Re-rank by cosine similarity → top 3 chunks
  3. Concatenate top 3 as context
  4. Run DistilBERT inference
  5. Return `RagResult(answer, sourceChunks, confidence)`

---

## 🧪 Phase 5 — Testing, Security Audits & Deployment

**Goal:** Production-ready, secure, performant application.

### Tasks

#### 5.1 Unit Tests
- [ ] `auth_repository_test.dart` — Argon2id hash/verify round-trip
- [ ] `vault_repository_test.dart` — encrypt → decrypt byte equality
- [ ] `ocr_service_test.dart` — mock Tesseract, verify chunk insertion
- [ ] `search_repository_test.dart` — FTS5 query returns expected results
- [ ] `rag_service_test.dart` — mock ONNX, verify pipeline orchestration

#### 5.2 Widget Tests
- [ ] `pin_input_widget_test.dart` — correct/incorrect PIN UI state
- [ ] `vault_item_card_test.dart` — renders name, size, category
- [ ] `search_screen_test.dart` — debounce behavior, result display

#### 5.3 Integration Tests
- [ ] Full import → encrypt → OCR → search flow
- [ ] Full import → encrypt → embed → Q&A flow
- [ ] Lock → unlock → verify files still accessible

#### 5.4 Security Audit
- [ ] **Verify no plaintext files** in app storage directory after import
- [ ] **Memory wipe verification** — use Flutter DevTools memory profiler
- [ ] **Screenshot blocking** — verify `FLAG_SECURE` on Android
- [ ] **Keystore check** — confirm VEK never stored in SharedPreferences
- [ ] **Brute force protection** — test 3-attempt lockout

#### 5.5 Performance Benchmarks
- [ ] Encryption time for files: 1MB, 10MB, 50MB, 100MB
- [ ] OCR time for dense-text image
- [ ] ONNX embedding generation time per chunk
- [ ] Q&A inference latency (target < 3 seconds on mid-range device)
- [ ] FTS5 search latency with 10,000+ chunks

#### 5.6 Deployment Prep
- [ ] Set `debuggable=false` in release build config
- [ ] Enable R8/ProGuard code shrinking on Android
- [ ] iOS App Transport Security — confirm all NSAllowsArbitraryLoads are false
- [ ] Generate release keystore and sign APK/AAB
- [ ] Final `flutter build appbundle --release` and `flutter build ipa --release`
- [ ] Write final README with architecture diagram

---

## 🗓️ Estimated Timeline

| Phase | Estimated Duration | Complexity |
|:---|:---:|:---:|
| Phase 1 — Scaffolding & UI | 1–2 weeks | 🟡 Medium |
| Phase 2 — Vault & Database | 2–3 weeks | 🔴 High |
| Phase 3 — Parsing & OCR | 1–2 weeks | 🟡 Medium |
| Phase 4 — AI & Search | 2–3 weeks | 🔴 High |
| Phase 5 — Testing & Deployment | 1–2 weeks | 🟡 Medium |
| **Total** | **7–12 weeks** | |

---

## ⚡ Phase Execution Order

```
Phase 1 (UI Shell)
    │
    └──► Phase 2 (Encryption Core)   ← Critical path
              │
              └──► Phase 3 (Parsing)
                        │
                        └──► Phase 4 (AI/Search)
                                  │
                                  └──► Phase 5 (QA + Deploy)
```

> **Recommended starting point:** Begin with Phase 1 to get the UI shell working, then immediately move to Phase 2 since the encryption core is the riskiest and most foundational component.

---

## 🚦 Key Risks & Mitigations

| Risk | Mitigation |
|:---|:---|
| ONNX models too slow on low-end devices | Use quantized INT8 models; benchmark early in Phase 4 |
| `flutter_tesseract_ocr` flaky on some Android versions | Isolate in background; fallback to "text extraction failed" gracefully |
| SQLCipher migration complexity | Use `sqflite_sqlcipher` fork which wraps it cleanly |
| Memory pressure with 250MB AI model | Lazy-load model only when Q&A screen is opened; dispose on close |
| Argon2id parameters too slow/fast | Benchmark on target device; adjust `timeCost` accordingly |
