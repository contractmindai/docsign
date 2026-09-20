/// Subset of the Adobe Glyph List — the mapping from PostScript glyph names
/// (as they appear in a PDF font's `/Encoding /Differences` array) to the
/// Unicode character each name represents.
///
/// The full list has ~4000 entries; this covers the printable ASCII range,
/// which is what 99 % of business documents use. Add more entries if you
/// encounter documents that render non-Latin scripts with custom encodings.
const Map<String, String> kAdobeGlyphToUnicode = {
  // Control names that appear in some subset fonts.
  'space': ' ',

  // ASCII punctuation
  'exclam': '!',
  'quotedbl': '"',
  'numbersign': '#',
  'dollar': r'$',
  'percent': '%',
  'ampersand': '&',
  'quotesingle': "'",
  'parenleft': '(',
  'parenright': ')',
  'asterisk': '*',
  'plus': '+',
  'comma': ',',
  'hyphen': '-',
  'period': '.',
  'slash': '/',
  'colon': ':',
  'semicolon': ';',
  'less': '<',
  'equal': '=',
  'greater': '>',
  'question': '?',
  'at': '@',
  'bracketleft': '[',
  'backslash': r'\',
  'bracketright': ']',
  'asciicircum': '^',
  'underscore': '_',
  'grave': '`',
  'braceleft': '{',
  'bar': '|',
  'braceright': '}',
  'asciitilde': '~',

  // Digits
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',

  // Uppercase Latin
  'A': 'A', 'B': 'B', 'C': 'C', 'D': 'D', 'E': 'E', 'F': 'F',
  'G': 'G', 'H': 'H', 'I': 'I', 'J': 'J', 'K': 'K', 'L': 'L',
  'M': 'M', 'N': 'N', 'O': 'O', 'P': 'P', 'Q': 'Q', 'R': 'R',
  'S': 'S', 'T': 'T', 'U': 'U', 'V': 'V', 'W': 'W', 'X': 'X',
  'Y': 'Y', 'Z': 'Z',

  // Lowercase Latin
  'a': 'a', 'b': 'b', 'c': 'c', 'd': 'd', 'e': 'e', 'f': 'f',
  'g': 'g', 'h': 'h', 'i': 'i', 'j': 'j', 'k': 'k', 'l': 'l',
  'm': 'm', 'n': 'n', 'o': 'o', 'p': 'p', 'q': 'q', 'r': 'r',
  's': 's', 't': 't', 'u': 'u', 'v': 'v', 'w': 'w', 'x': 'x',
  'y': 'y', 'z': 'z',

  // A few common extras that show up in invoices / forms
  'endash': '–',
  'emdash': '—',
  'quoteright': '\u2019',
  'quoteleft': '\u2018',
  'quotedblleft': '\u201C',
  'quotedblright': '\u201D',
  'bullet': '•',
  'periodcentered': '·',
  'ellipsis': '…',
  'degree': '°',
  'sterling': '£',
  'Euro': '€',
  'yen': '¥',
  'cent': '¢',
  'section': '§',
  'paragraph': '¶',
  'dagger': '†',
  'daggerdbl': '‡',
  'copyright': '©',
  'registered': '®',
  'trademark': '™',
};