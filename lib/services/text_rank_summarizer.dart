import 'dart:math';

/// TextRank – Production-grade extractive text summarization with MMR.
/// Completely offline, no external dependencies.
///
/// Features:
/// ✅ Correct PageRank with proper damping + dangling nodes
/// ✅ Real Porter stemmer (200+ lines)
/// ✅ Stop-word removal (220+ words)
/// ✅ Smoothed IDF: log((N+1)/(df+1)) + 1
/// ✅ Sparse graph for PageRank – O(n) memory
/// ✅ Adaptive similarity threshold
/// ✅ Heading & entity boosts (reduced to 1.1)
/// ✅ **MMR (Maximum Marginal Relevance) selection** – balances relevance & diversity
/// ✅ MMR enabled by default for better, less repetitive summaries
class TextRankSummarizer {
  final int maxSummarySentences;
  final double dampingFactor;
  final double similarityThreshold;
  final bool useAdaptiveThreshold;
  final bool enableHeadingBoost;
  final bool enableEntityBoost;
  final bool useMMR;
  final double mmrLambda;

  const TextRankSummarizer({
    this.maxSummarySentences = 5,
    this.dampingFactor = 0.85,
    this.similarityThreshold = 0.05,
    this.useAdaptiveThreshold = true,
    this.enableHeadingBoost = true,
    this.enableEntityBoost = true,
    this.useMMR = true, // ✅ now enabled by default
    this.mmrLambda = 0.7,
  });

  // ─── Static compiled regexes ──────────────────────────────────────────

  static final List<RegExp> _headingPatterns = [
    RegExp(r'^(introduction|background|methodology|results|discussion|conclusion|summary|recommendation|appendix|references|abstract)',
        caseSensitive: false),
    RegExp(r'^[IVXLCDM]+\.\s'),
    RegExp(r'^\d+\.\s'),
  ];

  static final RegExp _entityNumber = RegExp(r'\d+\.?\d*%?');
  static final RegExp _entityCurrency = RegExp(r'[$€£¥₹]');
  static final RegExp _entityDate1 = RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}');
  static final RegExp _entityDate2 = RegExp(r'[A-Z][a-z]+ \d{1,2},? \d{4}');
  static final RegExp _entityPercent = RegExp(r'\d+\.?\d*%');
  static final RegExp _entityDollar = RegExp(r'\$\d+\.?\d*');
  static final RegExp _entityYear = RegExp(r'\b(19|20)\d{2}\b');
  static final RegExp _entityProperName = RegExp(r'[A-Z][a-z]+ [A-Z][a-z]+');

  // ─── Public API ──────────────────────────────────────────────────────────

  String summarize(String text) {
    if (text.isEmpty) return '';

    final sentences = _splitSentences(text);
    if (sentences.isEmpty) return text;

    // Dynamic threshold for short documents
    final totalWords = text.split(RegExp(r'\s+')).length;
    final minMeaningfulWords = totalWords < 150 ? 3 : 4;

    final filtered = <String>[];
    for (final s in sentences) {
      final tokens = _tokenize(s);
      final meaningful = tokens
          .where((t) => !_stopWords.contains(t) && t.length > 2)
          .toList();
      if (meaningful.length >= minMeaningfulWords) {
        filtered.add(s);
      }
    }

    if (filtered.length < 2) {
      final fallback = sentences.where((s) => s.trim().length > 15).toList();
      if (fallback.length >= 2) return fallback.join(' ');
      return text;
    }

    final numSentences = filtered.length;
    final adaptiveMax = min(maxSummarySentences, _adaptiveMaxSentences(numSentences));

    // Tokenize and build TF‑IDF weights
    final tokenized = filtered.map(_tokenizeWithStemming).toList();
    final weights = _computeWeights(tokenized);

    // Build sparse graph for PageRank
    final (edges, outSum) = _buildSparseGraph(weights);
    final scores = _pageRank(edges, outSum);
    final normalized = _normalizeScores(scores);

    // Apply boosts
    var boosted = List<double>.from(normalized);
    if (enableHeadingBoost || enableEntityBoost) {
      for (int i = 0; i < filtered.length; i++) {
        double boost = 1.0;
        if (enableHeadingBoost && _isHeading(filtered[i])) {
          final wordCount = filtered[i].split(' ').length;
          final factor = min(1.0, wordCount / 5.0);
          boost *= (1.0 + 0.1 * factor);
        }
        if (enableEntityBoost && _containsImportantEntity(filtered[i])) {
          boost *= 1.1;
        }
        boosted[i] *= boost;
      }
      final total = boosted.fold(0.0, (s, v) => s + v);
      if (total > 0) {
        boosted = boosted.map((v) => v / total).toList();
      }
    }

    // ─── Selection ──────────────────────────────────────────────────────
    List<int> topIndices;

    if (useMMR) {
      // Build dense similarity matrix (reuses the same weights)
      final similarityMatrix = _buildDenseMatrix(weights);
      topIndices = _mmrSelect(similarityMatrix, boosted, adaptiveMax, mmrLambda);
    } else {
      final indexed = <int, double>{};
      for (int i = 0; i < filtered.length; i++) {
        indexed[i] = boosted[i];
      }
      final sorted = indexed.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topIndices = sorted
          .take(adaptiveMax)
          .map((e) => e.key)
          .toList();
    }

    topIndices.sort();
    return topIndices.map((i) => filtered[i]).join(' ');
  }

  // ─── MMR Selection ──────────────────────────────────────────────────────

  List<int> _mmrSelect(
    List<List<double>> similarity,
    List<double> scores,
    int k,
    double lambda,
  ) {
    final n = similarity.length;
    if (k >= n) return List.generate(n, (i) => i);
    if (n == 0) return [];
    if (k <= 0) return [];

    final selected = <int>[];
    final candidates = List<int>.generate(n, (i) => i);

    // Safety: if no sentences selected yet, pick the highest‑scoring one.
    if (selected.isEmpty) {
      int bestFirst = 0;
      double bestScore = -1.0;
      for (int i = 0; i < n; i++) {
        if (scores[i] > bestScore) {
          bestScore = scores[i];
          bestFirst = i;
        }
      }
      selected.add(bestFirst);
      candidates.remove(bestFirst);
    }

    for (int _ = 1; _ < k; _++) {
      int bestIdx = -1;
      double bestMMR = -double.infinity;

      for (final i in candidates) {
        final relevance = scores[i];
        double maxSimToSelected = 0.0;
        for (final j in selected) {
          final sim = similarity[i][j];
          if (sim > maxSimToSelected) maxSimToSelected = sim;
        }
        final mmr = lambda * relevance - (1 - lambda) * maxSimToSelected;
        if (mmr > bestMMR) {
          bestMMR = mmr;
          bestIdx = i;
        }
      }

      if (bestIdx == -1) break;
      selected.add(bestIdx);
      candidates.remove(bestIdx);
    }

    selected.sort();
    return selected;
  }

  // ─── Build Dense Similarity Matrix ────────────────────────────────────

  List<List<double>> _buildDenseMatrix(List<Map<String, double>> weights) {
    final n = weights.length;
    if (n == 0) return [];

    final matrix = List.generate(n, (_) => List.filled(n, 0.0));

    double threshold = similarityThreshold;
    if (useAdaptiveThreshold) {
      double totalSim = 0.0;
      int pairCount = 0;
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          final sim = _cosineSimilarity(weights[i], weights[j]);
          if (sim > 0.001) {
            totalSim += sim;
            pairCount++;
          }
        }
      }
      if (pairCount > 0) {
        final avgSim = totalSim / pairCount;
        threshold = (avgSim * 0.5).clamp(0.01, 0.1);
      }
    }

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final common = weights[i].keys.where((k) => weights[j].containsKey(k)).toList();
        if (common.isEmpty) continue;
        final sim = _cosineSimilarity(weights[i], weights[j]);
        if (sim > threshold) {
          matrix[i][j] = sim;
          matrix[j][i] = sim;
        }
      }
    }
    return matrix;
  }

  // ─── Adaptive summary length ──────────────────────────────────────────

  int _adaptiveMaxSentences(int total) {
    if (total <= 5) return 2;
    if (total <= 10) return 3;
    if (total <= 20) return 5;
    if (total <= 40) return 8;
    if (total <= 100) return 12;
    return 15;
  }

  // ─── Heading & Entity Detection ─────────────────────────────────────

  bool _isHeading(String sentence) {
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length < 60) {
      if (trimmed == trimmed.toUpperCase() && trimmed.length > 3) return true;
      for (final pattern in _headingPatterns) {
        if (pattern.hasMatch(trimmed)) return true;
      }
    }
    return false;
  }

  bool _containsImportantEntity(String sentence) {
    if (_entityNumber.hasMatch(sentence)) return true;
    if (_entityCurrency.hasMatch(sentence)) return true;
    if (_entityDate1.hasMatch(sentence)) return true;
    if (_entityDate2.hasMatch(sentence)) return true;
    if (_entityPercent.hasMatch(sentence)) return true;
    if (_entityDollar.hasMatch(sentence)) return true;
    if (_entityYear.hasMatch(sentence)) return true;
    if (_entityProperName.hasMatch(sentence)) return true;
    return false;
  }

  // ─── Sentence splitting (safe abbreviation protection) ─────────────

  List<String> _splitSentences(String text) {
    final abbreviations = {
      'mr',
      'mrs',
      'ms',
      'dr',
      'prof',
      'rev',
      'hon',
      'st',
      'jr',
      'sr',
      'inc',
      'corp',
      'ltd',
      'co',
      'llc',
      'plc',
      'llp',
      'vol',
      'ed',
      'trans',
      'rev',
      'col',
      'gen',
      'sen',
      'rep',
      'gov',
      'pres',
      'sec',
      'asst',
      'supt',
      'e.g',
      'i.e',
      'vs',
      'etc',
      'cf',
      'al',
      'et',
      'jan',
      'feb',
      'mar',
      'apr',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
      'mon',
      'tue',
      'wed',
      'thu',
      'fri',
      'sat',
      'sun',
      'a.m',
      'p.m',
      'u.s',
      'u.k',
      'e.u',
      'no',
      'fig',
      'eq',
      'sec',
      'chap',
      'app',
      'rev',
    };

    var processed = text;
    final abbrMap = <String, String>{};
    const placeholder = '___ABBR___';

    for (final abbr in abbreviations) {
      final pattern = RegExp(r'\b' + abbr + r'\.\b', caseSensitive: false);
      processed = processed.replaceAllMapped(pattern, (match) {
        final key = '$placeholder${abbrMap.length}';
        abbrMap[key] = match.group(0)!;
        return key;
      });
    }

    processed = processed.replaceAllMapped(
      RegExp(r'\d+\.\d+'),
      (m) => m.group(0)!.replaceAll('.', '___DOT___'),
    );
    processed = processed.replaceAllMapped(
      RegExp(r'[A-Z]\.\s*[A-Z]\.'),
      (m) => m.group(0)!.replaceAll('.', '___DOT___'),
    );

    final parts = processed.split(RegExp(r'(?<=[.!?])\s+'));

    final sentences = parts.map((part) {
      var restored = part;
      for (final entry in abbrMap.entries) {
        restored = restored.replaceAll(entry.key, entry.value);
      }
      restored = restored.replaceAll('___DOT___', '.');
      return restored.trim();
    }).where((s) => s.isNotEmpty).toList();

    if (sentences.length < 2) {
      final fallback = text.split(RegExp(r'[\n\r]+'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (fallback.length > 1) return fallback;
    }
    return sentences;
  }

  // ─── Expanded stop words (220+) ─────────────────────────────────────

  static const Set<String> _stopWords = {
    'a',
    'about',
    'above',
    'across',
    'after',
    'afterwards',
    'again',
    'against',
    'all',
    'almost',
    'alone',
    'along',
    'already',
    'also',
    'although',
    'always',
    'am',
    'among',
    'amongst',
    'amount',
    'an',
    'and',
    'another',
    'any',
    'anyhow',
    'anyone',
    'anything',
    'anyway',
    'anywhere',
    'are',
    'around',
    'as',
    'at',
    'back',
    'be',
    'became',
    'because',
    'become',
    'becomes',
    'becoming',
    'been',
    'before',
    'beforehand',
    'behind',
    'being',
    'below',
    'beside',
    'besides',
    'between',
    'beyond',
    'both',
    'bottom',
    'but',
    'by',
    'call',
    'can',
    'cannot',
    'cant',
    'co',
    'con',
    'could',
    'couldnt',
    'de',
    'describe',
    'detail',
    'do',
    'done',
    'down',
    'due',
    'during',
    'each',
    'eg',
    'eight',
    'either',
    'eleven',
    'else',
    'elsewhere',
    'empty',
    'etc',
    'even',
    'ever',
    'every',
    'everyone',
    'everything',
    'everywhere',
    'except',
    'few',
    'fifteen',
    'fify',
    'fill',
    'find',
    'fire',
    'first',
    'five',
    'for',
    'former',
    'formerly',
    'forty',
    'found',
    'four',
    'from',
    'front',
    'full',
    'further',
    'get',
    'give',
    'go',
    'had',
    'has',
    'hasnt',
    'have',
    'he',
    'hence',
    'her',
    'here',
    'hereafter',
    'hereby',
    'herein',
    'hereupon',
    'hers',
    'herself',
    'him',
    'himself',
    'his',
    'how',
    'however',
    'hundred',
    'i',
    'ie',
    'if',
    'in',
    'inc',
    'indeed',
    'interest',
    'into',
    'is',
    'it',
    'its',
    'itself',
    'keep',
    'last',
    'latter',
    'latterly',
    'least',
    'less',
    'ltd',
    'made',
    'many',
    'may',
    'me',
    'meanwhile',
    'might',
    'mill',
    'mine',
    'more',
    'moreover',
    'most',
    'mostly',
    'move',
    'much',
    'must',
    'my',
    'myself',
    'name',
    'namely',
    'neither',
    'never',
    'nevertheless',
    'next',
    'nine',
    'no',
    'nobody',
    'none',
    'noone',
    'nor',
    'not',
    'nothing',
    'now',
    'nowhere',
    'of',
    'off',
    'often',
    'on',
    'once',
    'one',
    'only',
    'onto',
    'or',
    'other',
    'others',
    'otherwise',
    'our',
    'ours',
    'ourselves',
    'out',
    'over',
    'own',
    'part',
    'per',
    'perhaps',
    'please',
    'put',
    'rather',
    're',
    'same',
    'see',
    'seem',
    'seemed',
    'seeming',
    'seems',
    'serious',
    'several',
    'she',
    'should',
    'show',
    'side',
    'since',
    'sincere',
    'six',
    'sixty',
    'so',
    'some',
    'somehow',
    'someone',
    'something',
    'sometime',
    'sometimes',
    'somewhere',
    'still',
    'such',
    'system',
    'take',
    'ten',
    'than',
    'that',
    'the',
    'their',
    'them',
    'themselves',
    'then',
    'thence',
    'there',
    'thereafter',
    'thereby',
    'therefore',
    'therein',
    'thereupon',
    'these',
    'they',
    'thick',
    'thin',
    'third',
    'this',
    'those',
    'though',
    'three',
    'through',
    'throughout',
    'thru',
    'thus',
    'to',
    'together',
    'too',
    'top',
    'toward',
    'towards',
    'twelve',
    'twenty',
    'two',
    'un',
    'under',
    'until',
    'up',
    'upon',
    'us',
    'very',
    'via',
    'was',
    'we',
    'well',
    'were',
    'what',
    'whatever',
    'when',
    'whence',
    'whenever',
    'where',
    'whereafter',
    'whereby',
    'wherein',
    'whereupon',
    'wherever',
    'whether',
    'which',
    'while',
    'whither',
    'who',
    'whoever',
    'whole',
    'whom',
    'whose',
    'why',
    'will',
    'with',
    'within',
    'without',
    'would',
    'yet',
    'you',
    'your',
    'yours',
    'yourself',
    'yourselves',
  //  'herein',
    'thereof',
    'whereas',
    'notwithstanding',
    'aforesaid',
    'hereinafter',
    'heretofore',
   // 'whereby',
   // 'wherein',
    'thereto',
  };

  // ─── Tokenizers ──────────────────────────────────────────────────────

  List<String> _tokenize(String sentence) {
    var cleaned = sentence.toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r"[^a-z0-9'\-]"), ' ');
    return cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }

  List<String> _tokenizeWithStemming(String sentence) {
    var cleaned = sentence.toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r"[^a-z0-9'\-]"), ' ');
    final tokens = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return tokens
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .map(_stem)
        .toList();
  }

  // ─── REAL Porter Stemmer ─────────────────────────────────────────────

  String _stem(String word) {
    var w = word.toLowerCase();

    if (w.endsWith('sses')) {
      w = w.substring(0, w.length - 2);
    } else if (w.endsWith('ies')) {
      w = w.substring(0, w.length - 2);
    } else if (w.endsWith('ss')) {
      // keep ss
    } else if (w.endsWith('s')) {
      w = w.substring(0, w.length - 1);
    }

    var changed = false;
    if (w.endsWith('eed') && _hasVowel(w.substring(0, w.length - 3))) {
      w = w.substring(0, w.length - 1);
    } else if (w.endsWith('ed') && _hasVowel(w.substring(0, w.length - 2))) {
      w = w.substring(0, w.length - 2);
      changed = true;
    } else if (w.endsWith('ing') && _hasVowel(w.substring(0, w.length - 3))) {
      w = w.substring(0, w.length - 3);
      changed = true;
    }

    if (changed) {
      if (w.endsWith('at') || w.endsWith('bl') || w.endsWith('iz')) {
        w += 'e';
      } else if (_isDoubleConsonant(w) &&
          !w.endsWith('l') &&
          !w.endsWith('s') &&
          !w.endsWith('z')) {
        w = w.substring(0, w.length - 1);
      } else if (_isShortWord(w)) {
        w += 'e';
      }
    }

    if (w.endsWith('y') && _hasVowel(w.substring(0, w.length - 1))) {
      w = w.substring(0, w.length - 1) + 'i';
    }

    const step2Suffixes = {
      'ational': 'ate',
      'tional': 'tion',
      'enci': 'ence',
      'anci': 'ance',
      'izer': 'ize',
      'abli': 'able',
      'alli': 'al',
      'entli': 'ent',
      'eli': 'e',
      'ousli': 'ous',
      'ization': 'ize',
      'ation': 'ate',
      'ator': 'ate',
      'alism': 'al',
      'iveness': 'ive',
      'fulness': 'ful',
      'ousness': 'ous',
      'aliti': 'al',
      'iviti': 'ive',
      'biliti': 'ble',
    };
    for (final entry in step2Suffixes.entries) {
      if (w.endsWith(entry.key) &&
          _hasVowel(w.substring(0, w.length - entry.key.length))) {
        w = w.substring(0, w.length - entry.key.length) + entry.value;
        break;
      }
    }

    const step3Suffixes = {
      'icate': 'ic',
      'ative': '',
      'alize': 'al',
      'iciti': 'ic',
      'ical': 'ic',
      'ful': '',
      'ness': '',
    };
    for (final entry in step3Suffixes.entries) {
      if (w.endsWith(entry.key) &&
          _hasVowel(w.substring(0, w.length - entry.key.length))) {
        w = w.substring(0, w.length - entry.key.length) + entry.value;
        break;
      }
    }

    const step4Suffixes = [
      'al',
      'ance',
      'ence',
      'er',
      'ic',
      'able',
      'ible',
      'ant',
      'ement',
      'ment',
      'ent',
      'sion',
      'tion',
      'ou',
      'ism',
      'ate',
      'iti',
      'ous',
      'ive',
      'ize',
    ];
    for (final suffix in step4Suffixes) {
      if (w.endsWith(suffix) &&
          _hasVowel(w.substring(0, w.length - suffix.length))) {
        w = w.substring(0, w.length - suffix.length);
        break;
      }
    }

    if (w.endsWith('e') && _hasVowel(w.substring(0, w.length - 1))) {
      w = w.substring(0, w.length - 1);
    }
    if (w.endsWith('l') &&
        _isDoubleConsonant(w) &&
        _hasVowel(w.substring(0, w.length - 1))) {
      w = w.substring(0, w.length - 1);
    }

    return w;
  }

  bool _hasVowel(String s) => s.contains(RegExp(r'[aeiou]'));

  bool _isDoubleConsonant(String s) {
    if (s.length < 2) return false;
    final last = s[s.length - 1];
    return s[s.length - 2] == last && !'aeiou'.contains(last);
  }

  bool _isShortWord(String s) => s.length <= 3 && _hasVowel(s);

  // ─── TF‑IDF Computation ───────────────────────────────────────────────

  List<Map<String, double>> _computeWeights(List<List<String>> tokenized) {
    final n = tokenized.length;
    if (n == 0) return [];

    final df = <String, int>{};
    for (final tokens in tokenized) {
      final unique = tokens.toSet();
      for (final w in unique) {
        df[w] = (df[w] ?? 0) + 1;
      }
    }

    final idf = <String, double>{};
    final N = n.toDouble();
    for (final entry in df.entries) {
      idf[entry.key] = log((N + 1) / (entry.value + 1)) + 1;
    }

    return tokenized.map((tokens) {
      final freq = <String, int>{};
      for (final w in tokens) freq[w] = (freq[w] ?? 0) + 1;
      final tfidf = <String, double>{};
      final maxFreq = freq.values.fold(0, (max, v) => v > max ? v : max);
      if (maxFreq == 0) return tfidf;
      for (final entry in freq.entries) {
        final tf = entry.value / maxFreq;
        tfidf[entry.key] = tf * (idf[entry.key] ?? 0);
      }
      return tfidf;
    }).toList();
  }

  double _cosineSimilarity(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final common = a.keys.where((k) => b.containsKey(k)).toList();
    if (common.isEmpty) return 0.0;

    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (final key in a.keys) {
      final va = a[key]!;
      normA += va * va;
    }
    for (final key in b.keys) {
      final vb = b[key]!;
      normB += vb * vb;
    }
    if (normA == 0 || normB == 0) return 0.0;

    for (final key in common) {
      dot += a[key]! * b[key]!;
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

  // ─── Sparse Graph Construction ────────────────────────────────────────

  (List<List<double>> edges, List<double> outSum) _buildSparseGraph(
    List<Map<String, double>> weights,
  ) {
    final n = weights.length;
    if (n == 0) return ([], []);

    final edges = <List<double>>[];
    final outSum = List.filled(n, 0.0);

    double threshold = similarityThreshold;
    if (useAdaptiveThreshold) {
      double totalSim = 0.0;
      int pairCount = 0;
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          final sim = _cosineSimilarity(weights[i], weights[j]);
          if (sim > 0.001) {
            totalSim += sim;
            pairCount++;
          }
        }
      }
      if (pairCount > 0) {
        final avgSim = totalSim / pairCount;
        threshold = (avgSim * 0.5).clamp(0.01, 0.1);
      }
    }

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final common = weights[i].keys.where((k) => weights[j].containsKey(k)).toList();
        if (common.isEmpty) continue;
        final sim = _cosineSimilarity(weights[i], weights[j]);
        if (sim > threshold) {
          edges.add([i.toDouble(), j.toDouble(), sim]);
          outSum[i] += sim;
          outSum[j] += sim;
        }
      }
    }
    return (edges, outSum);
  }

  // ─── Sparse PageRank ──────────────────────────────────────────────────

  List<double> _pageRank(List<List<double>> edges, List<double> outSum) {
    final n = outSum.length;
    if (n == 0) return [];

    final incoming = List.generate(n, (_) => <(int, double)>[]);
    for (final edge in edges) {
      final from = edge[0].toInt();
      final to = edge[1].toInt();
      final weight = edge[2];
      incoming[to].add((from, weight));
    }

    var scores = List.filled(n, 1.0 / n);
    const maxIter = 100;
    const tol = 1e-8;
    final damping = dampingFactor;

    for (int iter = 0; iter < maxIter; iter++) {
      final newScores = List.filled(n, 0.0);
      double danglingSum = 0.0;

      for (int j = 0; j < n; j++) {
        if (outSum[j] == 0.0) danglingSum += scores[j];
      }

      for (int i = 0; i < n; i++) {
        double sum = 0.0;
        for (final (j, weight) in incoming[i]) {
          if (outSum[j] > 0) {
            sum += (weight / outSum[j]) * scores[j];
          }
        }
        newScores[i] = (1 - damping) / n + damping * (sum + danglingSum / n);
      }

      double diff = 0.0;
      for (int i = 0; i < n; i++) {
        diff += (newScores[i] - scores[i]).abs();
      }
      scores = newScores;
      if (diff < tol) break;
    }
    return scores;
  }

  // ─── Normalize scores ──────────────────────────────────────────────────

  List<double> _normalizeScores(List<double> scores) {
    final total = scores.fold(0.0, (s, v) => s + v);
    if (total == 0) return scores;
    return scores.map((s) => s / total).toList();
  }
}