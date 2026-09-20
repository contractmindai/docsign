import '../pdf_core/object_parser.dart';
import '../pdf_core/lexer.dart' show PdfRawString;

/// The type of a resolved AcroForm field.
enum AcroFieldType {
  text,       // /Tx
  checkbox,   // /Btn (Pushbutton bit clear, Radio bit clear)
  radio,      // /Btn (Radio bit set) — group parent
  pushbutton, // /Btn (Pushbutton bit set) — not fillable
  choice,     // /Ch (dropdown / listbox)
  signature,  // /Sig
  unknown,
}

/// A resolved, fillable field in a PDF AcroForm.
class AcroFormField {
  final String partialName;
  final String fullyQualifiedName;
  final String fieldType;     // raw PDF value: '/Tx', '/Btn', '/Ch', '/Sig'
  final AcroFieldType type;   // resolved enum
  final int objectId;
  final dynamic currentValue;
  final Map<String, dynamic> rawDict;

  /// For radio groups: the widget-annotation children.
  final List<AcroFormField> radioKids;

  AcroFormField({
    required this.partialName,
    required this.fullyQualifiedName,
    required this.fieldType,
    required this.type,
    required this.objectId,
    required this.currentValue,
    required this.rawDict,
    this.radioKids = const [],
  });

  /// The available options for a /Ch field, derived from /Opt.
  /// Each entry is either a plain string or the display-name half of a
  /// [exportValue, displayName] pair.
  List<String> get choiceOptions {
    final opts = rawDict['/Opt'];
    if (opts is! List) return [];
    return opts.map((o) {
      if (o is List && o.length >= 2) return _str(o[1]);
      return _str(o);
    }).toList();
  }

  /// For radio groups: the export values for each kid (their "on" state name).
  List<String> get radioOptions {
    return radioKids.map((k) => _kidOnState(k.rawDict) ?? '/Yes').toList();
  }

  static String _str(dynamic v) {
    if (v is PdfRawString) return v.text;
    return v.toString();
  }

  static String? _kidOnState(Map<String, dynamic> kidDict) {
    final ap = kidDict['/AP'];
    if (ap is Map<String, dynamic>) {
      final n = ap['/N'];
      if (n is Map<String, dynamic>) {
        return n.keys.firstWhere((k) => k != '/Off', orElse: () => '/Yes');
      }
    }
    return null;
  }

  @override
  String toString() =>
      'FormField[$fullyQualifiedName ($fieldType / ${type.name}) ObjID: $objectId Value: $currentValue]';
}

class PdfAcroFormTreeWalker {
  final Map<int, dynamic> structuralObjectRegistry;

  PdfAcroFormTreeWalker(this.structuralObjectRegistry);

  List<AcroFormField> locateFormFields(Map<String, dynamic> catalogDictionary) {
    final List<AcroFormField> manifest = [];
    if (!catalogDictionary.containsKey('/AcroForm')) return manifest;

    final acroFormDict = _asDict(catalogDictionary['/AcroForm']);
    if (acroFormDict == null) return manifest;

    // Inherit /DR (default resources) for later use if needed
    dynamic fieldsRoot = acroFormDict['/Fields'];
    if (fieldsRoot is List<dynamic>) {
      for (var fieldRef in fieldsRoot) {
        final id = _refId(fieldRef);
        if (id != null) _walkFieldNode(id, '', manifest, acroFormDict);
      }
    }

    return manifest;
  }

  void _walkFieldNode(
    int objId,
    String parentNamePath,
    List<AcroFormField> manifest,
    Map<String, dynamic> inheritedDict,
  ) {
    final fieldDict = _asDict(structuralObjectRegistry[objId]);
    if (fieldDict == null) return;

    // Merge inheritable attributes downward: /FT, /Ff, /V, /DA, /Q
    final effectiveDict = _mergeInherited(fieldDict, inheritedDict);

    final partialName = _asString(effectiveDict['/T'] ?? fieldDict['/T']);
    final rawType = effectiveDict['/FT']?.toString() ?? '';
    final dynamic val = effectiveDict['/V'];

    final localPath = parentNamePath.isEmpty
        ? partialName
        : (partialName.isEmpty ? parentNamePath : '$parentNamePath.$partialName');

    final bool hasKids = fieldDict.containsKey('/Kids');

    // Determine if this is a radio group parent:
    //   /FT /Btn AND /Ff Radio bit (bit 16, value 32768) set AND has /Kids
    final bool isRadioParent =
        rawType == '/Btn' && _isRadioBtnParent(effectiveDict) && hasKids;

    if (isRadioParent) {
      // Collect the widget kids as radio option children
      final kids = <AcroFormField>[];
      final kidsList = fieldDict['/Kids'];
      if (kidsList is List) {
        for (var kidRef in kidsList) {
          final kidId = _refId(kidRef);
          if (kidId == null) continue;
          final kidDict = _asDict(structuralObjectRegistry[kidId]);
          if (kidDict == null) continue;
          // Kids of a radio group are widget annotations, not named sub-fields
          kids.add(AcroFormField(
            partialName: '',
            fullyQualifiedName: localPath,
            fieldType: '/Btn',
            type: AcroFieldType.radio,
            objectId: kidId,
            currentValue: kidDict['/AS'],
            rawDict: kidDict,
          ));
        }
      }

      manifest.add(AcroFormField(
        partialName: partialName,
        fullyQualifiedName: localPath,
        fieldType: '/Btn',
        type: AcroFieldType.radio,
        objectId: objId,
        currentValue: val,
        rawDict: fieldDict,
        radioKids: kids,
      ));
      return;
    }

    if (hasKids && rawType.isEmpty) {
      // Structural container node — recurse into children
      final kidsList = fieldDict['/Kids'];
      if (kidsList is List<dynamic>) {
        for (var kidRef in kidsList) {
          final kidId = _refId(kidRef);
          if (kidId != null) {
            _walkFieldNode(kidId, localPath, manifest, effectiveDict);
          }
        }
      }
      return;
    }

    // Leaf node
    if (rawType.isNotEmpty) {
      manifest.add(AcroFormField(
        partialName: partialName,
        fullyQualifiedName: localPath,
        fieldType: rawType,
        type: _resolveType(rawType, effectiveDict),
        objectId: objId,
        currentValue: val,
        rawDict: fieldDict,
      ));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  AcroFieldType _resolveType(String rawType, Map<String, dynamic> dict) {
    switch (rawType) {
      case '/Tx': return AcroFieldType.text;
      case '/Ch': return AcroFieldType.choice;
      case '/Sig': return AcroFieldType.signature;
      case '/Btn':
        final ff = _ff(dict);
        if (ff & (1 << 16) != 0) return AcroFieldType.pushbutton; // bit 17
        if (ff & (1 << 15) != 0) return AcroFieldType.radio;       // bit 16
        return AcroFieldType.checkbox;
      default:
        return AcroFieldType.unknown;
    }
  }

  bool _isRadioBtnParent(Map<String, dynamic> dict) {
    // Radio bit is bit 16 (0-indexed), i.e. value 1<<15 = 32768
    return _ff(dict) & (1 << 15) != 0;
  }

  int _ff(Map<String, dynamic> dict) {
    final ff = dict['/Ff'];
    if (ff is num) return ff.toInt();
    return 0;
  }

  /// Merges inheritable PDF field attributes from parent into child dict.
  /// Child values always win; we only copy keys missing from the child.
  Map<String, dynamic> _mergeInherited(
      Map<String, dynamic> child, Map<String, dynamic> parent) {
    const inheritable = ['/FT', '/Ff', '/V', '/DV', '/DA', '/Q', '/DR'];
    final merged = Map<String, dynamic>.from(child);
    for (final key in inheritable) {
      if (!merged.containsKey(key) && parent.containsKey(key)) {
        merged[key] = parent[key];
      }
    }
    return merged;
  }

  int? _refId(dynamic ref) {
    if (ref is PdfIndirectReference) return ref.objectId;
    if (ref is int) return ref;
    return null;
  }

  Map<String, dynamic>? _asDict(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is PdfIndirectReference) {
      return _asDict(structuralObjectRegistry[value.objectId]);
    }
    return null;
  }

  String _asString(dynamic value) {
    if (value == null) return '';
    if (value is PdfRawString) return value.text;
    return value.toString();
  }
}
