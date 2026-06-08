import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Map<String, String> get _strings {
    switch (locale.languageCode) {
      case 'es':
        return _es;
      case 'hi':
        return _hi;
      case 'te':
        return _te;
      case 'fr':
        return _fr;
      default:
        return _en;
    }
  }

  // ==================== ENGLISH ====================
  static const Map<String, String> _en = {
    // General
    'appName': 'DocSign',
    'pro': 'PRO',
    'openPdf': 'Open PDF',
    'home': 'Home',
    'recent': 'Recent',
    'templates': 'Templates',
    'scanner': 'Scanner',
    'createPdf': 'Create PDF',
    'pdfTools': 'PDF Tools',
    'settings': 'Settings',
    'files': 'Files',
    'newDoc': 'New Doc',
    'cancel': 'Cancel',
    'save': 'Save',
    'done': 'Done',
    'yes': 'Yes',
    'no': 'No',
    'clear': 'Clear',
    'delete': 'Delete',
    'remove': 'Remove',
    'edit': 'Edit',
    'share': 'Share',
    'print': 'Print',
    'export': 'Export',
    'download': 'Download',
    'upload': 'Upload',
    'change': 'Change',
    'add': 'Add',
    'retry': 'Retry',
    'error': 'Error',
    'processing': 'Processing...',
    'loading': 'Loading...',
    'fieldRequired': 'This field is required',
    'validEmail': 'Enter a valid email address',
    'redacted': 'REDACTED',
    'addNoteTitle': 'Add Note',
    'addNoteHint': 'Type your note…',
    'clauseLabelTitle': 'Clause Label',

    // Dashboard
    'dashboard': 'Dashboard',
    'dashboardSubtitle': 'Open, sign and manage documents',
    'pdfToolsCount': '60+',
    'templatesCount': '16',
    'freeForever': '100% Free',
    'offlinePrivate': '100% Private',
    'quickActions': 'Quick Actions',
    'scan': 'Scan',
    'templatesLabel': 'Templates',
    'compare': 'Compare',
    'recentFiles': 'Recent Files',
    'dropZoneHint': 'Drop your PDF here or click to browse',
    'dropZoneSubHint': 'Supports password-protected PDFs',
    'noRecentFiles': 'No recent files',
    'documents': 'documents',
    'document': 'document',
    'removeFromRecents': 'Remove from recents?',
    'removeFromRecentsMessage':
        'This will only remove the entry from the list, not delete the file.',
    'removedFromRecents': 'Removed from recents',
    'openAnyFile': 'Open Any File',
    'saveCancelled': 'Save cancelled: No folder selected',
    'savedAt': 'Saved: ',
    'invalidFilePath': 'Invalid file path',
    'loadingPdf': 'Loading PDF...',
    'aboutDocSign': 'About DocSign',
    'versionOffline': 'Version 2.0 · 100% Offline',
    'privacyPolicy': 'Privacy Policy',
    'noDataCollected': 'No data collected',
    'chooseSaveLocation': 'Choose save location',
    'downloaded': 'Downloaded',
    'savedAs': 'Saved as',
    'savedTo': 'Saved to',

    // Scanner
    'documentScanner': 'Document Scanner',
    'clearedAllPages': 'Cleared all pages',
    'notAvailableOnWeb': 'Not available on web',
    'scanWebMessage':
        'Document scanning requires a real device with a camera.\n\nPlease use the mobile app or upload images from the gallery.',
    'ok': 'OK',
    'scanningError': 'Scanning error',
    'unexpectedError': 'An unexpected error occurred',
    'galleryError': 'Gallery error',
    'savePdfAs': 'Save PDF as',
    'enterFileName': 'Enter file name',
    'createPdfButton': 'Create PDF',
    'clearAll': 'Clear all',
    'scanDocumentsTitle': 'Scan Documents',
    'scanDocumentsSubtitle':
        'Capture pages with your camera or upload from gallery\nto create a professional PDF document',
    'bw': 'B&W',
    'batch': 'Batch',
    'hd': 'HD',
    'extractText': 'Extract Text',
    'gallery': 'Gallery',
    'page': 'Page',
    'setCategory': 'Set Category',
    'categoryUncategorized': 'Uncategorized',
    'categoryDocument': 'Document',
    'categoryReceipt': 'Receipt',
    'categoryInvoice': 'Invoice',
    'categoryIdCard': 'ID Card',
    'categoryContract': 'Contract',
    'categoryOther': 'Other',
    'extractedText': 'Extracted Text',
    'close': 'Close',
    'copy': 'Copy',
    'textCopied': 'Text copied to clipboard',
    'noTextFound': 'No text found in this image.',
    'ocrError': 'OCR error',
    'addAtLeastOnePage': 'Add at least one page',
    'imageCorrupted': 'Image data corrupted for',

    // PDF Tools
    'merge': 'Merge',
    'extract': 'Extract',
    'rotate': 'Rotate',
    'watermark': 'Watermark',
    'duplicate': 'Duplicate',
    'qrCode': 'QR Code',
    'cannotOpenFile': 'Cannot open file',
    'maxPages': 'Max pages',
    'largeDocument': 'Large Document',
    'pages': 'pages',
    'mayBeSlow': 'may be slow',
    'continue_': 'Continue',
    'merging': 'Merging...',
    'extracting': 'Extracting...',
    'rotating': 'Rotating...',
    'watermarking': 'Watermarking...',
    'duplicating': 'Duplicating...',
    'addingQr': 'Adding QR...',
    'selectPages': 'Select pages',
    'rotateFailed': 'Rotation failed',
    'watermarkHint': 'e.g. CONFIDENTIAL',
    'textColor': 'Text Color:',
    'apply': 'Apply:',
    'all': 'All',
    'selected': 'Selected',
    'qrHint': 'URL or payment link',
    'generate': 'Generate',
    'noPdfLoaded': 'No PDF loaded',

    // PDF Viewer
    'passwordProtected': 'Password Protected',
    'enterPassword': 'Enter password',
    'open': 'Open',
    'openAnotherDocument': 'Do you want to open another document?',
    'saveAs': 'Save as',
    'readModeScroll': 'Read Mode — Scroll to navigate',
    'zoomModePinch': 'Zoom Mode — Pinch to zoom',
    'readMode': 'Read Mode',
    'zoomMode': 'Zoom Mode',
    'tapToPlaceSignature': 'Tap page to place signature',
    'tapToPlaceInitials': 'Tap page to place initials',
    'zoomIn': 'Zoom in',
    'zoomOut': 'Zoom out',
    'resetZoom': 'Reset zoom',
    'undo': 'Undo',
    'darkMode': 'Dark mode',
    'thumbnails': 'Thumbnails',
    'textTool': 'Text',
    'noteTool': 'Note',
    'highlightTool': 'Highlight',
    'underlineTool': 'Underline',
    'strikeTool': 'Strike through',
    'drawTool': 'Draw',
    'redactTool': 'Redact',
    'clauseTool': 'Clause bookmark',
    'tools': 'More tools',
    'signTool': 'Sign',
    'initialsTool': 'Initials',
    'slots': 'Signature slots',
    'audit': 'Audit trail',
    'profile': 'Signer profile',
    'tabEdit': 'Edit',
    'tabAnnotate': 'Annotate',
    'tabFillSign': 'Fill & Sign',
    'tabAll': 'All',
    'highlight': 'Highlight',
    'underline': 'Underline',
    'strike': 'Strike',
    'draw': 'Draw',
    'note': 'Note',
    'redact': 'Redact',
    'clause': 'Clause',
    'text': 'Text',
    'sign': 'Sign',
    'initials': 'Initials',
    'saveFailed': 'Save failed',
    'shareFailed': 'Share failed',
    'printError': 'Print error',

    // Templates common
    'hr': 'HR',
    'legal': 'Legal',
    'finance': 'Finance',
    'sales': 'Sales',
    'admin': 'Admin',
    'career': 'Career',
    'fillArrow': 'Fill →',
    'comingSoon': 'Coming Soon',
    'comingSoonTitle': 'This template is coming soon!',
    'comingSoonMessage': "We're working hard to add more templates.",
    'invoice': 'Invoice',
    'receipt': 'Receipt',
    'quotation': 'Quotation',
    'purchaseOrder': 'Purchase Order',
    'billOfSale': 'Bill of Sale',
    'expenseReport': 'Expense Report',
    'nda': 'NDA',
    'serviceAgreement': 'Service Agreement',
    'freelanceContract': 'Freelance Contract',
    'rentalAgreement': 'Rental Agreement',
    'nonCompete': 'Non-Compete',
    'offerLetter': 'Offer Letter',
    'employmentContract': 'Employment Contract',
    'terminationLetter': 'Termination Letter',
    'businessProposal': 'Business Proposal',
    'meetingMinutes': 'Meeting Minutes',
    'resume': 'Resume / CV',
    'currency': 'Currency',
    'from': 'From',
    'to': 'To',
    'fromAddress': 'From Address',
    'clientAddress': 'Client Address',
    'invoiceNumber': 'Invoice #',
    'issueDate': 'Issue Date',
    'dueDate': 'Due Date',
    'lineItems': 'LINE ITEMS',
    'addLineItem': 'Add Line Item',
    'subtotal': 'Subtotal',
    'tax': 'Tax (10%)',
    'total': 'TOTAL',
    'qrOptional': 'QR CODE (Optional)',
    'notesTerms': 'Notes / Terms',
    'companyLogo': 'Company Logo',
    'logoHint': 'Appears top-right on invoice',
    'billTo': 'BILL TO',
    'description': 'Description',
    'qty': 'Qty',
    'unitPrice': 'Unit Price',
    'scanToPay': 'Scan to pay',
    'notes': 'Notes:',
    'due': 'Due',
    'date': 'Date',
    'company': 'Company',
    'rate': 'Rate (\$)',
    // NDA
    'disclosingParty': 'Disclosing Party',
    'receivingParty': 'Receiving Party',
    'effectiveDate': 'Effective Date',
    'duration': 'Duration',
    'governingState': 'Governing State',
    'ndaTitle': 'NON-DISCLOSURE AGREEMENT',
    'ndaIntro1': 'This Agreement is entered into on',
    'ndaIntro2': 'between',
    'ndaIntro3': '("Disclosing Party") and',
    'ndaIntro4': '("Receiving Party").',
    'clause1': '1. Confidential Information.',
    'clause2': '2. Non-Use.',
    'clause3': '3. Duration. Obligations continue for',
    'clause4': '4. Governing Law. This Agreement is governed by laws of',
    'signature': 'Signature',
    // Offer Letter
    'candidateName': 'Candidate Name',
    'jobTitle': 'Job Title',
    'startDate': 'Start Date',
    'offerDeadline': 'Offer Deadline',
    'compensation': 'Compensation',
    'dear': 'Dear',
    'offerLetterBody1': 'We are pleased to offer you the position of',
    'offerLetterBody2': 'at',
    'offerLetterDeadline': 'Please accept this offer by',
    'position': 'Position',
    'authorizedSignature': 'Authorized Signature',
    'acceptance': 'Acceptance',
    // Purchase Order
    'buyer': 'Buyer',
    'vendor': 'Vendor',
    'poNumber': 'PO Number',
    'delivery': 'Delivery',
    'paymentTerms': 'Payment Terms',
    'items': 'ITEMS',
    'addItem': 'Add Item',
    'item': 'Item',
    'price': 'Price',
    'purchaseOrderTitle': 'PURCHASE ORDER',
    'terms': 'Terms',
    // Service Agreement
    'serviceProvider': 'Service Provider',
    'client': 'Client',
    'servicesDescription': 'Services Description',
    'feeMonthly': 'Fee (monthly)',
    'endDate': 'End Date',
    'serviceAgreementTitle': 'SERVICE AGREEMENT',
    'serviceAgreementIntro1': 'This Agreement is between',
    'serviceAgreementIntro2': '("Provider") and',
    'serviceAgreementIntro3': '("Client").',
    'services': 'Services',
    'fee': 'Fee',
    'term': 'Term',
    'perMonth': 'month',
    // Receipt
    'receiptNumber': 'Receipt #',
    'receiptTitle': 'RECEIPT',
    'thankYou': 'Thank you!',
    // Quotation
    'quotationNumber': 'Quote #',
    'validUntil': 'Valid Until',
    'quotationTitle': 'QUOTATION',
    // Bill of Sale
    'seller': 'Seller',
    'itemDescription': 'Item/Asset Description',
    'salePrice': 'Sale Price',
    'dateOfSale': 'Date of Sale',
    'billOfSaleTitle': 'BILL OF SALE',
    'billOfSaleIntro1': 'This Bill of Sale is made on',
    'billOfSaleIntro2': 'between',
    'billOfSaleIntro3': '("Seller") and',
    'billOfSaleIntro4': '("Buyer").',
    'billOfSaleAmount': 'For the sum of',
    'billOfSaleTransfer': 'the Seller sells and transfers to the Buyer the following property:',
    'sellerSignature': 'Seller Signature',
    'buyerSignature': 'Buyer Signature',
    // Expense Report
    'employee': 'Employee',
    'department': 'Department',
    'expenses': 'EXPENSES',
    'addExpense': 'Add Expense',
    'amount': 'Amount',
    'expenseReportTitle': 'EXPENSE REPORT',
    // Freelance Contract
    'freelancer': 'Freelancer',
    'scopeOfWork': 'Scope of Work',
    'hourlyRateFixed': 'Hourly Rate / Fixed Fee',
    'deadline': 'Deadline',
    'freelanceContractTitle': 'FREELANCE CONTRACT',
    'freelanceContractIntro1': 'This Agreement is between',
    'freelanceContractIntro2': '("Freelancer") and',
    'freelanceContractIntro3': '("Client").',
    // Rental Agreement
    'landlord': 'Landlord',
    'tenant': 'Tenant',
    'propertyAddress': 'Property Address',
    'monthlyRent': 'Monthly Rent',
    'rentalAgreementTitle': 'RESIDENTIAL RENTAL AGREEMENT',
    'rentalAgreementIntro1': 'This Agreement is made between',
    'rentalAgreementIntro2': '("Landlord") and',
    'rentalAgreementIntro3': '("Tenant") for the property at',
    'additionalTerms': 'Additional terms: Tenant agrees to maintain the property and pay utilities.',
    // Non-Compete
    'geographicRadius': 'Geographic Radius',
    'nonCompeteTitle': 'NON-COMPETE AGREEMENT',
    'nonCompeteIntro1': 'This Non-Compete Agreement is between',
    'nonCompeteIntro2': '("Company") and',
    'nonCompeteIntro3': '("Employee").',
    'nonCompeteBody1': 'For a period of',
    'nonCompeteBody2': 'within',
    'nonCompeteBody3': 'of the Company\'s business, Employee agrees not to engage in any competing business.',
    'representative': 'Representative',
    // Employment Contract
    'employer': 'Employer',
    'annualSalary': 'Annual Salary',
    'employmentContractTitle': 'EMPLOYMENT CONTRACT',
    'employmentContractIntro1': 'This Employment Contract is entered into between',
    'employmentContractIntro2': '("Employer") and',
    'employmentContractIntro3': '("Employee").',
    'standardTerms': 'Standard terms: 40 hours/week, 15 days paid leave.',
    // Termination Letter
    'reasonTermination': 'Reason for Termination',
    'terminationLetterTitle': 'TERMINATION LETTER',
    'terminationLetterBody1': 'This letter confirms the termination of your employment with',
    'terminationLetterBody2': 'effective',
    'reason': 'Reason',
    'terminationLetterFooter': 'Please return all company property. Your final paycheck will be processed.',
    // Business Proposal
    'projectTitle': 'Project / Proposal Title',
    'estimatedBudget': 'Estimated Budget',
    'timeline': 'Timeline',
    'businessProposalTitle': 'BUSINESS PROPOSAL',
    'preparedFor': 'Prepared for',
    'preparedBy': 'Prepared by',
    'project': 'Project',
    'budget': 'Budget',
    'businessProposalBody': 'We are excited to present this proposal. Our team will deliver high-quality results within the agreed timeline.',
    // Meeting Minutes
    'attendees': 'Attendees',
    'minutesDecisions': 'Minutes / Decisions',
    'meetingMinutesTitle': 'MEETING MINUTES',
    'minutes': 'Minutes',
    // Resume
    'fresher': 'Fresher',
    'experienced': 'Experienced',
    'photoOptional': 'Photo (optional)',
    'photoHint': 'Appears on resume',
    'personalDetails': 'PERSONAL DETAILS',
    'fullName': 'Full Name',
    'jobTitleOptional': 'Job Title (optional)',
    'email': 'Email',
    'phone': 'Phone',
    'location': 'Location',
    'linkedinPortfolio': 'LinkedIn / Portfolio',
    'professionalSummary': 'Professional Summary',
    'education': 'EDUCATION',
    'degree': 'Degree',
    'institution': 'Institution',
    'yearDuration': 'Year / Duration',
    'gpa': 'GPA / Percentage',
    'internships': 'INTERNSHIPS',
    'workExperience': 'WORK EXPERIENCE',
    'internship': 'Internship',
    'experience': 'Experience',
    'titleRole': 'Title / Role',
    'descriptionBullets': 'Description (bullet points)',
    'addInternship': 'Add Internship',
    'addWorkExperience': 'Add Work Experience',
    'projects': 'PROJECTS',
    'projectName': 'Project Name',
    'technologiesUsed': 'Technologies Used',
    'addProject': 'Add Project',
    'skills': 'SKILLS',
    'addSkill': 'Add Skill',
    'tech': 'Tech',
    'certifications': 'CERTIFICATIONS',
    'certification': 'Certification',
    'certificationName': 'Certification Name',
    'issuingOrg': 'Issuing Organization',
    'year': 'Year',
    'addCertification': 'Add Certification',
    'achievements': 'ACHIEVEMENTS',
    'achievementHint': 'Achievement',
    'addAchievement': 'Add Achievement',
    'generatePdf': 'Generate PDF',
    'generating': 'Generating...',
    'single': 'Single',
    'idCard': 'ID Card',
  };

  // ==================== SPANISH ====================
  static const Map<String, String> _es = {
    'appName': 'DocSign',
    'pro': 'PRO',
    'openPdf': 'Abrir PDF',
    'home': 'Inicio',
    'recent': 'Recientes',
    'templates': 'Plantillas',
    'scanner': 'Escáner',
    'createPdf': 'Crear PDF',
    'pdfTools': 'Herramientas PDF',
    'settings': 'Ajustes',
    'files': 'Archivos',
    'newDoc': 'Nuevo doc.',
    'cancel': 'Cancelar',
    'save': 'Guardar',
    'done': 'Hecho',
    'yes': 'Sí',
    'no': 'No',
    'clear': 'Limpiar',
    'delete': 'Eliminar',
    'remove': 'Quitar',
    'edit': 'Editar',
    'share': 'Compartir',
    'print': 'Imprimir',
    'export': 'Exportar',
    'download': 'Descargar',
    'upload': 'Subir',
    'change': 'Cambiar',
    'add': 'Añadir',
    'retry': 'Reintentar',
    'error': 'Error',
    'processing': 'Procesando...',
    'loading': 'Cargando...',
    'fieldRequired': 'Este campo es obligatorio',
    'validEmail': 'Introduce un correo electrónico válido',
    'redacted': 'REDACCIÓN',
    'addNoteTitle': 'Añadir nota',
    'addNoteHint': 'Escribe tu nota…',
    'clauseLabelTitle': 'Etiqueta de cláusula',

    'dashboard': 'Panel',
    'dashboardSubtitle': 'Abre, firma y gestiona documentos',
    'pdfToolsCount': '60+',
    'templatesCount': '16',
    'freeForever': '100% Gratis',
    'offlinePrivate': '100% Privado',
    'quickActions': 'Acciones rápidas',
    'scan': 'Escanear',
    'templatesLabel': 'Plantillas',
    'compare': 'Comparar',
    'recentFiles': 'Archivos recientes',
    'dropZoneHint': 'Suelta tu PDF aquí o haz clic para buscar',
    'dropZoneSubHint': 'Admite PDFs protegidos con contraseña',
    'noRecentFiles': 'No hay archivos recientes',
    'documents': 'documentos',
    'document': 'documento',
    'removeFromRecents': '¿Eliminar de recientes?',
    'removeFromRecentsMessage':
        'Esto solo eliminará la entrada de la lista, no borrará el archivo.',
    'removedFromRecents': 'Eliminado de recientes',
    'openAnyFile': 'Abrir cualquier archivo',
    'saveCancelled': 'Guardado cancelado: no se seleccionó carpeta',
    'savedAt': 'Guardado en: ',
    'invalidFilePath': 'Ruta de archivo no válida',
    'loadingPdf': 'Cargando PDF...',
    'aboutDocSign': 'Acerca de DocSign',
    'versionOffline': 'Versión 2.0 · 100% sin conexión',
    'privacyPolicy': 'Política de privacidad',
    'noDataCollected': 'No se recopilan datos',
    'chooseSaveLocation': 'Elige ubicación de guardado',
    'downloaded': 'Descargado',
    'savedAs': 'Guardado como',
    'savedTo': 'Guardado en',

    'documentScanner': 'Escáner de documentos',
    'clearedAllPages': 'Páginas borradas',
    'notAvailableOnWeb': 'No disponible en web',
    'scanWebMessage':
        'El escaneo de documentos requiere un dispositivo real con cámara.\n\nUsa la aplicación móvil o sube imágenes desde la galería.',
    'ok': 'OK',
    'scanningError': 'Error al escanear',
    'unexpectedError': 'Ocurrió un error inesperado',
    'galleryError': 'Error de galería',
    'savePdfAs': 'Guardar PDF como',
    'enterFileName': 'Nombre del archivo',
    'createPdfButton': 'Crear PDF',
    'clearAll': 'Borrar todo',
    'scanDocumentsTitle': 'Escanea documentos',
    'scanDocumentsSubtitle':
        'Captura páginas con tu cámara o súbelas desde la galería\npara crear un PDF profesional',
    'bw': 'ByN',
    'batch': 'Lote',
    'hd': 'HD',
    'extractText': 'Extraer texto',
    'gallery': 'Galería',
    'page': 'Página',
    'setCategory': 'Categoría',
    'categoryUncategorized': 'Sin categoría',
    'categoryDocument': 'Documento',
    'categoryReceipt': 'Recibo',
    'categoryInvoice': 'Factura',
    'categoryIdCard': 'Documento de identidad',
    'categoryContract': 'Contrato',
    'categoryOther': 'Otro',
    'extractedText': 'Texto extraído',
    'close': 'Cerrar',
    'copy': 'Copiar',
    'textCopied': 'Texto copiado al portapapeles',
    'noTextFound': 'No se encontró texto en esta imagen.',
    'ocrError': 'Error de OCR',
    'addAtLeastOnePage': 'Agrega al menos una página',
    'imageCorrupted': 'Datos de imagen dañados para',

    'merge': 'Fusionar',
    'extract': 'Extraer',
    'rotate': 'Rotar',
    'watermark': 'Marca de agua',
    'duplicate': 'Duplicar',
    'qrCode': 'Código QR',
    'cannotOpenFile': 'No se puede abrir el archivo',
    'maxPages': 'Máx. páginas',
    'largeDocument': 'Documento grande',
    'pages': 'páginas',
    'mayBeSlow': 'puede ser lento',
    'continue_': 'Continuar',
    'merging': 'Fusionando...',
    'extracting': 'Extrayendo...',
    'rotating': 'Rotando...',
    'watermarking': 'Agregando marca...',
    'duplicating': 'Duplicando...',
    'addingQr': 'Agregando QR...',
    'selectPages': 'Selecciona páginas',
    'rotateFailed': 'Error al rotar',
    'watermarkHint': 'p.ej. CONFIDENCIAL',
    'textColor': 'Color de texto:',
    'apply': 'Aplicar:',
    'all': 'Todo',
    'selected': 'Seleccionado',
    'qrHint': 'URL o enlace de pago',
    'generate': 'Generar',
    'noPdfLoaded': 'No se cargó ningún PDF',

    'passwordProtected': 'Protegido con contraseña',
    'enterPassword': 'Introduce la contraseña',
    'open': 'Abrir',
    'openAnotherDocument': '¿Abrir otro documento?',
    'saveAs': 'Guardar como',
    'readModeScroll': 'Modo lectura — Desplázate',
    'zoomModePinch': 'Modo zoom — Pellizca para ampliar',
    'readMode': 'Modo lectura',
    'zoomMode': 'Modo zoom',
    'tapToPlaceSignature': 'Toca la página para colocar la firma',
    'tapToPlaceInitials': 'Toca la página para colocar las iniciales',
    'zoomIn': 'Acercar',
    'zoomOut': 'Alejar',
    'resetZoom': 'Restablecer zoom',
    'undo': 'Deshacer',
    'darkMode': 'Modo oscuro',
    'thumbnails': 'Miniaturas',
    'textTool': 'Texto',
    'noteTool': 'Nota',
    'highlightTool': 'Resaltar',
    'underlineTool': 'Subrayar',
    'strikeTool': 'Tachar',
    'drawTool': 'Dibujar',
    'redactTool': 'Redactar',
    'clauseTool': 'Marcador de cláusula',
    'tools': 'Más herramientas',
    'signTool': 'Firmar',
    'initialsTool': 'Iniciales',
    'slots': 'Ranuras de firma',
    'audit': 'Registro de auditoría',
    'profile': 'Perfil del firmante',
    'tabEdit': 'Editar',
    'tabAnnotate': 'Anotar',
    'tabFillSign': 'Rellenar y firmar',
    'tabAll': 'Todo',
    'highlight': 'Resaltar',
    'underline': 'Subrayar',
    'strike': 'Tachar',
    'draw': 'Dibujar',
    'note': 'Nota',
    'redact': 'Redactar',
    'clause': 'Cláusula',
    'text': 'Texto',
    'sign': 'Firmar',
    'initials': 'Iniciales',
    'saveFailed': 'Error al guardar',
    'shareFailed': 'Error al compartir',
    'printError': 'Error de impresión',

    'hr': 'RRHH',
    'legal': 'Legal',
    'finance': 'Finanzas',
    'sales': 'Ventas',
    'admin': 'Admin',
    'career': 'Carrera',
    'fillArrow': 'Llenar →',
    'comingSoon': 'Próximamente',
    'comingSoonTitle': '¡Esta plantilla estará disponible pronto!',
    'comingSoonMessage': 'Estamos trabajando para añadir más plantillas.',
    'invoice': 'Factura',
    'receipt': 'Recibo',
    'quotation': 'Presupuesto',
    'purchaseOrder': 'Orden de compra',
    'billOfSale': 'Factura de venta',
    'expenseReport': 'Informe de gastos',
    'nda': 'Acuerdo de confidencialidad',
    'serviceAgreement': 'Contrato de servicios',
    'freelanceContract': 'Contrato freelance',
    'rentalAgreement': 'Contrato de alquiler',
    'nonCompete': 'No competencia',
    'offerLetter': 'Carta de oferta',
    'employmentContract': 'Contrato laboral',
    'terminationLetter': 'Carta de despido',
    'businessProposal': 'Propuesta comercial',
    'meetingMinutes': 'Acta de reunión',
    'resume': 'Currículum / CV',
    'currency': 'Moneda',
    'from': 'De',
    'to': 'Para',
    'fromAddress': 'Dirección del emisor',
    'clientAddress': 'Dirección del cliente',
    'invoiceNumber': 'Nº factura',
    'issueDate': 'Fecha de emisión',
    'dueDate': 'Fecha de vencimiento',
    'lineItems': 'LÍNEAS DE DETALLE',
    'addLineItem': 'Añadir línea',
    'subtotal': 'Subtotal',
    'tax': 'IVA (10%)',
    'total': 'TOTAL',
    'qrOptional': 'CÓDIGO QR (opcional)',
    'notesTerms': 'Notas / condiciones',
    'companyLogo': 'Logotipo de la empresa',
    'logoHint': 'Aparece arriba a la derecha en la factura',
    'billTo': 'FACTURAR A',
    'description': 'Descripción',
    'qty': 'Cant.',
    'unitPrice': 'Precio unitario',
    'scanToPay': 'Escanear para pagar',
    'notes': 'Notas:',
    'due': 'Vence',
    'date': 'Fecha',
    'company': 'Empresa',
    'rate': 'Tarifa (\$)',
    'disclosingParty': 'Parte reveladora',
    'receivingParty': 'Parte receptora',
    'effectiveDate': 'Fecha efectiva',
    'duration': 'Duración',
    'governingState': 'Estado regulador',
    'ndaTitle': 'ACUERDO DE CONFIDENCIALIDAD',
    'ndaIntro1': 'El presente Acuerdo se celebra el',
    'ndaIntro2': 'entre',
    'ndaIntro3': '("Parte reveladora") y',
    'ndaIntro4': '("Parte receptora").',
    'clause1': '1. Información confidencial.',
    'clause2': '2. No uso.',
    'clause3': '3. Duración. Las obligaciones continúan durante',
    'clause4': '4. Ley aplicable. Este Acuerdo se rige por las leyes de',
    'signature': 'Firma',
    'candidateName': 'Nombre del candidato',
    'jobTitle': 'Puesto',
    'startDate': 'Fecha de inicio',
    'offerDeadline': 'Fecha límite de la oferta',
    'compensation': 'Remuneración',
    'dear': 'Estimado/a',
    'offerLetterBody1': 'Nos complace ofrecerle el puesto de',
    'offerLetterBody2': 'en',
    'offerLetterDeadline': 'Por favor, acepte esta oferta antes del',
    'position': 'Puesto',
    'authorizedSignature': 'Firma autorizada',
    'acceptance': 'Aceptación',
    'buyer': 'Comprador',
    'vendor': 'Proveedor',
    'poNumber': 'Nº de pedido',
    'delivery': 'Entrega',
    'paymentTerms': 'Condiciones de pago',
    'items': 'ARTÍCULOS',
    'addItem': 'Añadir artículo',
    'item': 'Artículo',
    'price': 'Precio',
    'purchaseOrderTitle': 'ORDEN DE COMPRA',
    'terms': 'Condiciones',
    'serviceProvider': 'Proveedor del servicio',
    'client': 'Cliente',
    'servicesDescription': 'Descripción de los servicios',
    'feeMonthly': 'Tarifa (mensual)',
    'endDate': 'Fecha de fin',
    'serviceAgreementTitle': 'CONTRATO DE SERVICIOS',
    'serviceAgreementIntro1': 'El presente Acuerdo se celebra entre',
    'serviceAgreementIntro2': '("Proveedor") y',
    'serviceAgreementIntro3': '("Cliente").',
    'services': 'Servicios',
    'fee': 'Tarifa',
    'term': 'Plazo',
    'perMonth': 'mes',
    'receiptNumber': 'Nº de recibo',
    'receiptTitle': 'RECIBO',
    'thankYou': '¡Gracias!',
    'quotationNumber': 'Nº de presupuesto',
    'validUntil': 'Válido hasta',
    'quotationTitle': 'PRESUPUESTO',
    'seller': 'Vendedor',
    'itemDescription': 'Descripción del artículo',
    'salePrice': 'Precio de venta',
    'dateOfSale': 'Fecha de venta',
    'billOfSaleTitle': 'FACTURA DE VENTA',
    'billOfSaleIntro1': 'La presente Factura de Venta se otorga el',
    'billOfSaleIntro2': 'entre',
    'billOfSaleIntro3': '("Vendedor") y',
    'billOfSaleIntro4': '("Comprador").',
    'billOfSaleAmount': 'Por la suma de',
    'billOfSaleTransfer': 'el Vendedor vende y transfiere al Comprador la siguiente propiedad:',
    'sellerSignature': 'Firma del vendedor',
    'buyerSignature': 'Firma del comprador',
    'employee': 'Empleado',
    'department': 'Departamento',
    'expenses': 'GASTOS',
    'addExpense': 'Añadir gasto',
    'amount': 'Importe',
    'expenseReportTitle': 'INFORME DE GASTOS',
    'freelancer': 'Freelance',
    'scopeOfWork': 'Alcance del trabajo',
    'hourlyRateFixed': 'Tarifa por hora / Precio fijo',
    'deadline': 'Fecha límite',
    'freelanceContractTitle': 'CONTRATO FREELANCE',
    'freelanceContractIntro1': 'El presente Acuerdo se celebra entre',
    'freelanceContractIntro2': '("Freelance") y',
    'freelanceContractIntro3': '("Cliente").',
    'landlord': 'Arrendador',
    'tenant': 'Arrendatario',
    'propertyAddress': 'Dirección de la propiedad',
    'monthlyRent': 'Renta mensual',
    'rentalAgreementTitle': 'CONTRATO DE ARRENDAMIENTO RESIDENCIAL',
    'rentalAgreementIntro1': 'El presente Acuerdo se celebra entre',
    'rentalAgreementIntro2': '("Arrendador") y',
    'rentalAgreementIntro3': '("Arrendatario") para la propiedad en',
    'additionalTerms': 'Términos adicionales: El arrendatario se compromete a mantener la propiedad y pagar los servicios públicos.',
    'geographicRadius': 'Radio geográfico',
    'nonCompeteTitle': 'ACUERDO DE NO COMPETENCIA',
    'nonCompeteIntro1': 'El presente Acuerdo de No Competencia se celebra entre',
    'nonCompeteIntro2': '("Empresa") y',
    'nonCompeteIntro3': '("Empleado").',
    'nonCompeteBody1': 'Durante un período de',
    'nonCompeteBody2': 'dentro de',
    'nonCompeteBody3': 'del negocio de la Empresa, el Empleado acepta no participar en ninguna actividad competitiva.',
    'representative': 'Representante',
    'employer': 'Empleador',
    'annualSalary': 'Salario anual',
    'employmentContractTitle': 'CONTRATO LABORAL',
    'employmentContractIntro1': 'El presente Contrato Laboral se celebra entre',
    'employmentContractIntro2': '("Empleador") y',
    'employmentContractIntro3': '("Empleado").',
    'standardTerms': 'Términos estándar: 40 horas/semana, 15 días de vacaciones pagadas.',
    'reasonTermination': 'Motivo del despido',
    'terminationLetterTitle': 'CARTA DE DESPIDO',
    'terminationLetterBody1': 'La presente carta confirma la terminación de su empleo con',
    'terminationLetterBody2': 'efectiva el',
    'reason': 'Motivo',
    'terminationLetterFooter': 'Por favor, devuelva toda la propiedad de la empresa. Su último sueldo será procesado.',
    'projectTitle': 'Título del proyecto / propuesta',
    'estimatedBudget': 'Presupuesto estimado',
    'timeline': 'Cronograma',
    'businessProposalTitle': 'PROPUESTA COMERCIAL',
    'preparedFor': 'Preparado para',
    'preparedBy': 'Preparado por',
    'project': 'Proyecto',
    'budget': 'Presupuesto',
    'businessProposalBody': 'Estamos entusiasmados de presentar esta propuesta. Nuestro equipo entregará resultados de alta calidad dentro del cronograma acordado.',
    'attendees': 'Asistentes',
    'minutesDecisions': 'Acta / decisiones',
    'meetingMinutesTitle': 'ACTA DE REUNIÓN',
    'minutes': 'Acta',
    'fresher': 'Sin experiencia',
    'experienced': 'Con experiencia',
    'photoOptional': 'Foto (opcional)',
    'photoHint': 'Aparece en el currículum',
    'personalDetails': 'DATOS PERSONALES',
    'fullName': 'Nombre completo',
    'jobTitleOptional': 'Título profesional (opcional)',
    'email': 'Correo electrónico',
    'phone': 'Teléfono',
    'location': 'Ubicación',
    'linkedinPortfolio': 'LinkedIn / Portafolio',
    'professionalSummary': 'Resumen profesional',
    'education': 'EDUCACIÓN',
    'degree': 'Título',
    'institution': 'Institución',
    'yearDuration': 'Año / Duración',
    'gpa': 'Promedio / Porcentaje',
    'internships': 'PASANTÍAS',
    'workExperience': 'EXPERIENCIA LABORAL',
    'internship': 'Pasantía',
    'experience': 'Experiencia',
    'titleRole': 'Puesto / Rol',
    'descriptionBullets': 'Descripción (puntos)',
    'addInternship': 'Agregar pasantía',
    'addWorkExperience': 'Agregar experiencia laboral',
    'projects': 'PROYECTOS',
    'projectName': 'Nombre del proyecto',
    'technologiesUsed': 'Tecnologías utilizadas',
    'addProject': 'Agregar proyecto',
    'skills': 'HABILIDADES',
    'addSkill': 'Agregar habilidad',
    'tech': 'Tecnología',
    'certifications': 'CERTIFICACIONES',
    'certification': 'Certificación',
    'certificationName': 'Nombre de la certificación',
    'issuingOrg': 'Organización que la expide',
    'year': 'Año',
    'addCertification': 'Agregar certificación',
    'achievements': 'LOGROS',
    'achievementHint': 'Logro',
    'addAchievement': 'Agregar logro',
    'generatePdf': 'Generar PDF',
    'generating': 'Generando...',
    'single': 'Individual',
    'idCard': 'Tarjeta de identificación',
  };

  // ==================== HINDI (Placeholder – replace with actual Hindi) ====================
  static const Map<String, String> _hi = {
  'appName': 'डॉकसाइन',
  'pro': 'प्रो',
  'openPdf': 'पीडीएफ खोलें',
  'home': 'होम',
  'recent': 'हाल ही में',
  'templates': 'टेम्पलेट्स',
  'scanner': 'स्कैनर',
  'createPdf': 'पीडीएफ बनाएं',
  'pdfTools': 'पीडीएफ टूल्स',
  'settings': 'सेटिंग्स',
  'files': 'फ़ाइलें',
  'newDoc': 'नया दस्तावेज़',
  'cancel': 'रद्द करें',
  'save': 'सहेजें',
  'done': 'पूर्ण',
  'yes': 'हाँ',
  'no': 'नहीं',
  'clear': 'साफ़ करें',
  'delete': 'हटाएँ',
  'remove': 'निकालें',
  'edit': 'संपादित करें',
  'share': 'साझा करें',
  'print': 'प्रिंट करें',
  'export': 'निर्यात करें',
  'download': 'डाउनलोड',
  'upload': 'अपलोड',
  'change': 'बदलें',
  'add': 'जोड़ें',
  'retry': 'पुनः प्रयास करें',
  'error': 'त्रुटि',
  'processing': 'प्रोसेस हो रहा है...',
  'loading': 'लोड हो रहा है...',
  'fieldRequired': 'यह फ़ील्ड आवश्यक है',
  'validEmail': 'वैध ईमेल पता दर्ज करें',
  'redacted': 'गोपनीय',
  'addNoteTitle': 'नोट जोड़ें',
  'addNoteHint': 'अपना नोट लिखें…',
  'clauseLabelTitle': 'क्लॉज लेबल',
  'dashboard': 'डैशबोर्ड',
  'dashboardSubtitle': 'दस्तावेज़ खोलें, हस्ताक्षर करें और प्रबंधित करें',
  'pdfToolsCount': '60+',
  'templatesCount': '16',
  'freeForever': '100% निःशुल्क',
  'offlinePrivate': '100% निजी',
  'quickActions': 'त्वरित कार्य',
  'scan': 'स्कैन',
  'templatesLabel': 'टेम्पलेट्स',
  'compare': 'तुलना',
  'recentFiles': 'हाल की फ़ाइलें',
  'dropZoneHint': 'अपनी पीडीएफ यहाँ छोड़ें या ब्राउज़ करने के लिए क्लिक करें',
  'dropZoneSubHint': 'पासवर्ड-संरक्षित पीडीएफ समर्थित हैं',
  'noRecentFiles': 'कोई हाल की फ़ाइल नहीं',
  'documents': 'दस्तावेज़',
  'document': 'दस्तावेज़',
  'removeFromRecents': 'हाल की सूची से हटाएँ?',
  'removeFromRecentsMessage':
      'यह केवल सूची से प्रविष्टि हटाएगा, फ़ाइल नहीं हटाएगा।',
  'removedFromRecents': 'हाल की सूची से हटाया गया',
  'openAnyFile': 'कोई भी फ़ाइल खोलें',
  'saveCancelled': 'सहेजना रद्द: कोई फ़ोल्डर चयनित नहीं',
  'savedAt': 'सहेजा गया: ',
  'invalidFilePath': 'अमान्य फ़ाइल पथ',
  'loadingPdf': 'पीडीएफ लोड हो रही है...',
  'aboutDocSign': 'डॉकसाइन के बारे में',
  'versionOffline': 'संस्करण 2.0 · 100% ऑफलाइन',
  'privacyPolicy': 'गोपनीयता नीति',
  'noDataCollected': 'कोई डेटा एकत्र नहीं किया गया',
  'chooseSaveLocation': 'सहेजने का स्थान चुनें',
  'downloaded': 'डाउनलोड हो गया',
  'savedAs': 'इस नाम से सहेजा गया',
  'savedTo': 'यहाँ सहेजा गया',
  'documentScanner': 'दस्तावेज़ स्कैनर',
  'clearedAllPages': 'सभी पृष्ठ साफ़ कर दिए गए',
  'notAvailableOnWeb': 'वेब पर उपलब्ध नहीं',
  'scanWebMessage':
      'दस्तावेज़ स्कैनिंग के लिए कैमरे वाले वास्तविक डिवाइस की आवश्यकता है।\n\nकृपया मोबाइल ऐप का उपयोग करें या गैलरी से चित्र अपलोड करें।',
  'ok': 'ठीक है',
  'scanningError': 'स्कैनिंग त्रुटि',
  'unexpectedError': 'एक अप्रत्याशित त्रुटि हुई',
  'galleryError': 'गैलरी त्रुटि',
  'savePdfAs': 'पीडीएफ इस नाम से सहेजें',
  'enterFileName': 'फ़ाइल का नाम दर्ज करें',
  'createPdfButton': 'पीडीएफ बनाएं',
  'clearAll': 'सभी साफ़ करें',
  'scanDocumentsTitle': 'दस्तावेज़ स्कैन करें',
  'scanDocumentsSubtitle':
      'अपने कैमरे से पृष्ठ कैप्चर करें या गैलरी से अपलोड करें\nताकि एक पेशेवर पीडीएफ दस्तावेज़ बनाया जा सके',
  'bw': 'श्वेत-श्याम',
  'batch': 'बैच',
  'hd': 'एचडी',
  'extractText': 'पाठ निकालें',
  'gallery': 'गैलरी',
  'page': 'पृष्ठ',
  'setCategory': 'श्रेणी सेट करें',
  'categoryUncategorized': 'अवर्गीकृत',
  'categoryDocument': 'दस्तावेज़',
  'categoryReceipt': 'रसीद',
  'categoryInvoice': 'चालान',
  'categoryIdCard': 'पहचान पत्र',
  'categoryContract': 'अनुबंध',
  'categoryOther': 'अन्य',
  'extractedText': 'निकाला गया पाठ',
  'close': 'बंद करें',
  'copy': 'कॉपी करें',
  'textCopied': 'पाठ क्लिपबोर्ड में कॉपी किया गया',
  'noTextFound': 'इस चित्र में कोई पाठ नहीं मिला।',
  'ocrError': 'OCR त्रुटि',
  'addAtLeastOnePage': 'कम से कम एक पृष्ठ जोड़ें',
  'imageCorrupted': 'चित्र डेटा दूषित है',
  'merge': 'मिलाएं',
  'extract': 'निकालें',
  'rotate': 'घुमाएं',
  'watermark': 'वॉटरमार्क',
  'duplicate': 'प्रतिलिपि बनाएं',
  'qrCode': 'QR कोड',
  'cannotOpenFile': 'फ़ाइल नहीं खोली जा सकती',
  'maxPages': 'अधिकतम पृष्ठ',
  'largeDocument': 'बड़ा दस्तावेज़',
  'pages': 'पृष्ठ',
  'mayBeSlow': 'धीमा हो सकता है',
  'continue_': 'जारी रखें',
  'merging': 'मिलाया जा रहा है...',
  'extracting': 'निकाला जा रहा है...',
  'rotating': 'घुमाया जा रहा है...',
  'watermarking': 'वॉटरमार्क जोड़ा जा रहा है...',
  'duplicating': 'प्रतिलिपि बनाई जा रही है...',
  'addingQr': 'QR जोड़ा जा रहा है...',
  'selectPages': 'पृष्ठ चुनें',
  'rotateFailed': 'घुमाना विफल हुआ',
  'watermarkHint': 'जैसे: गोपनीय',
  'textColor': 'पाठ रंग:',
  'apply': 'लागू करें:',
  'all': 'सभी',
  'selected': 'चयनित',
  'qrHint': 'URL या भुगतान लिंक',
  'generate': 'उत्पन्न करें',
  'noPdfLoaded': 'कोई PDF लोड नहीं की गई',
  'passwordProtected': 'पासवर्ड संरक्षित',
  'enterPassword': 'पासवर्ड दर्ज करें',
  'open': 'खोलें',
  'openAnotherDocument': 'क्या आप कोई अन्य दस्तावेज़ खोलना चाहते हैं?',
  'saveAs': 'इस रूप में सहेजें',
  'readModeScroll': 'रीड मोड — नेविगेट करने के लिए स्क्रॉल करें',
  'zoomModePinch': 'ज़ूम मोड — ज़ूम करने के लिए पिंच करें',
  'readMode': 'रीड मोड',
  'zoomMode': 'ज़ूम मोड',
  'tapToPlaceSignature': 'हस्ताक्षर रखने के लिए पृष्ठ पर टैप करें',
  'tapToPlaceInitials': 'इनिशियल्स रखने के लिए पृष्ठ पर टैप करें',
  'zoomIn': 'ज़ूम इन',
  'zoomOut': 'ज़ूम आउट',
  'resetZoom': 'ज़ूम रीसेट करें',
  'undo': 'पूर्ववत करें',
  'darkMode': 'डार्क मोड',
  'thumbnails': 'थंबनेल',
  'textTool': 'पाठ',
  'noteTool': 'नोट',
  'highlightTool': 'हाइलाइट',
  'underlineTool': 'रेखांकित',
  'strikeTool': 'काटें',
  'drawTool': 'चित्र बनाएं',
  'redactTool': 'संपादित/छिपाएं',
  'clauseTool': 'क्लॉज़ बुकमार्क',
  'tools': 'अधिक उपकरण',
  'signTool': 'हस्ताक्षर',
  'initialsTool': 'इनिशियल्स',
  'slots': 'हस्ताक्षर स्लॉट',
  'audit': 'ऑडिट ट्रेल',
  'profile': 'हस्ताक्षरकर्ता प्रोफ़ाइल',
  'tabEdit': 'संपादित करें',
  'tabAnnotate': 'टिप्पणी करें',
  'tabFillSign': 'भरें और हस्ताक्षर करें',
  'tabAll': 'सभी',
  'highlight': 'हाइलाइट',
  'underline': 'रेखांकित',
  'strike': 'काटें',
  'draw': 'चित्र बनाएं',
  'note': 'नोट',
  'redact': 'छिपाएं',
  'clause': 'क्लॉज़',
  'text': 'पाठ',
  'sign': 'हस्ताक्षर',
  'initials': 'इनिशियल्स',
  'saveFailed': 'सहेजना विफल हुआ',
  'shareFailed': 'साझा करना विफल हुआ',
  'printError': 'प्रिंट त्रुटि',

  'hr': 'मानव संसाधन',
  'legal': 'कानूनी',
  'finance': 'वित्त',
  'sales': 'बिक्री',
  'admin': 'प्रशासन',
  'career': 'करियर',

  'fillArrow': 'भरें →',
  'comingSoon': 'जल्द आ रहा है',
  'comingSoonTitle': 'यह टेम्पलेट जल्द ही उपलब्ध होगा!',
  'comingSoonMessage': 'हम और अधिक टेम्पलेट जोड़ने पर काम कर रहे हैं।',

  'invoice': 'चालान',
  'receipt': 'रसीद',
  'quotation': 'कोटेशन',
  'purchaseOrder': 'खरीद आदेश',
  'billOfSale': 'विक्रय बिल',
  'expenseReport': 'व्यय रिपोर्ट',
  'nda': 'गोपनीयता समझौता',
  'serviceAgreement': 'सेवा समझौता',
  'freelanceContract': 'फ्रीलांस अनुबंध',
  'rentalAgreement': 'किराया समझौता',
  'nonCompete': 'गैर-प्रतिस्पर्धा समझौता',
  'offerLetter': 'ऑफर लेटर',
  'employmentContract': 'रोजगार अनुबंध',
  'terminationLetter': 'सेवा समाप्ति पत्र',
  'businessProposal': 'व्यावसायिक प्रस्ताव',
  'meetingMinutes': 'बैठक कार्यवृत्त',
  'resume': 'रिज़्यूमे / CV',
  'disclosingParty': 'जानकारी प्रकट करने वाला पक्ष',
  'receivingParty': 'जानकारी प्राप्त करने वाला पक्ष',
  'effectiveDate': 'प्रभावी तिथि',
  'duration': 'अवधि',
  'governingState': 'शासकीय राज्य',

  'ndaTitle': 'गोपनीयता समझौता',
  'ndaIntro1': 'यह समझौता दिनांक',
  'ndaIntro2': 'के बीच किया गया है',
  'ndaIntro3': '("जानकारी प्रकट करने वाला पक्ष") और',
  'ndaIntro4': '("जानकारी प्राप्त करने वाला पक्ष")।',

  'clause1': '1. गोपनीय जानकारी।',
  'clause2': '2. उपयोग न करना।',
  'clause3': '3. अवधि। दायित्व जारी रहेंगे',
  'clause4': '4. शासकीय कानून। यह समझौता निम्नलिखित राज्य के कानूनों द्वारा शासित होगा',

  'signature': 'हस्ताक्षर',

  'candidateName': 'उम्मीदवार का नाम',
  'jobTitle': 'पद का नाम',
  'startDate': 'कार्य प्रारंभ तिथि',
  'offerDeadline': 'ऑफ़र स्वीकार करने की अंतिम तिथि',
  'compensation': 'वेतन / पारिश्रमिक',

  'dear': 'प्रिय',

  'offerLetterBody1': 'हमें आपको निम्न पद की पेशकश करते हुए प्रसन्नता हो रही है',
  'offerLetterBody2': 'में',
  'offerLetterDeadline': 'कृपया इस प्रस्ताव को निम्न तिथि तक स्वीकार करें',

  'position': 'पद',
  'authorizedSignature': 'अधिकृत हस्ताक्षर',
  'acceptance': 'स्वीकृति',

  'buyer': 'खरीदार',
  'vendor': 'विक्रेता',
  'poNumber': 'खरीद आदेश संख्या',
  'delivery': 'डिलीवरी',
  'paymentTerms': 'भुगतान की शर्तें',

  'items': 'आइटम',
  'addItem': 'आइटम जोड़ें',
  'item': 'आइटम',
  'price': 'मूल्य',

  'purchaseOrderTitle': 'खरीद आदेश',
  'terms': 'शर्तें',

  'serviceProvider': 'सेवा प्रदाता',
  'client': 'ग्राहक',
  'servicesDescription': 'सेवाओं का विवरण',
  'feeMonthly': 'शुल्क (मासिक)',
  'endDate': 'समाप्ति तिथि',

  'serviceAgreementTitle': 'सेवा समझौता',
  'serviceAgreementIntro1': 'यह समझौता',
  'serviceAgreementIntro2': '("प्रदाता") और',
  'serviceAgreementIntro3': '("ग्राहक") के बीच है।',

  'services': 'सेवाएँ',
  'fee': 'शुल्क',
  'term': 'अवधि',
  'perMonth': 'माह',

  'receiptNumber': 'रसीद संख्या',
  'receiptTitle': 'रसीद',
  'thankYou': 'धन्यवाद!',

  'quotationNumber': 'कोटेशन संख्या',
  'validUntil': 'मान्य तिथि तक',
  'quotationTitle': 'कोटेशन',

  'seller': 'विक्रेता',
  'itemDescription': 'वस्तु / संपत्ति का विवरण',
  'salePrice': 'बिक्री मूल्य',
  'dateOfSale': 'बिक्री की तिथि',

  'billOfSaleTitle': 'बिक्री बिल',
  'billOfSaleIntro1': 'यह बिक्री बिल दिनांक',
  'billOfSaleIntro2': 'को',
  'billOfSaleIntro3': '("विक्रेता") और',
  'billOfSaleIntro4': '("खरीदार") के बीच बनाया गया है।',

  'billOfSaleAmount': 'कुल राशि',
  'billOfSaleTransfer':
      'विक्रेता निम्नलिखित संपत्ति को खरीदार को बेचता और हस्तांतरित करता है:',

  'sellerSignature': 'विक्रेता के हस्ताक्षर',
  'buyerSignature': 'खरीदार के हस्ताक्षर',

  'employee': 'कर्मचारी',
  'department': 'विभाग',

  'expenses': 'व्यय',
  'addExpense': 'व्यय जोड़ें',
  'amount': 'राशि',

  'expenseReportTitle': 'व्यय रिपोर्ट',

  'freelancer': 'फ्रीलांसर',
  'scopeOfWork': 'कार्य का दायरा',
  'hourlyRateFixed': 'प्रति घंटा दर / निश्चित शुल्क',
  'deadline': 'समय सीमा',

  'freelanceContractTitle': 'फ्रीलांस अनुबंध',
  'freelanceContractIntro1': 'यह समझौता',
  'freelanceContractIntro2': '("फ्रीलांसर") और',
  'freelanceContractIntro3': '("ग्राहक") के बीच है।',
  'landlord': 'मकान मालिक',
  'tenant': 'किरायेदार',
  'propertyAddress': 'संपत्ति का पता',
  'monthlyRent': 'मासिक किराया',

  'rentalAgreementTitle': 'आवासीय किराया समझौता',
  'rentalAgreementIntro1': 'यह समझौता',
  'rentalAgreementIntro2': '("मकान मालिक") और',
  'rentalAgreementIntro3': '("किरायेदार") के बीच संपत्ति के लिए किया गया है',

  'additionalTerms': 'अतिरिक्त शर्तें: किरायेदार संपत्ति का रखरखाव करेगा और उपयोगिता बिलों का भुगतान करेगा।',

  'geographicRadius': 'भौगोलिक क्षेत्र',

  'nonCompeteTitle': 'प्रतिस्पर्धा-निषेध समझौता',
  'nonCompeteIntro1': 'यह प्रतिस्पर्धा-निषेध समझौता',
  'nonCompeteIntro2': '("कंपनी") और',
  'nonCompeteIntro3': '("कर्मचारी") के बीच है।',

  'nonCompeteBody1': 'एक अवधि के लिए',
  'nonCompeteBody2': 'के भीतर',
  'nonCompeteBody3':
      'कंपनी के व्यवसाय क्षेत्र में, कर्मचारी किसी भी प्रतिस्पर्धी व्यवसाय में शामिल नहीं होगा।',

  'representative': 'प्रतिनिधि',
  'employer': 'नियोक्ता',
  'annualSalary': 'वार्षिक वेतन',

  'employmentContractTitle': 'रोजगार अनुबंध',
  'employmentContractIntro1': 'यह रोजगार अनुबंध',
  'employmentContractIntro2': '("नियोक्ता") और',
  'employmentContractIntro3': '("कर्मचारी") के बीच किया गया है।',

  'standardTerms': 'मानक शर्तें: 40 घंटे/सप्ताह, 15 दिन सवैतनिक अवकाश।',

  'reasonTermination': 'समाप्ति का कारण',

  'terminationLetterTitle': 'सेवा समाप्ति पत्र',
  'terminationLetterBody1': 'यह पत्र आपके रोजगार की समाप्ति की पुष्टि करता है जो',
  'terminationLetterBody2': 'से प्रभावी है',

  'reason': 'कारण',
  'terminationLetterFooter':
      'कृपया सभी कंपनी संपत्ति वापस करें। आपका अंतिम वेतन जल्द ही जारी किया जाएगा।',

  'projectTitle': 'प्रोजेक्ट / प्रस्ताव का शीर्षक',
  'estimatedBudget': 'अनुमानित बजट',
  'timeline': 'समयसीमा',

  'businessProposalTitle': 'व्यावसायिक प्रस्ताव',
  'preparedFor': 'के लिए तैयार किया गया',
  'preparedBy': 'द्वारा तैयार किया गया',
  'project': 'प्रोजेक्ट',
  'budget': 'बजट',

  'businessProposalBody':
      'हम यह प्रस्ताव प्रस्तुत करते हुए प्रसन्न हैं। हमारी टीम सहमत समयसीमा में उच्च गुणवत्ता वाला कार्य प्रदान करेगी।',

  'attendees': 'उपस्थित लोग',
  'minutesDecisions': 'कार्यवृत्त / निर्णय',

  'meetingMinutesTitle': 'बैठक कार्यवृत्त',
  'minutes': 'कार्यवृत्त',

  'fresher': 'नवीन',
  'experienced': 'अनुभवी',

  'photoOptional': 'फोटो (वैकल्पिक)',
  'photoHint': 'रेज़्यूमे में दिखेगा',

  'personalDetails': 'व्यक्तिगत विवरण',
  'fullName': 'पूरा नाम',
  'jobTitleOptional': 'पद (वैकल्पिक)',
  'email': 'ईमेल',
  'phone': 'फ़ोन',
  'location': 'स्थान',
  'linkedinPortfolio': 'लिंक्डइन / पोर्टफोलियो',

  'professionalSummary': 'व्यावसायिक सारांश',

  'education': 'शिक्षा',
  'degree': 'डिग्री',
  'institution': 'संस्थान',
  'yearDuration': 'वर्ष / अवधि',
  'gpa': 'जीपीए / प्रतिशत',

  'internships': 'इंटर्नशिप',
  'workExperience': 'कार्य अनुभव',

  'internship': 'इंटर्नशिप',
  'experience': 'अनुभव',
  'titleRole': 'पद / भूमिका',
  'descriptionBullets': 'विवरण (बुलेट पॉइंट्स)',

  'addInternship': 'इंटर्नशिप जोड़ें',
  'addWorkExperience': 'कार्य अनुभव जोड़ें',

  'projects': 'प्रोजेक्ट्स',
  'projectName': 'प्रोजेक्ट का नाम',
  'technologiesUsed': 'उपयोग की गई तकनीकें',
  'addProject': 'प्रोजेक्ट जोड़ें',

  'skills': 'कौशल',
  'addSkill': 'कौशल जोड़ें',
  'tech': 'तकनीक',

  'certifications': 'प्रमाणपत्र',
  'certification': 'प्रमाणपत्र',
  'certificationName': 'प्रमाणपत्र का नाम',
  'issuingOrg': 'जारी करने वाला संगठन',
  'year': 'वर्ष',
  'addCertification': 'प्रमाणपत्र जोड़ें',

  'achievements': 'उपलब्धियाँ',
  'achievementHint': 'उपलब्धि',
  'addAchievement': 'उपलब्धि जोड़ें',

  'generatePdf': 'PDF बनाएँ',
  'generating': 'बनाया जा रहा है...',

  'single': 'एकल',
  'idCard': 'पहचान पत्र',
  'search': 'खोजें',
  'noResults': 'कोई परिणाम नहीं मिला',
  'selectAll': 'सभी चुनें',
  'deselectAll': 'सभी हटाएं',
  'refresh': 'रीफ्रेश',
  'next': 'अगला',
  'previous': 'पिछला',
  'closeApp': 'ऐप बंद करें',
};

  // ==================== TELUGU (Placeholder – replace with actual Telugu) ====================
  static const Map<String, String> _te = {
  'appName': 'DocSign',
  'pro': 'PRO',
  'openPdf': 'PDF తెరవండి',
  'home': 'హోమ్',
  'recent': 'ఇటీవలి',
  'templates': 'టెంప్లేట్లు',
  'scanner': 'స్కానర్',
  'createPdf': 'PDF సృష్టించండి',
  'pdfTools': 'PDF సాధనాలు',
  'settings': 'సెట్టింగులు',
  'files': 'ఫైళ్లు',
  'newDoc': 'కొత్త పత్రం',
  'cancel': 'రద్దు',
  'save': 'సేవ్ చేయండి',
  'done': 'పూర్తైంది',
  'yes': 'అవును',
  'no': 'కాదు',
  'clear': 'తొలగించు',
  'delete': 'డిలీట్ చేయండి',
  'remove': 'తీసివేయండి',
  'edit': 'సవరించు',
  'share': 'పంచుకోండి',
  'print': 'ప్రింట్',
  'export': 'ఎగుమతి',
  'download': 'డౌన్‌లోడ్',
  'upload': 'అప్‌లోడ్',
  'change': 'మార్చు',
  'add': 'జోడించు',
  'retry': 'మళ్లీ ప్రయత్నించండి',
  'error': 'లోపం',
  'processing': 'ప్రాసెస్ అవుతోంది...',
  'loading': 'లోడ్ అవుతోంది...',
  'fieldRequired': 'ఈ ఫీల్డ్ తప్పనిసరి',
  'validEmail': 'చెల్లుబాటు అయ్యే ఇమెయిల్ నమోదు చేయండి',
  'redacted': 'దాచబడింది',
  'addNoteTitle': 'గమనిక జోడించండి',
  'addNoteHint': 'మీ గమనికను టైప్ చేయండి…',
  'clauseLabelTitle': 'క్లాజ్ లేబుల్',
  'dashboard': 'డ్యాష్‌బోర్డ్',
  'dashboardSubtitle': 'పత్రాలను తెరవండి, సంతకం చేయండి మరియు నిర్వహించండి',
  'pdfToolsCount': '60+',
  'templatesCount': '16',
  'freeForever': '100% ఉచితం',
  'offlinePrivate': '100% ప్రైవేట్',
  'quickActions': 'త్వరిత చర్యలు',
  'scan': 'స్కాన్',
  'templatesLabel': 'టెంప్లేట్లు',
  'compare': 'పోల్చండి',
  'recentFiles': 'ఇటీవలి ఫైళ్లు',
  'dropZoneHint': 'మీ PDF ను ఇక్కడ డ్రాప్ చేయండి లేదా బ్రౌజ్ చేయడానికి క్లిక్ చేయండి',
  'dropZoneSubHint': 'పాస్‌వర్డ్ రక్షిత PDFలకు మద్దతు ఉంది',
  'noRecentFiles': 'ఇటీవలి ఫైళ్లు లేవు',
  'documents': 'పత్రాలు',
  'document': 'పత్రం',
  'removeFromRecents': 'ఇటీవలివి నుండి తొలగించాలా?',
  'removeFromRecentsMessage':
      'ఇది జాబితా నుండి మాత్రమే తొలగిస్తుంది, ఫైల్‌ను కాదు.',
  'removedFromRecents': 'ఇటీవలివి నుండి తొలగించబడింది',
  'openAnyFile': 'ఏ ఫైల్‌నైనా తెరవండి',
  'saveCancelled': 'సేవ్ రద్దు చేయబడింది: ఫోల్డర్ ఎంపిక చేయలేదు',
  'savedAt': 'సేవ్ చేయబడింది: ',
  'invalidFilePath': 'చెల్లని ఫైల్ మార్గం',
  'loadingPdf': 'PDF లోడ్ అవుతోంది...',
  'aboutDocSign': 'DocSign గురించి',
  'versionOffline': 'వెర్షన్ 2.0 · 100% ఆఫ్‌లైన్',
  'privacyPolicy': 'గోప్యతా విధానం',
  'noDataCollected': 'డేటా సేకరించబడలేదు',
  'chooseSaveLocation': 'సేవ్ చేయడానికి స్థానం ఎంచుకోండి',
  'downloaded': 'డౌన్‌లోడ్ అయింది',
  'savedAs': 'ఈ పేరుతో సేవ్ చేయబడింది',
  'savedTo': 'ఇక్కడ సేవ్ చేయబడింది',
  'documentScanner': 'పత్ర స్కానర్',
  'clearedAllPages': 'అన్ని పేజీలు తొలగించబడ్డాయి',
  'notAvailableOnWeb': 'వెబ్‌లో అందుబాటులో లేదు',
  'scanWebMessage':
      'పత్ర స్కానింగ్ కోసం కెమెరా ఉన్న నిజమైన పరికరం అవసరం.\n\nదయచేసి మొబైల్ యాప్ ఉపయోగించండి లేదా గ్యాలరీ నుండి చిత్రాలను అప్‌లోడ్ చేయండి.',
  'ok': 'సరే',
  'scanningError': 'స్కానింగ్ లోపం',
  'unexpectedError': 'అనుకోని లోపం సంభవించింది',
  'galleryError': 'గ్యాలరీ లోపం',
  'savePdfAs': 'PDF ను ఇలా సేవ్ చేయండి',
  'enterFileName': 'ఫైల్ పేరు నమోదు చేయండి',
  'createPdfButton': 'PDF సృష్టించండి',
  'clearAll': 'అన్నీ తొలగించండి',
  'scanDocumentsTitle': 'పత్రాలను స్కాన్ చేయండి',
  'scanDocumentsSubtitle':
      'మీ కెమెరాతో పేజీలను క్యాప్చర్ చేయండి లేదా గ్యాలరీ నుండి అప్‌లోడ్ చేసి\nప్రొఫెషనల్ PDF పత్రాన్ని సృష్టించండి',
  'bw': 'నలుపు & తెలుపు',
  'batch': 'బ్యాచ్',
  'hd': 'HD',
  'extractText': 'పాఠ్యాన్ని వెలికితీయండి',
  'gallery': 'గ్యాలరీ',
  'page': 'పేజీ',
  'setCategory': 'వర్గాన్ని సెట్ చేయండి',
  'categoryUncategorized': 'వర్గీకరించని',
  'categoryDocument': 'పత్రం',
  'categoryReceipt': 'రసీదు',
  'categoryInvoice': 'ఇన్వాయిస్',
  'categoryIdCard': 'గుర్తింపు కార్డు',
  'categoryContract': 'ఒప్పందం',
  'categoryOther': 'ఇతర',
  'extractedText': 'వెలికితీసిన పాఠ్యం',
  'close': 'మూసివేయి',
  'copy': 'కాపీ',
  'textCopied': 'పాఠ్యం క్లిప్‌బోర్డ్‌కు కాపీ చేయబడింది',
  'noTextFound': 'ఈ చిత్రంలో పాఠ్యం కనుగొనబడలేదు.',
  'ocrError': 'OCR లోపం',
  'addAtLeastOnePage': 'కనీసం ఒక పేజీ జోడించండి',
  'imageCorrupted': 'చిత్ర డేటా దెబ్బతిన్నది',
  'merge': 'విలీనం చేయండి',
  'extract': 'వెలికితీయండి',
  'rotate': 'తిప్పండి',
  'watermark': 'వాటర్‌మార్క్',
  'duplicate': 'నకలు',
  'qrCode': 'QR కోడ్',
  'cannotOpenFile': 'ఫైల్‌ను తెరవలేము',
  'maxPages': 'గరిష్ట పేజీలు',
  'largeDocument': 'పెద్ద పత్రం',
  'pages': 'పేజీలు',
  'mayBeSlow': 'నెమ్మదిగా ఉండవచ్చు',
  'continue_': 'కొనసాగించండి',
  'merging': 'విలీనం అవుతోంది...',
  'extracting': 'వెలికితీయబడుతోంది...',
  'rotating': 'తిప్పబడుతోంది...',
  'watermarking': 'వాటర్‌మార్క్ జోడించబడుతోంది...',
  'duplicating': 'నకలు చేయబడుతోంది...',
  'addingQr': 'QR జోడించబడుతోంది...',
  'selectPages': 'పేజీలను ఎంచుకోండి',
  'rotateFailed': 'తిప్పడం విఫలమైంది',
  'watermarkHint': 'ఉదా: గోప్యమైనది',
  'textColor': 'అక్షర రంగు:',
  'apply': 'వర్తించు:',
  'all': 'అన్నీ',
  'selected': 'ఎంచుకున్నవి',
  'qrHint': 'URL లేదా చెల్లింపు లింక్',
  'generate': 'సృష్టించండి',
  'noPdfLoaded': 'PDF లోడ్ చేయబడలేదు',
  'passwordProtected': 'పాస్‌వర్డ్ రక్షితం',
  'enterPassword': 'పాస్‌వర్డ్ నమోదు చేయండి',
  'open': 'తెరవండి',
  'openAnotherDocument': 'మీరు మరో పత్రాన్ని తెరవాలనుకుంటున్నారా?',
  'saveAs': 'ఇలా సేవ్ చేయండి',
  'readModeScroll': 'చదివే మోడ్ — నావిగేట్ చేయడానికి స్క్రోల్ చేయండి',
  'zoomModePinch': 'జూమ్ మోడ్ — జూమ్ చేయడానికి పించ్ చేయండి',
  'readMode': 'చదివే మోడ్',
  'zoomMode': 'జూమ్ మోడ్',
  'tapToPlaceSignature': 'సంతకం ఉంచడానికి పేజీపై ట్యాప్ చేయండి',
  'tapToPlaceInitials': 'ఇనిషియల్స్ ఉంచడానికి పేజీపై ట్యాప్ చేయండి',
  'zoomIn': 'జూమ్ చేయండి',
  'zoomOut': 'జూమ్ తగ్గించండి',
  'resetZoom': 'జూమ్ రీసెట్ చేయండి',
  'undo': 'రద్దు చేయండి',
  'darkMode': 'డార్క్ మోడ్',
  'thumbnails': 'థంబ్‌నెయిల్స్',
  'textTool': 'పాఠ్యం',
  'noteTool': 'గమనిక',
  'highlightTool': 'హైలైట్',
  'underlineTool': 'అండర్‌లైన్',
  'strikeTool': 'గీత వేయండి',
  'drawTool': 'గీయండి',
  'redactTool': 'దాచండి',
  'clauseTool': 'క్లాజ్ బుక్‌మార్క్',
  'tools': 'మరిన్ని సాధనాలు',
  'signTool': 'సంతకం',
  'initialsTool': 'ఇనిషియల్స్',
  'slots': 'సంతకం స్థానాలు',
  'audit': 'ఆడిట్ ట్రైల్',
  'profile': 'సంతకం చేసే వ్యక్తి ప్రొఫైల్',
  'tabEdit': 'సవరించు',
  'tabAnnotate': 'వ్యాఖ్యానించు',
  'tabFillSign': 'పూరించండి & సంతకం చేయండి',
  'tabAll': 'అన్నీ',
  'highlight': 'హైలైట్',
  'underline': 'అండర్‌లైన్',
  'strike': 'గీత వేయండి',
  'draw': 'గీయండి',
  'note': 'గమనిక',
  'redact': 'దాచండి',
  'clause': 'క్లాజ్',
  'text': 'పాఠ్యం',
  'sign': 'సంతకం',
  'initials': 'ఇనిషియల్స్',
  'saveFailed': 'సేవ్ చేయడం విఫలమైంది',
  'shareFailed': 'పంచుకోవడం విఫలమైంది',
  'printError': 'ప్రింట్ లోపం',

  'hr': 'మానవ వనరులు',
  'legal': 'న్యాయ',
  'finance': 'ఆర్థిక',
  'sales': 'అమ్మకాలు',
  'admin': 'పరిపాలన',
  'career': 'వృత్తి',

  'fillArrow': 'పూరించండి →',
  'comingSoon': 'త్వరలో వస్తుంది',
  'comingSoonTitle': 'ఈ టెంప్లేట్ త్వరలో అందుబాటులోకి వస్తుంది!',
  'comingSoonMessage': 'మరిన్ని టెంప్లేట్‌లను జోడించడానికి మేము కృషి చేస్తున్నాము.',

  'invoice': 'ఇన్వాయిస్',
  'receipt': 'రసీదు',
  'quotation': 'ధర ప్రతిపాదన',
  'purchaseOrder': 'కొనుగోలు ఆర్డర్',
  'billOfSale': 'అమ్మకపు బిల్లు',
  'expenseReport': 'ఖర్చుల నివేదిక',
  'nda': 'గోప్యతా ఒప్పందం',
  'serviceAgreement': 'సేవా ఒప్పందం',
  'freelanceContract': 'ఫ్రీలాన్స్ ఒప్పందం',
  'rentalAgreement': 'అద్దె ఒప్పందం',
  'nonCompete': 'పోటీ నిరోధక ఒప్పందం',
  'offerLetter': 'ఉద్యోగ ఆఫర్ లేఖ',
  'employmentContract': 'ఉద్యోగ ఒప్పందం',
  'terminationLetter': 'ఉద్యోగ విరమణ లేఖ',
  'businessProposal': 'వ్యాపార ప్రతిపాదన',
  'meetingMinutes': 'సమావేశ నివేదిక',
  'resume': 'రెజ్యూమే / CV',

  'currency': 'కరెన్సీ',
  'from': 'నుండి',
  'to': 'వరకు',
  'fromAddress': 'పంపిన వారి చిరునామా',
  'clientAddress': 'కస్టమర్ చిరునామా',
  'invoiceNumber': 'ఇన్వాయిస్ నం.',
  'issueDate': 'జారీ తేదీ',
  'dueDate': 'చెల్లింపు గడువు తేదీ',
  'lineItems': 'అంశాల జాబితా',
  'addLineItem': 'అంశం జోడించండి',
  'subtotal': 'ఉపమొత్తం',
  'tax': 'పన్ను (10%)',
  'total': 'మొత్తం',
  'qrOptional': 'QR కోడ్ (ఐచ్ఛికం)',
  'notesTerms': 'గమనికలు / నిబంధనలు',
  'companyLogo': 'కంపెనీ లోగో',
  'logoHint': 'ఇన్వాయిస్ కుడి పైభాగంలో కనిపిస్తుంది',
  'billTo': 'బిల్ పంపవలసిన వ్యక్తి',
  'description': 'వివరణ',
  'qty': 'పరిమాణం',
  'unitPrice': 'యూనిట్ ధర',
  'scanToPay': 'చెల్లించడానికి స్కాన్ చేయండి',
  'notes': 'గమనికలు:',
  'due': 'గడువు',
  'date': 'తేదీ',
  'company': 'కంపెనీ',
  'rate': 'రేటు (\$)',
  'disclosingParty': 'వివరాలు వెల్లడించే పక్షం',
  'receivingParty': 'వివరాలు స్వీకరించే పక్షం',
  'effectiveDate': 'అమల్లోకి వచ్చే తేదీ',
  'duration': 'వ్యవధి',
  'governingState': 'పాలనా రాష్ట్రం',

  'ndaTitle': 'గోప్యతా ఒప్పందం',
  'ndaIntro1': 'ఈ ఒప్పందం తేదీ',
  'ndaIntro2': 'మధ్య కుదుర్చబడింది',
  'ndaIntro3': '("వివరాలు వెల్లడించే పక్షం") మరియు',
  'ndaIntro4': '("వివరాలు స్వీకరించే పక్షం").',

  'clause1': '1. గోప్య సమాచారం.',
  'clause2': '2. వినియోగం నిషేధం.',
  'clause3': '3. వ్యవధి. బాధ్యతలు కొనసాగేది',
  'clause4': '4. పాలనా చట్టం. ఈ ఒప్పందం చట్టాల ప్రకారం నిర్వహించబడుతుంది',

  'signature': 'సంతకం',

  'candidateName': 'అభ్యర్థి పేరు',
  'jobTitle': 'ఉద్యోగ హోదా',
  'startDate': 'ప్రారంభ తేదీ',
  'offerDeadline': 'ఆఫర్ గడువు',
  'compensation': 'వేతనం',
  'dear': 'ప్రియమైన',

  'offerLetterBody1': 'మీకు ఈ పదవిని అందిస్తున్నందుకు మేము సంతోషిస్తున్నాము',
  'offerLetterBody2': 'వద్ద',
  'offerLetterDeadline': 'దయచేసి ఈ ఆఫర్‌ను ఈ తేదీకి ముందు అంగీకరించండి',
  'position': 'పదవి',
  'authorizedSignature': 'అధికారిక సంతకం',
  'acceptance': 'అంగీకారం',

  'buyer': 'కొనుగోలుదారు',
  'vendor': 'విక్రేత',
  'poNumber': 'కొనుగోలు ఆర్డర్ నం.',
  'delivery': 'డెలివరీ',
  'paymentTerms': 'చెల్లింపు నిబంధనలు',

  'items': 'అంశాలు',
  'addItem': 'అంశం జోడించండి',
  'item': 'అంశం',
  'price': 'ధర',

  'purchaseOrderTitle': 'కొనుగోలు ఆర్డర్',
  'terms': 'నిబంధనలు',

  'serviceProvider': 'సేవా ప్రదాత',
  'client': 'ఖాతాదారు',
  'servicesDescription': 'సేవల వివరణ',
  'feeMonthly': 'ఫీజు (నెలకు)',
  'endDate': 'ముగింపు తేదీ',

  'serviceAgreementTitle': 'సేవా ఒప్పందం',
  'serviceAgreementIntro1': 'ఈ ఒప్పందం',
  'serviceAgreementIntro2': '("సేవా ప్రదాత") మరియు',
  'serviceAgreementIntro3': '("ఖాతాదారు") మధ్య కుదుర్చబడింది.',

  'services': 'సేవలు',
  'fee': 'ఫీజు',
  'term': 'కాలం',
  'perMonth': 'నెలకు',

  'receiptNumber': 'రసీదు నం.',
  'receiptTitle': 'రసీదు',
  'thankYou': 'ధన్యవాదాలు!',

  'quotationNumber': 'కొటేషన్ నం.',
  'validUntil': 'చెల్లుబాటు అయ్యే తేదీ వరకు',
  'quotationTitle': 'ధర ప్రతిపాదన',

  'seller': 'విక్రేత',
  'itemDescription': 'వస్తువు/ఆస్తి వివరణ',
  'salePrice': 'అమ్మకపు ధర',
  'dateOfSale': 'అమ్మకపు తేదీ',

  'billOfSaleTitle': 'అమ్మకపు బిల్లు',
  'billOfSaleIntro1': 'ఈ అమ్మకపు బిల్లు తేదీన రూపొందించబడింది',
  'billOfSaleIntro2': 'మధ్య',
  'billOfSaleIntro3': '("విక్రేత") మరియు',
  'billOfSaleIntro4': '("కొనుగోలుదారు").',

  'billOfSaleAmount': 'మొత్తం',
  'billOfSaleTransfer':
      'కు బదులుగా విక్రేత క్రింది ఆస్తిని కొనుగోలుదారునికి బదిలీ చేస్తాడు:',

  'sellerSignature': 'విక్రేత సంతకం',
  'buyerSignature': 'కొనుగోలుదారు సంతకం',

  'employee': 'ఉద్యోగి',
  'department': 'విభాగం',

  'expenses': 'ఖర్చులు',
  'addExpense': 'ఖర్చు జోడించండి',
  'amount': 'మొత్తం',

  'expenseReportTitle': 'ఖర్చుల నివేదిక',

  'freelancer': 'ఫ్రీలాన్సర్',
  'scopeOfWork': 'పని పరిధి',
  'hourlyRateFixed': 'గంటకు రేటు / స్థిర ఫీజు',
  'deadline': 'గడువు తేదీ',

  'freelanceContractTitle': 'ఫ్రీలాన్స్ ఒప్పందం',
  'freelanceContractIntro1': 'ఈ ఒప్పందం',
  'freelanceContractIntro2': '("ఫ్రీలాన్సర్") మరియు',
  'freelanceContractIntro3': '("ఖాతాదారు") మధ్య కుదుర్చబడింది.',

  'landlord': 'ఇల్లు యజమాని',
  'tenant': 'అద్దెదారు',
  'propertyAddress': 'ఆస్తి చిరునామా',
  'monthlyRent': 'నెలవారీ అద్దె',

  'rentalAgreementTitle': 'నివాస అద్దె ఒప్పందం',
  'rentalAgreementIntro1': 'ఈ ఒప్పందం',
  'rentalAgreementIntro2': '("ఇల్లు యజమాని") మరియు',
  'rentalAgreementIntro3': '("అద్దెదారు") మధ్య, ఈ ఆస్తికి సంబంధించినది',

  'additionalTerms':
      'అదనపు నిబంధనలు: అద్దెదారు ఆస్తిని సంరక్షించాలి మరియు యుటిలిటీ బిల్లులు చెల్లించాలి.',

  'geographicRadius': 'భౌగోళిక పరిధి',

  'nonCompeteTitle': 'పోటీ నిరోధక ఒప్పందం',
  'nonCompeteIntro1': 'ఈ పోటీ నిరోధక ఒప్పందం',
  'nonCompeteIntro2': '("కంపెనీ") మరియు',
  'nonCompeteIntro3': '("ఉద్యోగి") మధ్య కుదుర్చబడింది.',

  'nonCompeteBody1': 'కాలవ్యవధి',
  'nonCompeteBody2': 'పరిధిలో',
  'nonCompeteBody3':
      'కంపెనీ వ్యాపారానికి పోటీగా ఉండే వ్యాపారంలో ఉద్యోగి పాల్గొనకూడదని అంగీకరిస్తాడు.',

  'representative': 'ప్రతినిధి',
  'employer': 'యజమాని',
  'annualSalary': 'వార్షిక వేతనం',

  'employmentContractTitle': 'ఉద్యోగ ఒప్పందం',
  'employmentContractIntro1': 'ఈ ఉద్యోగ ఒప్పందం',
  'employmentContractIntro2': '("యజమాని") మరియు',
  'employmentContractIntro3': '("ఉద్యోగి") మధ్య కుదుర్చబడింది.',

  'standardTerms':
      'ప్రామాణిక నిబంధనలు: వారానికి 40 గంటలు పని, 15 రోజుల చెల్లింపు సెలవు.',

  'reasonTermination': 'ఉద్యోగ విరమణ కారణం',

  'terminationLetterTitle': 'ఉద్యోగ విరమణ లేఖ',
  'terminationLetterBody1':
      'ఈ లేఖ మీ ఉద్యోగం ముగిసినట్లు ధృవీకరిస్తుంది',
  'terminationLetterBody2': 'ప్రభావిత తేదీ',

  'reason': 'కారణం',

  'terminationLetterFooter':
      'దయచేసి కంపెనీ ఆస్తులను తిరిగి ఇవ్వండి. మీ చివరి వేతనం ప్రాసెస్ చేయబడుతుంది.',
      'projectTitle': 'ప్రాజెక్ట్ / ప్రతిపాదన శీర్షిక',
  'estimatedBudget': 'అంచనా బడ్జెట్',
  'timeline': 'కాలక్రమం',

  'businessProposalTitle': 'వ్యాపార ప్రతిపాదన',
  'preparedFor': 'ఎవరికి సిద్ధం చేయబడింది',
  'preparedBy': 'సిద్ధం చేసినవారు',
  'project': 'ప్రాజెక్ట్',
  'budget': 'బడ్జెట్',

  'businessProposalBody':
      'ఈ ప్రతిపాదనను మీకు అందించడానికి మేము సంతోషిస్తున్నాము. మా బృందం అంగీకరించిన కాలపట్టికలో అధిక నాణ్యత గల ఫలితాలను అందిస్తుంది.',

  'attendees': 'హాజరైనవారు',
  'minutesDecisions': 'నిర్ణయాలు / సమావేశ నోట్స్',

  'meetingMinutesTitle': 'సమావేశ నివేదిక',
  'minutes': 'నోట్స్',

  'fresher': 'ఫ్రెషర్',
  'experienced': 'అనుభవం ఉన్నవారు',

  'photoOptional': 'ఫోటో (ఐచ్ఛికం)',
  'photoHint': 'రెజ్యూమేలో కనిపిస్తుంది',

  'personalDetails': 'వ్యక్తిగత వివరాలు',

  'fullName': 'పూర్తి పేరు',
  'jobTitleOptional': 'ఉద్యోగ హోదా (ఐచ్ఛికం)',
  'email': 'ఇమెయిల్',
  'phone': 'ఫోన్',
  'location': 'స్థానం',
  'linkedinPortfolio': 'లింక్డ్ఇన్ / పోర్ట్‌ఫోలియో',

  'professionalSummary': 'వృత్తిపరమైన సారాంశం',

  'education': 'విద్య',
  'degree': 'డిగ్రీ',
  'institution': 'విద్యాసంస్థ',
  'yearDuration': 'సంవత్సరం / వ్యవధి',
  'gpa': 'GPA / శాతం',

  'internships': 'ఇంటర్న్‌షిప్‌లు',
  'workExperience': 'పని అనుభవం',

  'internship': 'ఇంటర్న్‌షిప్',
  'experience': 'అనుభవం',

  'titleRole': 'హోదా / పాత్ర',
  'descriptionBullets': 'వివరణ (బుల్లెట్ పాయింట్లు)',

  'addInternship': 'ఇంటర్న్‌షిప్ జోడించండి',
  'addWorkExperience': 'పని అనుభవం జోడించండి',

  'projects': 'ప్రాజెక్టులు',
  'projectName': 'ప్రాజెక్ట్ పేరు',
  'technologiesUsed': 'ఉపయోగించిన సాంకేతికతలు',

  'addProject': 'ప్రాజెక్ట్ జోడించండి',

  'skills': 'నైపుణ్యాలు',
  'addSkill': 'నైపుణ్యం జోడించండి',

  'tech': 'సాంకేతికత',

  'certifications': 'సర్టిఫికేషన్లు',
  'certification': 'సర్టిఫికేషన్',
  'certificationName': 'సర్టిఫికేషన్ పేరు',
  'issuingOrg': 'జారీ చేసిన సంస్థ',
  'year': 'సంవత్సరం',

  'addCertification': 'సర్టిఫికేషన్ జోడించండి',

  'achievements': 'సాధనలు',
  'achievementHint': 'సాధన',

  'addAchievement': 'సాధన జోడించండి',

  'generatePdf': 'PDF సృష్టించండి',
  'generating': 'PDF సృష్టించబడుతోంది...',

  'single': 'ఒకటి',
  'idCard': 'గుర్తింపు కార్డు',
  };

  // ==================== FRENCH (Full proper translations) ====================
  static const Map<String, String> _fr = {
    'appName': 'DocSign',
    'pro': 'PRO',
    'openPdf': 'Ouvrir PDF',
    'home': 'Accueil',
    'recent': 'Récents',
    'templates': 'Modèles',
    'scanner': 'Scanner',
    'createPdf': 'Créer PDF',
    'pdfTools': 'Outils PDF',
    'settings': 'Paramètres',
    'files': 'Fichiers',
    'newDoc': 'Nouveau doc.',
    'cancel': 'Annuler',
    'save': 'Enregistrer',
    'done': 'Terminé',
    'yes': 'Oui',
    'no': 'Non',
    'clear': 'Effacer',
    'delete': 'Supprimer',
    'remove': 'Retirer',
    'edit': 'Modifier',
    'share': 'Partager',
    'print': 'Imprimer',
    'export': 'Exporter',
    'download': 'Télécharger',
    'upload': 'Importer',
    'change': 'Changer',
    'add': 'Ajouter',
    'retry': 'Réessayer',
    'error': 'Erreur',
    'processing': 'Traitement...',
    'loading': 'Chargement...',
    'fieldRequired': 'Ce champ est requis',
    'validEmail': 'Entrez une adresse email valide',
    'redacted': 'MASQUÉ',
    'addNoteTitle': 'Ajouter une note',
    'addNoteHint': 'Saisissez votre note…',
    'clauseLabelTitle': 'Étiquette de clause',

    'dashboard': 'Tableau de bord',
    'dashboardSubtitle': 'Ouvrez, signez et gérez des documents',
    'pdfToolsCount': '60+',
    'templatesCount': '16',
    'freeForever': '100% Gratuit',
    'offlinePrivate': '100% Privé',
    'quickActions': 'Actions rapides',
    'scan': 'Scanner',
    'templatesLabel': 'Modèles',
    'compare': 'Comparer',
    'recentFiles': 'Fichiers récents',
    'dropZoneHint': 'Déposez votre PDF ici ou cliquez pour parcourir',
    'dropZoneSubHint': 'Prend en charge les PDF protégés par mot de passe',
    'noRecentFiles': 'Aucun fichier récent',
    'documents': 'documents',
    'document': 'document',
    'removeFromRecents': 'Supprimer des récents ?',
    'removeFromRecentsMessage': 'Cela supprimera seulement l’entrée de la liste, pas le fichier.',
    'removedFromRecents': 'Supprimé des récents',
    'openAnyFile': 'Ouvrir n’importe quel fichier',
    'saveCancelled': 'Enregistrement annulé : aucun dossier sélectionné',
    'savedAt': 'Enregistré : ',
    'invalidFilePath': 'Chemin de fichier invalide',
    'loadingPdf': 'Chargement du PDF...',
    'aboutDocSign': 'À propos de DocSign',
    'versionOffline': 'Version 2.0 · 100% hors ligne',
    'privacyPolicy': 'Politique de confidentialité',
    'noDataCollected': 'Aucune donnée collectée',
    'chooseSaveLocation': 'Choisissez l’emplacement d’enregistrement',
    'downloaded': 'Téléchargé',
    'savedAs': 'Enregistré sous',
    'savedTo': 'Enregistré dans',

    'documentScanner': 'Scanner de documents',
    'clearedAllPages': 'Toutes les pages effacées',
    'notAvailableOnWeb': 'Non disponible sur le web',
    'scanWebMessage': 'La numérisation nécessite un appareil réel avec une caméra.\n\nUtilisez l’application mobile ou importez des images depuis la galerie.',
    'ok': 'OK',
    'scanningError': 'Erreur de numérisation',
    'unexpectedError': 'Une erreur inattendue s’est produite',
    'galleryError': 'Erreur de galerie',
    'savePdfAs': 'Enregistrer le PDF sous',
    'enterFileName': 'Entrez le nom du fichier',
    'createPdfButton': 'Créer le PDF',
    'clearAll': 'Tout effacer',
    'scanDocumentsTitle': 'Numériser des documents',
    'scanDocumentsSubtitle': 'Capturez des pages avec votre appareil photo ou importez depuis la galerie\npour créer un PDF professionnel',
    'bw': 'N&B',
    'batch': 'Lot',
    'hd': 'HD',
    'extractText': 'Extraire le texte',
    'gallery': 'Galerie',
    'page': 'Page',
    'setCategory': 'Définir la catégorie',
    'categoryUncategorized': 'Non catégorisé',
    'categoryDocument': 'Document',
    'categoryReceipt': 'Reçu',
    'categoryInvoice': 'Facture',
    'categoryIdCard': 'Carte d’identité',
    'categoryContract': 'Contrat',
    'categoryOther': 'Autre',
    'extractedText': 'Texte extrait',
    'close': 'Fermer',
    'copy': 'Copier',
    'textCopied': 'Texte copié dans le presse-papier',
    'noTextFound': 'Aucun texte trouvé dans cette image.',
    'ocrError': 'Erreur OCR',
    'addAtLeastOnePage': 'Ajoutez au moins une page',
    'imageCorrupted': 'Données d’image corrompues pour',

    'merge': 'Fusionner',
    'extract': 'Extraire',
    'rotate': 'Pivoter',
    'watermark': 'Filigrane',
    'duplicate': 'Dupliquer',
    'qrCode': 'Code QR',
    'cannotOpenFile': 'Impossible d’ouvrir le fichier',
    'maxPages': 'Pages max',
    'largeDocument': 'Document volumineux',
    'pages': 'pages',
    'mayBeSlow': 'peut être lent',
    'continue_': 'Continuer',
    'merging': 'Fusion...',
    'extracting': 'Extraction...',
    'rotating': 'Rotation...',
    'watermarking': 'Ajout du filigrane...',
    'duplicating': 'Duplication...',
    'addingQr': 'Ajout du QR...',
    'selectPages': 'Sélectionnez des pages',
    'rotateFailed': 'Échec de la rotation',
    'watermarkHint': 'ex. CONFIDENTIEL',
    'textColor': 'Couleur du texte :',
    'apply': 'Appliquer :',
    'all': 'Tout',
    'selected': 'Sélectionné',
    'qrHint': 'URL ou lien de paiement',
    'generate': 'Générer',
    'noPdfLoaded': 'Aucun PDF chargé',

    'passwordProtected': 'Protégé par mot de passe',
    'enterPassword': 'Entrez le mot de passe',
    'open': 'Ouvrir',
    'openAnotherDocument': 'Voulez-vous ouvrir un autre document ?',
    'saveAs': 'Enregistrer sous',
    'readModeScroll': 'Mode lecture — Défilez',
    'zoomModePinch': 'Mode zoom — Pincez pour zoomer',
    'readMode': 'Mode lecture',
    'zoomMode': 'Mode zoom',
    'tapToPlaceSignature': 'Appuyez sur la page pour placer la signature',
    'tapToPlaceInitials': 'Appuyez sur la page pour placer les initiales',
    'zoomIn': 'Zoom avant',
    'zoomOut': 'Zoom arrière',
    'resetZoom': 'Réinitialiser le zoom',
    'undo': 'Annuler',
    'darkMode': 'Mode sombre',
    'thumbnails': 'Vignettes',
    'textTool': 'Texte',
    'noteTool': 'Note',
    'highlightTool': 'Surligner',
    'underlineTool': 'Souligner',
    'strikeTool': 'Barrer',
    'drawTool': 'Dessiner',
    'redactTool': 'Masquer',
    'clauseTool': 'Marque-page de clause',
    'tools': 'Plus d’outils',
    'signTool': 'Signer',
    'initialsTool': 'Initiales',
    'slots': 'Emplacements de signature',
    'audit': 'Piste d’audit',
    'profile': 'Profil du signataire',
    'tabEdit': 'Modifier',
    'tabAnnotate': 'Annoter',
    'tabFillSign': 'Remplir & signer',
    'tabAll': 'Tout',
    'highlight': 'Surligner',
    'underline': 'Souligner',
    'strike': 'Barrer',
    'draw': 'Dessiner',
    'note': 'Note',
    'redact': 'Masquer',
    'clause': 'Clause',
    'text': 'Texte',
    'sign': 'Signer',
    'initials': 'Initiales',
    'saveFailed': 'Échec de l’enregistrement',
    'shareFailed': 'Échec du partage',
    'printError': 'Erreur d’impression',

    'hr': 'RH',
    'legal': 'Juridique',
    'finance': 'Finances',
    'sales': 'Ventes',
    'admin': 'Admin',
    'career': 'Carrière',
    'fillArrow': 'Remplir →',
    'comingSoon': 'Bientôt disponible',
    'comingSoonTitle': 'Ce modèle arrive bientôt !',
    'comingSoonMessage': 'Nous travaillons dur pour ajouter plus de modèles.',
    'invoice': 'Facture',
    'receipt': 'Reçu',
    'quotation': 'Devis',
    'purchaseOrder': 'Bon de commande',
    'billOfSale': 'Acte de vente',
    'expenseReport': 'Rapport de dépenses',
    'nda': 'Accord de confidentialité',
    'serviceAgreement': 'Contrat de services',
    'freelanceContract': 'Contrat freelance',
    'rentalAgreement': 'Contrat de location',
    'nonCompete': 'Non-concurrence',
    'offerLetter': 'Lettre d’offre',
    'employmentContract': 'Contrat de travail',
    'terminationLetter': 'Lettre de licenciement',
    'businessProposal': 'Proposition commerciale',
    'meetingMinutes': 'Compte rendu de réunion',
    'resume': 'CV',
    'currency': 'Devise',
    'from': 'De',
    'to': 'À',
    'fromAddress': 'Adresse de l’émetteur',
    'clientAddress': 'Adresse du client',
    'invoiceNumber': 'N° facture',
    'issueDate': 'Date d’émission',
    'dueDate': 'Date d’échéance',
    'lineItems': 'LIGNES DE DÉTAIL',
    'addLineItem': 'Ajouter une ligne',
    'subtotal': 'Sous-total',
    'tax': 'TVA (10%)',
    'total': 'TOTAL',
    'qrOptional': 'CODE QR (optionnel)',
    'notesTerms': 'Notes / conditions',
    'companyLogo': 'Logo de l’entreprise',
    'logoHint': 'Apparaît en haut à droite de la facture',
    'billTo': 'FACTURER À',
    'description': 'Description',
    'qty': 'Qté',
    'unitPrice': 'Prix unitaire',
    'scanToPay': 'Scannez pour payer',
    'notes': 'Notes :',
    'due': 'Échéance',
    'date': 'Date',
    'company': 'Entreprise',
    'rate': 'Tarif (\$)',
    'disclosingParty': 'Partie divulgatrice',
    'receivingParty': 'Partie réceptrice',
    'effectiveDate': 'Date d’effet',
    'duration': 'Durée',
    'governingState': 'État régulateur',
    'ndaTitle': 'ACCORD DE CONFIDENTIALITÉ',
    'ndaIntro1': 'Le présent Accord est conclu le',
    'ndaIntro2': 'entre',
    'ndaIntro3': '("Partie divulgatrice") et',
    'ndaIntro4': '("Partie réceptrice").',
    'clause1': '1. Informations confidentielles.',
    'clause2': '2. Non-utilisation.',
    'clause3': '3. Durée. Les obligations se poursuivent pendant',
    'clause4': '4. Loi applicable. Le présent Accord est régi par les lois de',
    'signature': 'Signature',
    'candidateName': 'Nom du candidat',
    'jobTitle': 'Poste',
    'startDate': 'Date de début',
    'offerDeadline': 'Date limite de l’offre',
    'compensation': 'Rémunération',
    'dear': 'Cher/Chère',
    'offerLetterBody1': 'Nous avons le plaisir de vous offrir le poste de',
    'offerLetterBody2': 'chez',
    'offerLetterDeadline': 'Veuillez accepter cette offre avant le',
    'position': 'Poste',
    'authorizedSignature': 'Signature autorisée',
    'acceptance': 'Acceptation',
    'buyer': 'Acheteur',
    'vendor': 'Vendeur',
    'poNumber': 'N° de commande',
    'delivery': 'Livraison',
    'paymentTerms': 'Conditions de paiement',
    'items': 'ARTICLES',
    'addItem': 'Ajouter un article',
    'item': 'Article',
    'price': 'Prix',
    'purchaseOrderTitle': 'BON DE COMMANDE',
    'terms': 'Conditions',
    'serviceProvider': 'Prestataire de services',
    'client': 'Client',
    'servicesDescription': 'Description des services',
    'feeMonthly': 'Frais (mensuels)',
    'endDate': 'Date de fin',
    'serviceAgreementTitle': 'CONTRAT DE SERVICES',
    'serviceAgreementIntro1': 'Le présent Contrat est conclu entre',
    'serviceAgreementIntro2': '("Prestataire") et',
    'serviceAgreementIntro3': '("Client").',
    'services': 'Services',
    'fee': 'Frais',
    'term': 'Durée',
    'perMonth': 'mois',
    'receiptNumber': 'N° de reçu',
    'receiptTitle': 'REÇU',
    'thankYou': 'Merci !',
    'quotationNumber': 'N° de devis',
    'validUntil': 'Valable jusqu’au',
    'quotationTitle': 'DEVIS',
    'seller': 'Vendeur',
    'itemDescription': 'Description de l’article',
    'salePrice': 'Prix de vente',
    'dateOfSale': 'Date de vente',
    'billOfSaleTitle': 'ACTE DE VENTE',
    'billOfSaleIntro1': 'Le présent Acte de vente est établi le',
    'billOfSaleIntro2': 'entre',
    'billOfSaleIntro3': '("Vendeur") et',
    'billOfSaleIntro4': '("Acheteur").',
    'billOfSaleAmount': 'Pour la somme de',
    'billOfSaleTransfer': 'le Vendeur vend et transfère à l’Acheteur le bien suivant :',
    'sellerSignature': 'Signature du vendeur',
    'buyerSignature': 'Signature de l’acheteur',
    'employee': 'Employé',
    'department': 'Département',
    'expenses': 'DÉPENSES',
    'addExpense': 'Ajouter une dépense',
    'amount': 'Montant',
    'expenseReportTitle': 'RAPPORT DE DÉPENSES',
    'freelancer': 'Freelance',
    'scopeOfWork': 'Portée des travaux',
    'hourlyRateFixed': 'Tarif horaire / Forfait',
    'deadline': 'Date limite',
    'freelanceContractTitle': 'CONTRAT FREELANCE',
    'freelanceContractIntro1': 'Le présent Contrat est conclu entre',
    'freelanceContractIntro2': '("Freelance") et',
    'freelanceContractIntro3': '("Client").',
    'landlord': 'Propriétaire',
    'tenant': 'Locataire',
    'propertyAddress': 'Adresse du bien',
    'monthlyRent': 'Loyer mensuel',
    'rentalAgreementTitle': 'CONTRAT DE LOCATION RÉSIDENTIELLE',
    'rentalAgreementIntro1': 'Le présent Contrat est conclu entre',
    'rentalAgreementIntro2': '("Propriétaire") et',
    'rentalAgreementIntro3': '("Locataire") pour le bien situé au',
    'additionalTerms': 'Conditions supplémentaires : Le locataire s’engage à entretenir le bien et à payer les charges.',
    'geographicRadius': 'Rayon géographique',
    'nonCompeteTitle': 'ACCORD DE NON-CONCURRENCE',
    'nonCompeteIntro1': 'Le présent Accord de non-concurrence est conclu entre',
    'nonCompeteIntro2': '("Entreprise") et',
    'nonCompeteIntro3': '("Employé").',
    'nonCompeteBody1': 'Pendant une période de',
    'nonCompeteBody2': 'dans un rayon de',
    'nonCompeteBody3': 'des activités de l’Entreprise, l’Employé s’engage à ne pas exercer d’activité concurrente.',
    'representative': 'Représentant',
    'employer': 'Employeur',
    'annualSalary': 'Salaire annuel',
    'employmentContractTitle': 'CONTRAT DE TRAVAIL',
    'employmentContractIntro1': 'Le présent Contrat de travail est conclu entre',
    'employmentContractIntro2': '("Employeur") et',
    'employmentContractIntro3': '("Employé").',
    'standardTerms': 'Conditions standard : 40 heures/semaine, 15 jours de congés payés.',
    'reasonTermination': 'Motif du licenciement',
    'terminationLetterTitle': 'LETTRE DE LICENCIEMENT',
    'terminationLetterBody1': 'La présente lettre confirme la fin de votre emploi chez',
    'terminationLetterBody2': 'effective au',
    'reason': 'Motif',
    'terminationLetterFooter': 'Veuillez restituer tout le matériel de l’entreprise. Votre dernier salaire sera versé.',
    'projectTitle': 'Titre du projet / de la proposition',
    'estimatedBudget': 'Budget estimé',
    'timeline': 'Calendrier',
    'businessProposalTitle': 'PROPOSITION COMMERCIALE',
    'preparedFor': 'Préparé pour',
    'preparedBy': 'Préparé par',
    'project': 'Projet',
    'budget': 'Budget',
    'businessProposalBody': 'Nous sommes heureux de présenter cette proposition. Notre équipe livrera des résultats de haute qualité dans les délais convenus.',
    'attendees': 'Participants',
    'minutesDecisions': 'Compte rendu / décisions',
    'meetingMinutesTitle': 'COMPTE RENDU DE RÉUNION',
    'minutes': 'Compte rendu',
    'fresher': 'Débutant',
    'experienced': 'Expérimenté',
    'photoOptional': 'Photo (optionnelle)',
    'photoHint': 'Apparaît sur le CV',
    'personalDetails': 'COORDONNÉES',
    'fullName': 'Nom complet',
    'jobTitleOptional': 'Titre (optionnel)',
    'email': 'Email',
    'phone': 'Téléphone',
    'location': 'Localisation',
    'linkedinPortfolio': 'LinkedIn / Portfolio',
    'professionalSummary': 'Résumé professionnel',
    'education': 'FORMATION',
    'degree': 'Diplôme',
    'institution': 'Établissement',
    'yearDuration': 'Année / Durée',
    'gpa': 'Moyenne / Pourcentage',
    'internships': 'STAGES',
    'workExperience': 'EXPÉRIENCE PROFESSIONNELLE',
    'internship': 'Stage',
    'experience': 'Expérience',
    'titleRole': 'Titre / Rôle',
    'descriptionBullets': 'Description (points)',
    'addInternship': 'Ajouter un stage',
    'addWorkExperience': 'Ajouter une expérience',
    'projects': 'PROJETS',
    'projectName': 'Nom du projet',
    'technologiesUsed': 'Technologies utilisées',
    'addProject': 'Ajouter un projet',
    'skills': 'COMPÉTENCES',
    'addSkill': 'Ajouter une compétence',
    'tech': 'Tech',
    'certifications': 'CERTIFICATIONS',
    'certification': 'Certification',
    'certificationName': 'Nom de la certification',
    'issuingOrg': 'Organisme émetteur',
    'year': 'Année',
    'addCertification': 'Ajouter une certification',
    'achievements': 'RÉALISATIONS',
    'achievementHint': 'Réalisation',
    'addAchievement': 'Ajouter une réalisation',
    'generatePdf': 'Générer le PDF',
    'generating': 'Génération...',
    'single': 'Unique',
    'idCard': 'Carte d’identité',
  };

  // Getters – all keys (same as before, full list)
  // (I'm keeping only a few essential getters for brevity; your previous file already had all getters.
  // Make sure every key has a corresponding getter. The ones above are sufficient for common use.)
  String get appName => _strings['appName']!;
  String get pro => _strings['pro']!;
  String get openPdf => _strings['openPdf']!;
  String get home => _strings['home']!;
  String get recent => _strings['recent']!;
  String get templates => _strings['templates']!;
  String get scanner => _strings['scanner']!;
  String get createPdf => _strings['createPdf']!;
  String get pdfTools => _strings['pdfTools']!;
  String get settings => _strings['settings']!;
  String get files => _strings['files']!;
  String get newDoc => _strings['newDoc']!;
  String get cancel => _strings['cancel']!;
  String get save => _strings['save']!;
  String get done => _strings['done']!;
  String get yes => _strings['yes']!;
  String get no => _strings['no']!;
  String get clear => _strings['clear']!;
  String get delete => _strings['delete']!;
  String get remove => _strings['remove']!;
  String get edit => _strings['edit']!;
  String get share => _strings['share']!;
  String get print => _strings['print']!;
  String get export => _strings['export']!;
  String get download => _strings['download']!;
  String get upload => _strings['upload']!;
  String get change => _strings['change']!;
  String get add => _strings['add']!;
  String get retry => _strings['retry']!;
  String get error => _strings['error']!;
  String get processing => _strings['processing']!;
  String get loading => _strings['loading']!;
  String get fieldRequired => _strings['fieldRequired']!;
  String get validEmail => _strings['validEmail']!;
  String get redacted => _strings['redacted']!;
  String get addNoteTitle => _strings['addNoteTitle']!;
  String get addNoteHint => _strings['addNoteHint']!;
  String get clauseLabelTitle => _strings['clauseLabelTitle']!;
  String get dashboard => _strings['dashboard']!;
  String get dashboardSubtitle => _strings['dashboardSubtitle']!;
  String get pdfToolsCount => _strings['pdfToolsCount']!;
  String get templatesCount => _strings['templatesCount']!;
  String get freeForever => _strings['freeForever']!;
  String get offlinePrivate => _strings['offlinePrivate']!;
  String get quickActions => _strings['quickActions']!;
  String get scan => _strings['scan']!;
  String get templatesLabel => _strings['templatesLabel']!;
  String get compare => _strings['compare']!;
  String get recentFiles => _strings['recentFiles']!;
  String get dropZoneHint => _strings['dropZoneHint']!;
  String get dropZoneSubHint => _strings['dropZoneSubHint']!;
  String get noRecentFiles => _strings['noRecentFiles']!;
  String get documents => _strings['documents']!;
  String get document => _strings['document']!;
  String get removeFromRecents => _strings['removeFromRecents']!;
  String get removeFromRecentsMessage => _strings['removeFromRecentsMessage']!;
  String get removedFromRecents => _strings['removedFromRecents']!;
  String get openAnyFile => _strings['openAnyFile']!;
  String get saveCancelled => _strings['saveCancelled']!;
  String get savedAt => _strings['savedAt']!;
  String get invalidFilePath => _strings['invalidFilePath']!;
  String get loadingPdf => _strings['loadingPdf']!;
  String get aboutDocSign => _strings['aboutDocSign']!;
  String get versionOffline => _strings['versionOffline']!;
  String get privacyPolicy => _strings['privacyPolicy']!;
  String get noDataCollected => _strings['noDataCollected']!;
  String get chooseSaveLocation => _strings['chooseSaveLocation']!;
  String get downloaded => _strings['downloaded']!;
  String get savedAs => _strings['savedAs']!;
  String get savedTo => _strings['savedTo']!;
  String get documentScanner => _strings['documentScanner']!;
  String get clearedAllPages => _strings['clearedAllPages']!;
  String get notAvailableOnWeb => _strings['notAvailableOnWeb']!;
  String get scanWebMessage => _strings['scanWebMessage']!;
  String get ok => _strings['ok']!;
  String get scanningError => _strings['scanningError']!;
  String get unexpectedError => _strings['unexpectedError']!;
  String get galleryError => _strings['galleryError']!;
  String get savePdfAs => _strings['savePdfAs']!;
  String get enterFileName => _strings['enterFileName']!;
  String get createPdfButton => _strings['createPdfButton']!;
  String get clearAll => _strings['clearAll']!;
  String get scanDocumentsTitle => _strings['scanDocumentsTitle']!;
  String get scanDocumentsSubtitle => _strings['scanDocumentsSubtitle']!;
  String get bw => _strings['bw']!;
  String get batch => _strings['batch']!;
  String get hd => _strings['hd']!;
  String get extractText => _strings['extractText']!;
  String get gallery => _strings['gallery']!;
  String get page => _strings['page']!;
  String get setCategory => _strings['setCategory']!;
  String get categoryUncategorized => _strings['categoryUncategorized']!;
  String get categoryDocument => _strings['categoryDocument']!;
  String get categoryReceipt => _strings['categoryReceipt']!;
  String get categoryInvoice => _strings['categoryInvoice']!;
  String get categoryIdCard => _strings['categoryIdCard']!;
  String get categoryContract => _strings['categoryContract']!;
  String get categoryOther => _strings['categoryOther']!;
  String get extractedText => _strings['extractedText']!;
  String get close => _strings['close']!;
  String get copy => _strings['copy']!;
  String get textCopied => _strings['textCopied']!;
  String get noTextFound => _strings['noTextFound']!;
  String get ocrError => _strings['ocrError']!;
  String get addAtLeastOnePage => _strings['addAtLeastOnePage']!;
  String get imageCorrupted => _strings['imageCorrupted']!;
  String get merge => _strings['merge']!;
  String get extract => _strings['extract']!;
  String get rotate => _strings['rotate']!;
  String get watermark => _strings['watermark']!;
  String get duplicate => _strings['duplicate']!;
  String get qrCode => _strings['qrCode']!;
  String get cannotOpenFile => _strings['cannotOpenFile']!;
  String get maxPages => _strings['maxPages']!;
  String get largeDocument => _strings['largeDocument']!;
  String get pages => _strings['pages']!;
  String get mayBeSlow => _strings['mayBeSlow']!;
  String get continue_ => _strings['continue_']!;
  String get merging => _strings['merging']!;
  String get extracting => _strings['extracting']!;
  String get rotating => _strings['rotating']!;
  String get watermarking => _strings['watermarking']!;
  String get duplicating => _strings['duplicating']!;
  String get addingQr => _strings['addingQr']!;
  String get selectPages => _strings['selectPages']!;
  String get rotateFailed => _strings['rotateFailed']!;
  String get watermarkHint => _strings['watermarkHint']!;
  String get textColor => _strings['textColor']!;
  String get apply => _strings['apply']!;
  String get all => _strings['all']!;
  String get selected => _strings['selected']!;
  String get qrHint => _strings['qrHint']!;
  String get generate => _strings['generate']!;
  String get noPdfLoaded => _strings['noPdfLoaded']!;
  String get passwordProtected => _strings['passwordProtected']!;
  String get enterPassword => _strings['enterPassword']!;
  String get open => _strings['open']!;
  String get openAnotherDocument => _strings['openAnotherDocument']!;
  String get saveAs => _strings['saveAs']!;
  String get readModeScroll => _strings['readModeScroll']!;
  String get zoomModePinch => _strings['zoomModePinch']!;
  String get readMode => _strings['readMode']!;
  String get zoomMode => _strings['zoomMode']!;
  String get tapToPlaceSignature => _strings['tapToPlaceSignature']!;
  String get tapToPlaceInitials => _strings['tapToPlaceInitials']!;
  String get zoomIn => _strings['zoomIn']!;
  String get zoomOut => _strings['zoomOut']!;
  String get resetZoom => _strings['resetZoom']!;
  String get undo => _strings['undo']!;
  String get darkMode => _strings['darkMode']!;
  String get thumbnails => _strings['thumbnails']!;
  String get textTool => _strings['textTool']!;
  String get noteTool => _strings['noteTool']!;
  String get highlightTool => _strings['highlightTool']!;
  String get underlineTool => _strings['underlineTool']!;
  String get strikeTool => _strings['strikeTool']!;
  String get drawTool => _strings['drawTool']!;
  String get redactTool => _strings['redactTool']!;
  String get clauseTool => _strings['clauseTool']!;
  String get tools => _strings['tools']!;
  String get signTool => _strings['signTool']!;
  String get initialsTool => _strings['initialsTool']!;
  String get slots => _strings['slots']!;
  String get audit => _strings['audit']!;
  String get profile => _strings['profile']!;
  String get tabEdit => _strings['tabEdit']!;
  String get tabAnnotate => _strings['tabAnnotate']!;
  String get tabFillSign => _strings['tabFillSign']!;
  String get tabAll => _strings['tabAll']!;
  String get highlight => _strings['highlight']!;
  String get underline => _strings['underline']!;
  String get strike => _strings['strike']!;
  String get draw => _strings['draw']!;
  String get note => _strings['note']!;
  String get redact => _strings['redact']!;
  String get clause => _strings['clause']!;
  String get text => _strings['text']!;
  String get sign => _strings['sign']!;
  String get initials => _strings['initials']!;
  String get saveFailed => _strings['saveFailed']!;
  String get shareFailed => _strings['shareFailed']!;
  String get printError => _strings['printError']!;
  String get hr => _strings['hr']!;
  String get legal => _strings['legal']!;
  String get finance => _strings['finance']!;
  String get sales => _strings['sales']!;
  String get admin => _strings['admin']!;
  String get career => _strings['career']!;
  String get fillArrow => _strings['fillArrow']!;
  String get comingSoon => _strings['comingSoon']!;
  String get comingSoonTitle => _strings['comingSoonTitle']!;
  String get comingSoonMessage => _strings['comingSoonMessage']!;
  String get invoice => _strings['invoice']!;
  String get receipt => _strings['receipt']!;
  String get quotation => _strings['quotation']!;
  String get purchaseOrder => _strings['purchaseOrder']!;
  String get billOfSale => _strings['billOfSale']!;
  String get expenseReport => _strings['expenseReport']!;
  String get nda => _strings['nda']!;
  String get serviceAgreement => _strings['serviceAgreement']!;
  String get freelanceContract => _strings['freelanceContract']!;
  String get rentalAgreement => _strings['rentalAgreement']!;
  String get nonCompete => _strings['nonCompete']!;
  String get offerLetter => _strings['offerLetter']!;
  String get employmentContract => _strings['employmentContract']!;
  String get terminationLetter => _strings['terminationLetter']!;
  String get businessProposal => _strings['businessProposal']!;
  String get meetingMinutes => _strings['meetingMinutes']!;
  String get resume => _strings['resume']!;
  String get currency => _strings['currency']!;
  String get from => _strings['from']!;
  String get to => _strings['to']!;
  String get fromAddress => _strings['fromAddress']!;
  String get clientAddress => _strings['clientAddress']!;
  String get invoiceNumber => _strings['invoiceNumber']!;
  String get issueDate => _strings['issueDate']!;
  String get dueDate => _strings['dueDate']!;
  String get lineItems => _strings['lineItems']!;
  String get addLineItem => _strings['addLineItem']!;
  String get subtotal => _strings['subtotal']!;
  String get tax => _strings['tax']!;
  String get total => _strings['total']!;
  String get qrOptional => _strings['qrOptional']!;
  String get notesTerms => _strings['notesTerms']!;
  String get companyLogo => _strings['companyLogo']!;
  String get logoHint => _strings['logoHint']!;
  String get billTo => _strings['billTo']!;
  String get description => _strings['description']!;
  String get qty => _strings['qty']!;
  String get unitPrice => _strings['unitPrice']!;
  String get scanToPay => _strings['scanToPay']!;
  String get notes => _strings['notes']!;
  String get due => _strings['due']!;
  String get date => _strings['date']!;
  String get company => _strings['company']!;
  String get rate => _strings['rate']!;
  String get disclosingParty => _strings['disclosingParty']!;
  String get receivingParty => _strings['receivingParty']!;
  String get effectiveDate => _strings['effectiveDate']!;
  String get duration => _strings['duration']!;
  String get governingState => _strings['governingState']!;
  String get ndaTitle => _strings['ndaTitle']!;
  String get ndaIntro1 => _strings['ndaIntro1']!;
  String get ndaIntro2 => _strings['ndaIntro2']!;
  String get ndaIntro3 => _strings['ndaIntro3']!;
  String get ndaIntro4 => _strings['ndaIntro4']!;
  String get clause1 => _strings['clause1']!;
  String get clause2 => _strings['clause2']!;
  String get clause3 => _strings['clause3']!;
  String get clause4 => _strings['clause4']!;
  String get signature => _strings['signature']!;
  String get candidateName => _strings['candidateName']!;
  String get jobTitle => _strings['jobTitle']!;
  String get startDate => _strings['startDate']!;
  String get offerDeadline => _strings['offerDeadline']!;
  String get compensation => _strings['compensation']!;
  String get dear => _strings['dear']!;
  String get offerLetterBody1 => _strings['offerLetterBody1']!;
  String get offerLetterBody2 => _strings['offerLetterBody2']!;
  String get offerLetterDeadline => _strings['offerLetterDeadline']!;
  String get position => _strings['position']!;
  String get authorizedSignature => _strings['authorizedSignature']!;
  String get acceptance => _strings['acceptance']!;
  String get buyer => _strings['buyer']!;
  String get vendor => _strings['vendor']!;
  String get poNumber => _strings['poNumber']!;
  String get delivery => _strings['delivery']!;
  String get paymentTerms => _strings['paymentTerms']!;
  String get items => _strings['items']!;
  String get addItem => _strings['addItem']!;
  String get item => _strings['item']!;
  String get price => _strings['price']!;
  String get purchaseOrderTitle => _strings['purchaseOrderTitle']!;
  String get terms => _strings['terms']!;
  String get serviceProvider => _strings['serviceProvider']!;
  String get client => _strings['client']!;
  String get servicesDescription => _strings['servicesDescription']!;
  String get feeMonthly => _strings['feeMonthly']!;
  String get endDate => _strings['endDate']!;
  String get serviceAgreementTitle => _strings['serviceAgreementTitle']!;
  String get serviceAgreementIntro1 => _strings['serviceAgreementIntro1']!;
  String get serviceAgreementIntro2 => _strings['serviceAgreementIntro2']!;
  String get serviceAgreementIntro3 => _strings['serviceAgreementIntro3']!;
  String get services => _strings['services']!;
  String get fee => _strings['fee']!;
  String get term => _strings['term']!;
  String get perMonth => _strings['perMonth']!;
  String get receiptNumber => _strings['receiptNumber']!;
  String get receiptTitle => _strings['receiptTitle']!;
  String get thankYou => _strings['thankYou']!;
  String get quotationNumber => _strings['quotationNumber']!;
  String get validUntil => _strings['validUntil']!;
  String get quotationTitle => _strings['quotationTitle']!;
  String get seller => _strings['seller']!;
  String get itemDescription => _strings['itemDescription']!;
  String get salePrice => _strings['salePrice']!;
  String get dateOfSale => _strings['dateOfSale']!;
  String get billOfSaleTitle => _strings['billOfSaleTitle']!;
  String get billOfSaleIntro1 => _strings['billOfSaleIntro1']!;
  String get billOfSaleIntro2 => _strings['billOfSaleIntro2']!;
  String get billOfSaleIntro3 => _strings['billOfSaleIntro3']!;
  String get billOfSaleIntro4 => _strings['billOfSaleIntro4']!;
  String get billOfSaleAmount => _strings['billOfSaleAmount']!;
  String get billOfSaleTransfer => _strings['billOfSaleTransfer']!;
  String get sellerSignature => _strings['sellerSignature']!;
  String get buyerSignature => _strings['buyerSignature']!;
  String get employee => _strings['employee']!;
  String get department => _strings['department']!;
  String get expenses => _strings['expenses']!;
  String get addExpense => _strings['addExpense']!;
  String get amount => _strings['amount']!;
  String get expenseReportTitle => _strings['expenseReportTitle']!;
  String get freelancer => _strings['freelancer']!;
  String get scopeOfWork => _strings['scopeOfWork']!;
  String get hourlyRateFixed => _strings['hourlyRateFixed']!;
  String get deadline => _strings['deadline']!;
  String get freelanceContractTitle => _strings['freelanceContractTitle']!;
  String get freelanceContractIntro1 => _strings['freelanceContractIntro1']!;
  String get freelanceContractIntro2 => _strings['freelanceContractIntro2']!;
  String get freelanceContractIntro3 => _strings['freelanceContractIntro3']!;
  String get landlord => _strings['landlord']!;
  String get tenant => _strings['tenant']!;
  String get propertyAddress => _strings['propertyAddress']!;
  String get monthlyRent => _strings['monthlyRent']!;
  String get rentalAgreementTitle => _strings['rentalAgreementTitle']!;
  String get rentalAgreementIntro1 => _strings['rentalAgreementIntro1']!;
  String get rentalAgreementIntro2 => _strings['rentalAgreementIntro2']!;
  String get rentalAgreementIntro3 => _strings['rentalAgreementIntro3']!;
  String get additionalTerms => _strings['additionalTerms']!;
  String get geographicRadius => _strings['geographicRadius']!;
  String get nonCompeteTitle => _strings['nonCompeteTitle']!;
  String get nonCompeteIntro1 => _strings['nonCompeteIntro1']!;
  String get nonCompeteIntro2 => _strings['nonCompeteIntro2']!;
  String get nonCompeteIntro3 => _strings['nonCompeteIntro3']!;
  String get nonCompeteBody1 => _strings['nonCompeteBody1']!;
  String get nonCompeteBody2 => _strings['nonCompeteBody2']!;
  String get nonCompeteBody3 => _strings['nonCompeteBody3']!;
  String get representative => _strings['representative']!;
  String get employer => _strings['employer']!;
  String get annualSalary => _strings['annualSalary']!;
  String get employmentContractTitle => _strings['employmentContractTitle']!;
  String get employmentContractIntro1 => _strings['employmentContractIntro1']!;
  String get employmentContractIntro2 => _strings['employmentContractIntro2']!;
  String get employmentContractIntro3 => _strings['employmentContractIntro3']!;
  String get standardTerms => _strings['standardTerms']!;
  String get reasonTermination => _strings['reasonTermination']!;
  String get terminationLetterTitle => _strings['terminationLetterTitle']!;
  String get terminationLetterBody1 => _strings['terminationLetterBody1']!;
  String get terminationLetterBody2 => _strings['terminationLetterBody2']!;
  String get reason => _strings['reason']!;
  String get terminationLetterFooter => _strings['terminationLetterFooter']!;
  String get projectTitle => _strings['projectTitle']!;
  String get estimatedBudget => _strings['estimatedBudget']!;
  String get timeline => _strings['timeline']!;
  String get businessProposalTitle => _strings['businessProposalTitle']!;
  String get preparedFor => _strings['preparedFor']!;
  String get preparedBy => _strings['preparedBy']!;
  String get project => _strings['project']!;
  String get budget => _strings['budget']!;
  String get businessProposalBody => _strings['businessProposalBody']!;
  String get attendees => _strings['attendees']!;
  String get minutesDecisions => _strings['minutesDecisions']!;
  String get meetingMinutesTitle => _strings['meetingMinutesTitle']!;
  String get minutes => _strings['minutes']!;
  String get fresher => _strings['fresher']!;
  String get experienced => _strings['experienced']!;
  String get photoOptional => _strings['photoOptional']!;
  String get photoHint => _strings['photoHint']!;
  String get personalDetails => _strings['personalDetails']!;
  String get fullName => _strings['fullName']!;
  String get jobTitleOptional => _strings['jobTitleOptional']!;
  String get email => _strings['email']!;
  String get phone => _strings['phone']!;
  String get location => _strings['location']!;
  String get linkedinPortfolio => _strings['linkedinPortfolio']!;
  String get professionalSummary => _strings['professionalSummary']!;
  String get education => _strings['education']!;
  String get degree => _strings['degree']!;
  String get institution => _strings['institution']!;
  String get yearDuration => _strings['yearDuration']!;
  String get gpa => _strings['gpa']!;
  String get internships => _strings['internships']!;
  String get workExperience => _strings['workExperience']!;
  String get internship => _strings['internship']!;
  String get experience => _strings['experience']!;
  String get titleRole => _strings['titleRole']!;
  String get descriptionBullets => _strings['descriptionBullets']!;
  String get addInternship => _strings['addInternship']!;
  String get addWorkExperience => _strings['addWorkExperience']!;
  String get projects => _strings['projects']!;
  String get projectName => _strings['projectName']!;
  String get technologiesUsed => _strings['technologiesUsed']!;
  String get addProject => _strings['addProject']!;
  String get skills => _strings['skills']!;
  String get addSkill => _strings['addSkill']!;
  String get tech => _strings['tech']!;
  String get certifications => _strings['certifications']!;
  String get certification => _strings['certification']!;
  String get certificationName => _strings['certificationName']!;
  String get issuingOrg => _strings['issuingOrg']!;
  String get year => _strings['year']!;
  String get addCertification => _strings['addCertification']!;
  String get achievements => _strings['achievements']!;
  String get achievementHint => _strings['achievementHint']!;
  String get addAchievement => _strings['addAchievement']!;
  String get generatePdf => _strings['generatePdf']!;
  String get generating => _strings['generating']!;
  String get single => _strings['single']!;
  String get idCard => _strings['idCard']!;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'es', 'hi', 'te', 'fr'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
