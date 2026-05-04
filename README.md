# 📄 DocSign — Free PDF Editor & eSign Tool

**100% Free · 100% Offline · No Account Required · Open Source**

[![Live Demo](https://img.shields.io/badge/Live%20Demo-pdf.contractmind.ai-6366F1?style=for-the-badge&logo=vercel)](https://pdf.contractmind.ai)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Web%20%7C%20Android%20%7C%20iOS%20%7C%20Desktop-blue?style=for-the-badge)](https://pdf.contractmind.ai)

---

## 🎯 Why DocSign?

Professional PDF tools shouldn't cost $40/month. DocSign gives you everything you need — completely free, no account required, works offline.

| Feature | DocSign | DocuSign | Adobe Acrobat | Smallpdf |
|---------|:---:|:---:|:---:|:---:|
| **Price** | **FREE** 🎉 | $10-40/mo | $20/mo | $12/mo |
| **Account Required** | **No** | Yes | Yes | Yes |
| **Works Offline** | **Yes** | No | Limited | No |
| **eSignatures** | **Free** | Paid | Included | Limited |
| **Templates** | **16 Free** | Paid | Paid | Paid |
| **PDF Tools** | **6 Free** | Limited | Paid | Paid |
| **Redaction** | **Free** | Enterprise | Paid | Paid |
| **Privacy** | **100% Local** | Cloud | Cloud | Cloud |
| **Open Source** | **Yes** ✅ | No | No | No |

---

## ✨ Features

### 📄 PDF Viewing
- Individual page zoom with pinch-to-zoom
- Read Mode for smooth scrolling
- Dark Mode support
- Responsive sidebar thumbnails (web) + bottom strip (mobile)
- Adaptive page sizing for all screen sizes
- iOS-optimized rendering

### ✍️ Annotations
- Text highlighting, underlining, strikethrough
- Freehand ink drawing with 8-color palette
- Sticky notes (expandable, color-coded)
- Text stamps with custom fonts, sizes & colors
- Undo/redo for all annotations
- Auto-save sidecar (3s debounce)

### 🖊️ eSignatures
- Draw, type, or upload signatures
- Transparent PNG export (no white background)
- Drag to move, corner handle to resize
- Initials mode for quick sign-off
- Multi-party sequential signing (A → B → C)
- ESIGN Act (US) & eIDAS (EU) compliant
- Cryptographic audit trail with IP tracking
- Role-based: Manager, Legal, Client, Witness, Notary

### 🛠️ PDF Tools
- **Merge PDFs** — Combine multiple PDFs into one
- **Extract Pages** — Pull specific pages from documents
- **Rotate Pages** — Fix sideways scans (90° increments)
- **Watermark** — Add CONFIDENTIAL, DRAFT, INVOICE stamps
- **Duplicate Pages** — Copy pages within documents
- **One-Click Email** — Send signed PDFs instantly
- **QR Code Generator** — Add payment/contact QR codes

### 📋 16 Business Templates

| Finance | Legal | HR | Sales | Admin |
|---------|-------|-----|-------|-------|
| Invoice* | NDA | Offer Letter | Business Proposal | Meeting Minutes |
| Receipt* | Service Agreement | Employment Contract | | |
| Quotation | Freelance Contract | Termination Letter | | |
| Purchase Order | Rental Agreement | | | |
| Bill of Sale | Non-Compete | | | |
| Expense Report | | | | |

*Includes company logo upload & QR payment code

### 📱 Document Scanner
- Camera capture with auto-edge detection
- Interactive crop tool (Free, A4, Wide, Square)
- Multi-page scanning with preview grid
- B&W mode for clean document scans
- Web: zoomable image preview before adding

### 🔒 Security & Privacy
- **True Redaction** — permanently destroys underlying text data
- Password-protected PDF support
- 100% offline — no documents leave your device
- No data collection, no tracking, no cloud storage
- GDPR / CCPA / HIPAA friendly

### 🔍 Pro Tools
- **Document Comparison** — side-by-side with diff percentage
- **Full-text Search** — search across all PDF pages
- **Clause Bookmarks** — tag important contract sections
- **Annotation Summary** — categorized list of all annotations
- **Audit Trail** — signer name, email, timestamp, device, IP
- **Keyboard Shortcuts** — Ctrl+S save, Ctrl+Z undo, Ctrl+P print
- **Save Indicator** — green/orange dot shows save status

---

## 🚀 Quick Start

### Online (No Installation)
Visit **[pdf.contractmind.ai](https://pdf.contractmind.ai)** — works directly in your browser!

### Run Locally
```bash
# Clone the repository
git clone https://github.com/contractmind/docsign.git
cd docsign

# Install dependencies
flutter pub get

# Run on web
flutter run -d chrome

# Run on mobile
flutter run