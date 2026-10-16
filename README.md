# 🗂️ DocSift

**DocSift** is an offline-first, zero-trust personal knowledge repository and encrypted vault application. It is designed to safely store, manage, and interact with your most sensitive documents without compromising privacy.

Everything stays on-device. No telemetry, no cloud backups, no telemetry pings.

## ✨ Core Features
- **Zero-Trust Encryption:** All imported files are immediately encrypted using AES-256-GCM. 
- **Offline-First RAG Pipeline:** Fully integrated ONNX runtime for local Natural Language Q&A against your stored documents.
- **Glanceable Security:** High-contrast visual cues reinforce the vault’s state of encryption.
- **Background Text Extraction:** PDFs, DOCX files, Markdown, and Images (OCR) are seamlessly parsed in background isolates.
- **Sub-two-second Search:** Leveraging SQLite FTS5 (Full Text Search) for blazing-fast keyword retrieval across thousands of chunks.
- **Screen Privacy:** Hardened Android activities (`FLAG_SECURE`, `excludeFromRecents`) to block screenshots, screen recording, and app switcher peeking.

## 🏗️ Architecture

```mermaid
graph TD
    A[User UI] -->|Import File| B(VaultService)
    B -->|Encrypt (PointyCastle)| C[(Local Storage)]
    B -->|File Metadata| D[(SQLCipher DB)]
    B -->|Push to Queue| E[ExtractionQueue]
    
    E -->|Background Isolate| F[IsolateRunner]
    F -->|OCR/PDF/DOCX Extractor| G(Chunk Text)
    G -->|Generate Vector| H[EmbeddingRepository (ONNX MiniLM)]
    H -->|Save Chunks| D
    
    A -->|Search Query| I[SearchRepository (FTS5)]
    I -->|Rank Top Contexts| D
    
    A -->|Ask AI| J[RagService]
    J -->|Search BM25| I
    J -->|Cosine Similarity| H
    J -->|Generate Answer| K[QaRepository (ONNX DistilBERT)]
    K --> A
```

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.x
- ONNX Models: Download and place `minilm.onnx` and `distilbert_squad2.onnx` inside `assets/models/`. (Note: The app will run without them and fallback to simulated inference for development).
- Android SDK / Xcode for iOS build.

### Building the app
1. Clone the repository.
2. Run `flutter pub get`.
3. To test in debug mode: `flutter run`.
4. To build for production (with R8 code shrinking enabled): `flutter build apk --release` or `flutter build ipa --release`.

## 🔒 Security Posture
- **VEK (Vault Encryption Key):** Stored securely inside `flutter_secure_storage` (Keystore on Android, Keychain on iOS).
- **Database:** Encrypted using SQLCipher (ChaCha20 / AES).
- **Memory Wiping:** In-memory decrypted file buffers are explicitly zeroed out when the user locks the vault or navigates away from the viewer.

## 📜 License
MIT License
