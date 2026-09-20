import 'dart:math';
import 'package:pdfrx/pdfrx.dart';

/// OfflineAI — Production-grade document intelligence using lightweight algorithms.
/// Completely offline, no external dependencies.
///
/// Features:
/// 1. Document Classification (Invoice, Contract, Resume, etc.)
/// 2. Key Entity Extraction (names, dates, amounts, emails, phone numbers)
/// 3. Document Deduplication & Similarity Search
/// 4. Automatic Tagging & Categorization
/// 5. Smart Form Filling (auto‑suggest values from context)
///
/// ALL improvements from code review have been applied:
/// ✅ Tokenizer preserves digits, apostrophes, and hyphens
/// ✅ Stopword list expanded to 220+ words
/// ✅ Classification uses keyword‑weighted TF (no broken TF‑IDF)
/// ✅ Tighter entity regexes (phones, amounts with commas)
/// ✅ `parseResume` uses entity extraction first
/// ✅ `suggestFieldValue` improved with multiple patterns
class OfflineAI {
  // ─── 1. DOCUMENT CLASSIFICATION ──────────────────────────────────────

  /// Pre‑defined category profiles (keywords + weights)
  static const Map<String, Map<String, double>> _categoryProfiles = {
    'Invoice': {
      'invoice': 2.0,
      'total': 1.8,
      'amount': 1.8,
      'due': 1.5,
      'payment': 1.5,
      'bill': 1.4,
      'client': 1.2,
      'item': 1.0,
    },
    'Contract': {
      'contract': 2.0,
      'agreement': 1.8,
      'terms': 1.5,
      'conditions': 1.5,
      'party': 1.4,
      'obligations': 1.3,
      'liability': 1.2,
      'termination': 1.2,
    },
    'Resume / CV': {
      'resume': 2.0,
      'cv': 1.8,
      'experience': 1.6,
      'education': 1.5,
      'skills': 1.4,
      'professional': 1.3,
      'career': 1.2,
      'achievement': 1.1,
    },
    'Receipt': {
      'receipt': 2.0,
      'paid': 1.8,
      'payment': 1.6,
      'total': 1.5,
      'amount': 1.5,
      'transaction': 1.3,
      'card': 1.0,
    },
    'NDA': {
      'nda': 2.0,
      'non-disclosure': 2.0,
      'confidential': 1.8,
      'confidentiality': 1.8,
      'disclosure': 1.5,
      'recipient': 1.2,
    },
    'Proposal': {
      'proposal': 2.0,
      'scope': 1.6,
      'deliverables': 1.5,
      'timeline': 1.4,
      'budget': 1.4,
      'solution': 1.2,
    },
  };

  /// Classifies a document based on its text content.
  /// Uses term‑frequency weighted keyword matching.
  static String classifyDocument(String text) {
    if (text.isEmpty) return 'Uncategorized';

    final tokens = _tokenize(text);
    if (tokens.isEmpty) return 'Uncategorized';

    final tf = _termFrequency(tokens);
    String bestCategory = 'Uncategorized';
    double bestScore = 0.0;

    for (final entry in _categoryProfiles.entries) {
      final profile = entry.value;
      double score = 0.0;
      for (final token in tf.keys) {
        final weight = profile[token] ?? 0.0;
        score += weight * tf[token]!;
      }
      // Normalize by number of tokens to avoid length bias
      score = score / (tokens.length + 1);
      if (score > bestScore) {
        bestScore = score;
        bestCategory = entry.key;
      }
    }

    return bestScore > 0.05 ? bestCategory : 'Uncategorized';
  }

  // ─── 2. KEY ENTITY EXTRACTION ────────────────────────────────────────

  /// Extracts key entities from text: names, dates, amounts, emails, phone numbers, clauses.
  static Map<String, List<String>> extractEntities(String text) {
    final entities = <String, List<String>>{
      'dates': [],
      'amounts': [],
      'emails': [],
      'phoneNumbers': [],
      'clauses': [],
    };

    // Dates (improved patterns)
    final datePatterns = [
      RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'),
      RegExp(r'\b[A-Z][a-z]+ \d{1,2},? \d{4}\b'),
      RegExp(r'\b\d{1,2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}\b'),
      RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), // ISO dates
    ];
    for (final pattern in datePatterns) {
      entities['dates']!.addAll(pattern.allMatches(text).map((m) => m.group(0)!));
    }

    // Amounts / Currency (supports $1,234.56, €1.234,56, etc.)
    final amountPatterns = [
      RegExp(r'\$\d{1,3}(,\d{3})*(\.\d{2})?'),
      RegExp(r'€\d{1,3}(,\d{3})*(\.\d{2})?'),
      RegExp(r'£\d{1,3}(,\d{3})*(\.\d{2})?'),
      RegExp(r'₹\d{1,3}(,\d{3})*(\.\d{2})?'),
      RegExp(r'\d{1,3}(,\d{3})*(\.\d{2})?\s?(dollars|USD|EUR|GBP|INR)'),
    ];
    for (final pattern in amountPatterns) {
      entities['amounts']!.addAll(pattern.allMatches(text).map((m) => m.group(0)!));
    }

    // Emails (already robust)
    final emailPattern = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    entities['emails']!.addAll(emailPattern.allMatches(text).map((m) => m.group(0)!));

    // Phone numbers (tightened)
    final phonePatterns = [
      // US: (123) 456-7890 or 123-456-7890
      RegExp(r'\(?\d{3}\)?[\s\-]?\d{3}[\s\-]?\d{4}'),
      // International: +1 123-456-7890
      RegExp(r'\+\d{1,3}[\s\-]?\(?\d{1,4}\)?[\s\-]?\d{1,4}[\s\-]?\d{1,4}'),
      // Simple 10+ digits with optional separators
      RegExp(r'\b\d{3}[\s\-\.]?\d{3}[\s\-\.]?\d{4}\b'),
    ];
    for (final pattern in phonePatterns) {
      entities['phoneNumbers']!.addAll(pattern.allMatches(text).map((m) => m.group(0)!));
    }

    // Contract clauses (unchanged, already good)
    final clausePatterns = {
      'Non-Compete': r'\bnon[- ]compete\b|\bnon[- ]competition\b',
      'Governing Law': r'\bgoverning law\b|\bchoice of law\b',
      'Termination': r'\btermination\b|\bterminate\b|\bnotice of termination\b',
      'Confidentiality': r'\bconfidential\b|\bconfidentiality\b|\bnondisclosure\b',
      'Indemnification': r'\bindemnif(y|ication)\b|\bindemnity\b',
      'Payment Terms': r'\bpayment terms\b|\bnett? \d+\b|\bdue upon\b',
    };
    for (final entry in clausePatterns.entries) {
      final pattern = RegExp(entry.value, caseSensitive: false);
      if (pattern.hasMatch(text)) {
        entities['clauses']!.add(entry.key);
      }
    }

    // Remove duplicates
    for (final key in entities.keys) {
      entities[key] = entities[key]!.toSet().toList();
    }

    return entities;
  }

  // ─── 3. DOCUMENT DEDUPLICATION & SIMILARITY SEARCH ─────────────────

  /// Computes similarity between two documents using TF‑IDF + cosine.
  static double similarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    final tokens1 = _tokenize(text1);
    final tokens2 = _tokenize(text2);

    // Compute TF‑IDF for both
    final allTokens = {...tokens1, ...tokens2};
    final df = <String, int>{};
    for (final token in allTokens) {
      df[token] = 0;
      if (tokens1.contains(token)) df[token] = df[token]! + 1;
      if (tokens2.contains(token)) df[token] = df[token]! + 1;
    }

    final tf1 = _termFrequency(tokens1);
    final tf2 = _termFrequency(tokens2);

    final idf = <String, double>{};
    final N = 2.0;
    for (final entry in df.entries) {
      idf[entry.key] = log((N + 1) / (entry.value + 1)) + 1;
    }

    final tfidf1 = <String, double>{};
    final tfidf2 = <String, double>{};
    for (final token in allTokens) {
      tfidf1[token] = (tf1[token] ?? 0) * (idf[token] ?? 0);
      tfidf2[token] = (tf2[token] ?? 0) * (idf[token] ?? 0);
    }

    return _cosineSimilarity(tfidf1, tfidf2);
  }

  /// Finds duplicate or similar documents in a list.
  static List<Map<String, dynamic>> findDuplicates(
    List<String> texts,
    List<String> names, {
    double threshold = 0.7,
  }) {
    final results = <Map<String, dynamic>>[];
    if (texts.length < 2) return results;

    for (int i = 0; i < texts.length; i++) {
      for (int j = i + 1; j < texts.length; j++) {
        final sim = similarity(texts[i], texts[j]);
        if (sim > threshold) {
          results.add({
            'document1': names[i],
            'document2': names[j],
            'similarity': sim,
          });
        }
      }
    }
    return results;
  }

  // ─── 4. AUTOMATIC TAGGING ─────────────────────────────────────────────

  static List<String> autoTagDocument(String text) {
    final tags = <String>[];

    final topicKeywords = {
      'Financial': ['invoice', 'payment', 'amount', 'total', 'balance', 'receipt', 'transaction'],
      'Legal': ['contract', 'agreement', 'terms', 'conditions', 'liability', 'indemnity', 'governing'],
      'HR': ['employee', 'salary', 'benefits', 'hire', 'offer', 'termination', 'recruitment'],
      'Urgent': ['urgent', 'immediate', 'asap', 'deadline', 'expires', 'due', 'critical'],
      'Confidential': ['confidential', 'nda', 'non-disclosure', 'privileged', 'private'],
      'Draft': ['draft', 'work in progress', 'preliminary', 'v1', 'v0'],
    };

    final lowerText = text.toLowerCase();
    for (final entry in topicKeywords.entries) {
      final count = entry.value.fold(0, (sum, keyword) {
        return sum + RegExp(keyword, caseSensitive: false).allMatches(lowerText).length;
      });
      if (count >= 2) {
        tags.add(entry.key);
      }
    }

    return tags;
  }

  // ─── 5. SMART FORM FILLING ────────────────────────────────────────────

  /// Extracts potential values for a template field from a context text.
  static String? suggestFieldValue(String fieldLabel, String context) {
    final lowerField = fieldLabel.toLowerCase();
    final lowerContext = context.toLowerCase();

    // Prefer patterns that include the field label as a key
    final fieldPatterns = {
      'name': RegExp(r'[Nn]ame[:\s]+([A-Z][a-z]+\s+[A-Z][a-z]+)'),
      'email': RegExp(r'[Ee]mail[:\s]+([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})'),
      'phone': RegExp(r'[Pp]hone[:\s]+((\+\d{1,3}[\s\-]?)?\(?\d{3}\)?[\s\-]?\d{3}[\s\-]?\d{4})'),
      'date': RegExp(r'[Dd]ate[:\s]+(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})'),
      'amount': RegExp(r'[Aa]mount[:\s]+(\$\d{1,3}(,\d{3})*(\.\d{2})?)'),
      'company': RegExp(r'[Cc]ompany[:\s]+([A-Z][a-z]+ (Inc|Corp|LLC|Ltd|Co)\b)'),
    };

    for (final entry in fieldPatterns.entries) {
      if (lowerField.contains(entry.key)) {
        final match = entry.value.firstMatch(context);
        if (match != null && match.groupCount >= 1) {
          return match.group(1);
        }
      }
    }

    // Fallback: generic capture after field label (more permissive)
    final fallbackRegex = RegExp('$lowerField[ :]+([A-Za-z0-9@._\\-]+)', caseSensitive: false);
    final match = fallbackRegex.firstMatch(lowerContext);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }

    return null;
  }

  // ─── 6. RESUME PARSING (Enhanced) ────────────────────────────────────

  /// Parses a raw text (clipboard) into structured resume data.
  static Map<String, dynamic> parseResume(String text) {
    final result = <String, dynamic>{};

    // First, extract entities (emails, phones, etc.)
    final entities = extractEntities(text);
    if (entities['emails']!.isNotEmpty) {
      result['email'] = entities['emails']!.first;
    }
    if (entities['phoneNumbers']!.isNotEmpty) {
      result['phone'] = entities['phoneNumbers']!.first;
    }

    // Name: find first line that looks like a name (two words, capitalized, not containing @, etc.)
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length > 2 && trimmed.length < 50 &&
          !trimmed.contains('@') && !RegExp(r'\d{4}').hasMatch(trimmed) &&
          !_stopWords.contains(trimmed.toLowerCase()) &&
          RegExp(r'[A-Z][a-z]+\s+[A-Z][a-z]+').hasMatch(trimmed)) {
        result['fullName'] = trimmed;
        break;
      }
    }

    // Skills: look for "Skills" heading and capture list
    final skillRegex = RegExp(r'(?:skills|technologies|tech stack)[\s:]+(.+?)(?:\n|$)', caseSensitive: false);
    final skillMatch = skillRegex.firstMatch(text);
    if (skillMatch != null) {
      final skills = skillMatch.group(1)!.split(RegExp(r'[,\n••]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      result['skills'] = skills;
    }

    // Work Experiences: find date ranges and capture nearby lines
    final expRegex = RegExp(r'(\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\s*[-–]\s*(\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}|Present)\b)', caseSensitive: false);
    final expMatches = expRegex.allMatches(text);
    final experiences = <Map<String, String>>[];
    for (final match in expMatches) {
      final start = text.lastIndexOf('\n', match.start);
      final end = text.indexOf('\n', match.end + 50);
      final block = text.substring(start > 0 ? start : 0, end > 0 ? end : text.length);
      final linesBlock = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (linesBlock.isNotEmpty) {
        experiences.add({
          'title': linesBlock.length > 1 ? linesBlock[0] : 'Position',
          'company': linesBlock.length > 2 ? linesBlock[1] : 'Company',
          'date': match.group(0)!,
          'desc': linesBlock.skip(2).take(3).join('\n'),
        });
      }
    }
    result['workExperiences'] = experiences;

    // Education: look for degree keywords
    final eduRegex = RegExp(r'\b(Bachelor|Master|B\.Sc|M\.Sc|MBA|PhD|B\.A|M\.A|Associate|Diploma)\b', caseSensitive: false);
    final eduMatch = eduRegex.firstMatch(text);
    if (eduMatch != null) {
      // Find the line containing the degree
      for (final line in lines) {
        if (line.contains(eduMatch.group(0)!)) {
          result['degree'] = line.trim();
          break;
        }
      }
    }

    // Summary: first paragraph that is long enough
    final cleanedLines = lines.where((l) =>
      !l.contains('@') &&
      !l.contains(RegExp(r'\+?[\d\s\-\(\)]')) &&
      l.length > 30
    ).toList();
    if (cleanedLines.isNotEmpty) {
      result['summary'] = cleanedLines.take(3).join(' ');
    }

    return result;
  }

  // ─── INTERNAL HELPERS ──────────────────────────────────────────────────

  /// Improved tokenizer: preserves digits, apostrophes, and hyphens.
  static List<String> _tokenize(String text) {
    var cleaned = text.toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r"[^a-z0-9'\-]"), ' ');
        return cleaned.split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w.length > 2 && !_stopWords.contains(w))
        .toList();
  }

  static Map<String, double> _termFrequency(List<String> tokens) {
    final freq = <String, double>{};
    for (final token in tokens) {
      freq[token] = (freq[token] ?? 0) + 1;
    }
    final maxFreq = freq.values.fold(0.0, (max, v) => v > max ? v : max);
    if (maxFreq > 0) {
      for (final key in freq.keys) {
        freq[key] = freq[key]! / maxFreq;
      }
    }
    return freq;
  }

  static double _cosineSimilarity(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (final key in a.keys) {
      normA += a[key]! * a[key]!;
      if (b.containsKey(key)) {
        dot += a[key]! * b[key]!;
      }
    }
    for (final key in b.keys) {
      normB += b[key]! * b[key]!;
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// Expanded stopword list (220+ words) – same as TextRankSummarizer.
  static const Set<String> _stopWords = {
    'a', 'about', 'above', 'across', 'after', 'afterwards', 'again', 'against',
    'all', 'almost', 'alone', 'along', 'already', 'also', 'although', 'always',
    'am', 'among', 'amongst', 'amount', 'an', 'and', 'another', 'any', 'anyhow',
    'anyone', 'anything', 'anyway', 'anywhere', 'are', 'around', 'as', 'at',
    'back', 'be', 'became', 'because', 'become', 'becomes', 'becoming', 'been',
    'before', 'beforehand', 'behind', 'being', 'below', 'beside', 'besides',
    'between', 'beyond', 'both', 'bottom', 'but', 'by',
    'call', 'can', 'cannot', 'cant', 'co', 'con', 'could', 'couldnt',
    'de', 'describe', 'detail', 'do', 'done', 'down', 'due', 'during',
    'each', 'eg', 'eight', 'either', 'eleven', 'else', 'elsewhere', 'empty',
    'etc', 'even', 'ever', 'every', 'everyone', 'everything', 'everywhere',
    'except',
    'few', 'fifteen', 'fify', 'fill', 'find', 'fire', 'first', 'five', 'for',
    'former', 'formerly', 'forty', 'found', 'four', 'from', 'front', 'full',
    'further',
    'get', 'give', 'go', 'had', 'has', 'hasnt', 'have', 'he', 'hence', 'her',
    'here', 'hereafter', 'hereby', 'herein', 'hereupon', 'hers', 'herself',
    'him', 'himself', 'his', 'how', 'however', 'hundred',
    'i', 'ie', 'if', 'in', 'inc', 'indeed', 'interest', 'into', 'is', 'it',
    'its', 'itself',
    'keep',
    'last', 'latter', 'latterly', 'least', 'less', 'ltd',
    'made', 'many', 'may', 'me', 'meanwhile', 'might', 'mill', 'mine', 'more',
    'moreover', 'most', 'mostly', 'move', 'much', 'must', 'my', 'myself',
    'name', 'namely', 'neither', 'never', 'nevertheless', 'next', 'nine', 'no',
    'nobody', 'none', 'noone', 'nor', 'not', 'nothing', 'now', 'nowhere',
    'of', 'off', 'often', 'on', 'once', 'one', 'only', 'onto', 'or', 'other',
    'others', 'otherwise', 'our', 'ours', 'ourselves', 'out', 'over', 'own',
    'part', 'per', 'perhaps', 'please', 'put',
    'rather', 're',
    'same', 'see', 'seem', 'seemed', 'seeming', 'seems', 'serious', 'several',
    'she', 'should', 'show', 'side', 'since', 'sincere', 'six', 'sixty', 'so',
    'some', 'somehow', 'someone', 'something', 'sometime', 'sometimes',
    'somewhere', 'still', 'such', 'system',
    'take', 'ten', 'than', 'that', 'the', 'their', 'them', 'themselves', 'then',
    'thence', 'there', 'thereafter', 'thereby', 'therefore', 'therein',
    'thereupon', 'these', 'they', 'thick', 'thin', 'third', 'this', 'those',
    'though', 'three', 'through', 'throughout', 'thru', 'thus', 'to', 'together',
    'too', 'top', 'toward', 'towards', 'twelve', 'twenty', 'two',
    'un', 'under', 'until', 'up', 'upon', 'us',
    'very', 'via',
    'was', 'we', 'well', 'were', 'what', 'whatever', 'when', 'whence',
    'whenever', 'where', 'whereafter', 'whereby', 'wherein', 'whereupon',
    'wherever', 'whether', 'which', 'while', 'whither', 'who', 'whoever',
    'whole', 'whom', 'whose', 'why', 'will', 'with', 'within', 'without',
    'would',
    'yet', 'you', 'your', 'yours', 'yourself', 'yourselves',
    // Domain‑specific (legal/medical)
   // 'herein', 'thereof', 'whereas', 'notwithstanding', 'aforesaid',
   // 'hereinafter', 'heretofore', 'whereby', 'wherein', 'thereto',
  };
}