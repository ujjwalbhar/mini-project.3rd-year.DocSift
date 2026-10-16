# Project Synopsis & Master Plan: DocSift
**A Secure, Offline-First Personal Knowledge Vault with Local AI**

---

## 1. Abstract
In an increasingly digitized world, students and professionals accumulate vast amounts of sensitive information across varied formats (PDFs, images, spreadsheets, and private media). Existing cloud-based knowledge management systems pose severe privacy risks, while native file managers lack intelligent search and organization capabilities. **DocSift** is a 100% offline, privacy-first personal knowledge management and secure vault application. By leveraging a zero-trust architecture, AES-256-GCM encryption, and local data structuring via SQLCipher, DocSift ensures that no other application or network can access the user's data. Furthermore, the system integrates an on-device Retrieval-Augmented Generation (RAG) pipeline utilizing lightweight ONNX AI models and offline OCR to allow users to semantically search and extract answers directly from their encrypted documents without internet dependency. This project demonstrates a highly secure, scalable, and intelligent approach to personal data sovereignty.

## 2. Introduction
DocSift bridges the gap between highly secure cold-storage vaults and intelligent note-taking applications. The core philosophy of the application is absolute data ownership. While modern mobile devices possess immense computational power, most applications still offload document processing and AI interactions to cloud servers, risking data leaks. DocSift flips this paradigm by bringing the processing to the data. Built on a cross-platform Flutter architecture, the application encrypts every file before it touches the device's physical storage and processes all text extraction, OCR, and AI querying locally on the device's CPU.

## 3. Problem Statement & Objectives
**Problem Statement:** 
Professionals and students struggle to securely organize, store, and retrieve information scattered across various document types. Standard cloud solutions compromise privacy, while traditional local storage lacks advanced search, tagging, and analytical capabilities, making data retrieval inefficient.

**Objectives:**
*   **Absolute Security:** Ensure zero network calls; store all files using robust AES-256-GCM encryption.
*   **Database Isolation:** Implement a fully encrypted local database (SQLCipher) to manage metadata, tags, and document relationships securely.
*   **Intelligent Retrieval:** Provide fast keyword search (BM25) and future-proof the application for semantic, AI-powered Q&A querying offline.
*   **Cross-Format Support:** Seamlessly handle and parse text (.pdf, .docx, .md), images (.jpg, .png), and encrypt private media (.mp4, .zip).

## 4. Proposed Methodology & System Architecture

The project will follow a modular architecture, ensuring distinct boundaries between the UI layer, data storage layer, and AI processing pipeline. 

### 4.1 Core Technologies (The Stack)
*   **Frontend UI & Framework:** Flutter 3.x (Dart) for a unified iOS/Android codebase.
*   **State Management:** Riverpod for scalable, reactive state handling.
*   **Database:** SQLite upgraded to **SQLCipher** for transparent 256-bit AES encryption of relational data.
*   **File Encryption:** `PointyCastle` library for encrypting standalone media/documents via AES-256-GCM.
*   **Key Storage:** `flutter_secure_storage` utilizing Android Keystore and iOS Secure Enclave for the Master Vault Encryption Key (VEK).
*   **Parsers & OCR:** `flutter_tesseract_ocr` for offline image text extraction; local Dart parsers for Microsoft Office files.
*   **Offline AI:** `onnxruntime_flutter` to run quantized, lightweight language models on the mobile CPU.

### 4.2 Security & Zero-Trust Data Pipeline
1.  **Authentication:** User sets a PIN, which is hashed via **Argon2id** to protect against brute-force attacks.
2.  **Storage:** The hashed PIN unlocks the VEK. Every file written to the disk is heavily encrypted. No other app (gallery, file manager) can read these files.
3.  **Memory Protection:** Volatile memory wiping is enforced. Once a user closes a decrypted file, the data is explicitly overwritten in the phone's RAM.
4.  **UI Hardening:** OS-level flags (`FLAG_SECURE`) are applied to block screenshots, screen recordings, and background app previews.

### 4.3 The Offline AI "RAG-Lite" Pipeline (Major Scope)
Instead of cloud APIs, DocSift utilizes an offline Retrieval-Augmented Generation pipeline:
1.  **Extraction:** Background isolates run Tesseract OCR on images or Dart parsers on documents to extract raw text.
2.  **Vectorization:** A local MiniLM model (~20MB) converts text chunks into vector embeddings.
3.  **Retrieval:** SQLite FTS5 (BM25) and vector similarity search find the most relevant document chunks based on a user's query.
4.  **Inference:** A local DistilBERT SQuAD2 model (~250MB) reads the retrieved chunks and extracts the exact answer for the user.

## 5. Execution Roadmap (Phases)

| Phase | Milestone | Execution Details |
| :--- | :--- | :--- |
| **Phase 1** | **Scaffolding & UI Prototyping** | Initialize Flutter project, define the design system (Light/Dark themes), configure `go_router`, and build core screens (Dashboard, PIN Setup, Vault Categories). |
| **Phase 2** | **Vault Architecture & Database** | Implement `SQLCipher` local database, set up `flutter_secure_storage` for VEK, and integrate `PointyCastle` to encrypt/decrypt files seamlessly upon upload/view. |
| **Phase 3** | **Data Parsing & OCR Integration** | Integrate `flutter_tesseract_ocr` and text parsers (`docx_to_text`, etc.). Set up background threads (Isolates) to silently extract text from uploaded files without blocking the UI. |
| **Phase 4** | **AI Integration & Search** | Load ONNX models (`onnxruntime_flutter`). Build the local SQLite FTS5 search engine and map the raw text data to the localized Q&A AI. |
| **Phase 5** | **Testing, Security Audits & Deployment** | Conduct memory-leak testing, verify screenshot-blocking mechanisms, test large file encryptions for performance bottlenecks, and prepare final documentation. |

## 6. Mapping with UN Sustainable Development Goals (SDGs)
*   **SDG 4 (Quality Education):** By providing a secure, highly organized, and easily searchable knowledge base, DocSift empowers students and researchers to manage their educational materials effectively without relying on expensive cloud subscriptions.
*   **SDG 9 (Industry, Innovation, and Infrastructure):** Developing an offline-first AI application contributes to technological innovation, showcasing how advanced edge computing can operate securely on consumer hardware without large-scale internet infrastructure.
*   **SDG 16 (Peace, Justice, and Strong Institutions):** Ensures fundamental privacy rights and data sovereignty, protecting individuals from data harvesting and surveillance.

## 7. Conclusion and Future Scope
**Conclusion:** DocSift redefines personal data management by proving that users do not have to sacrifice convenience for security. By executing AES encryption and AI processing entirely on-device, it delivers a highly secure, offline vault that guarantees absolute data privacy.
**Future Scope:** Future iterations of DocSift can include encrypted peer-to-peer (P2P) cross-device synchronization (allowing users to sync vaults between their phone and desktop without a central server), support for local audio transcription (Whisper AI), and advanced on-device document summarization.