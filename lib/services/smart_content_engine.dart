import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────
// SmartContentEngine
//
// A fully LOCAL, OFFLINE "intelligence" layer for the template forms.
// No network calls, no LLM/API keys — everything below is deterministic
// and algorithmic:
//   1) SmartSuggestions — fuzzy prefix/substring/edit-distance autocomplete
//      over curated word banks, so fields feel like they "know" common
//      values (job titles, skills, expense categories, etc).
//   2) SmartWriter — rule-based paragraph assembly. It reads whatever the
//      user has already typed into *other* fields on the same form and
//      stitches together professionally-worded sentences from weighted
//      phrase banks. A seeded RNG (seeded from the input itself) picks
//      which phrasing to use, so the same inputs always produce the same
//      output (deterministic + reproducible), but different inputs get
//      natural variety instead of one canned sentence.
//   3) TemplateDescriptions — computed one-line blurbs for the template
//      gallery cards, generated from a small rules table rather than
//      hard-coded per card.
// ─────────────────────────────────────────────────────────────────────────

/// ---------------------------------------------------------------------
/// 1. FUZZY AUTOCOMPLETE
/// ---------------------------------------------------------------------
class SmartSuggestions {
  SmartSuggestions._();

  static final Map<String, List<String>> _banks = {
    'jobTitle': [
      'Software Engineer', 'Product Manager', 'Marketing Manager', 'Sales Executive',
      'Graphic Designer', 'Data Analyst', 'Financial Analyst', 'Operations Manager',
      'HR Manager', 'Customer Success Manager', 'Project Manager', 'UX Designer',
      'Accountant', 'Business Analyst', 'Content Writer', 'Executive Assistant',
      'Registered Nurse', 'Teacher', 'Civil Engineer', 'Mechanical Engineer',
      'Chef', 'Waiter / Waitress', 'Barista', 'Store Manager', 'Warehouse Supervisor',
      'Administrative Assistant', 'IT Support Specialist', 'Recruiter', 'Paralegal',
    ],
    'skill': [
      'Communication', 'Leadership', 'Problem Solving', 'Time Management', 'Teamwork',
      'Project Management', 'Microsoft Excel', 'Python', 'JavaScript', 'Flutter',
      'SQL', 'Data Analysis', 'Customer Service', 'Negotiation', 'Public Speaking',
      'Adobe Photoshop', 'Figma', 'Salesforce', 'SEO', 'Content Marketing',
      'Budgeting', 'Bookkeeping', 'Conflict Resolution', 'Critical Thinking',
      'Attention to Detail', 'Adaptability', 'Sales', 'Java', 'React', 'Node.js',
    ],
    'expenseCategory': [
      'Travel', 'Meals & Entertainment', 'Lodging', 'Office Supplies', 'Software Subscription',
      'Client Gift', 'Transportation', 'Parking & Tolls', 'Conference Fee',
      'Training & Education', 'Internet & Phone', 'Postage & Shipping', 'Fuel',
    ],
    'menuCategory': ['Appetizers', 'Mains', 'Desserts', 'Beverages', 'Specials'],
    'role': [
      'Waiter', 'Waitress', 'Chef', 'Sous Chef', 'Line Cook', 'Barista', 'Cashier',
      'Host / Hostess', 'Dishwasher', 'Shift Supervisor', 'Store Manager', 'Sales Associate',
    ],
    'department': [
      'Engineering', 'Marketing', 'Sales', 'Finance', 'Human Resources', 'Operations',
      'Customer Support', 'Legal', 'IT', 'Product', 'Design',
    ],
    'company': [
      'Acme Corp', 'Globex Inc.', 'Initech', 'Umbrella Corporation', 'Stark Industries',
    ],
  };

  /// Ranked fuzzy suggestions: exact prefix hits first, then substring hits,
  /// then close edit-distance hits — capped to [limit]. Pure string
  /// algorithms, no model involved.
  static List<String> suggest(String fieldKey, String query, {int limit = 6}) {
    final bank = _banks[fieldKey];
    if (bank == null || query.trim().isEmpty) return const [];
    final q = query.toLowerCase().trim();
    final prefix = <String>[];
    final substr = <String>[];
    final fuzzy = <MapEntry<String, int>>[];

    for (final entry in bank) {
      final low = entry.toLowerCase();
      if (low.startsWith(q)) {
        prefix.add(entry);
      } else if (low.contains(q)) {
        substr.add(entry);
      } else {
        final clipped = low.length > q.length ? low.substring(0, q.length) : low;
        final dist = _levenshtein(q, clipped);
        if (dist <= 2) fuzzy.add(MapEntry(entry, dist));
      }
    }
    fuzzy.sort((a, b) => a.value.compareTo(b.value));
    final out = [...prefix, ...substr, ...fuzzy.map((e) => e.key)];
    return out.toSet().take(limit).toList();
  }

  static bool hasBank(String fieldKey) => _banks.containsKey(fieldKey);

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var v0 = List<int>.generate(b.length + 1, (i) => i);
    var v1 = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce(min);
      }
      for (var j = 0; j < v0.length; j++) v0[j] = v1[j];
    }
    return v1[b.length];
  }
}

/// ---------------------------------------------------------------------
/// 2. RULE-BASED TEXT GENERATION ("auto-write" for long-text fields)
/// ---------------------------------------------------------------------
class SmartWriter {
  SmartWriter._();

  /// Deterministic RNG seeded from the context, so the same field values
  /// always produce the same generated text, while different inputs get
  /// varied phrasing (weighted random pick from a phrase bank).
  static Random _seededRandom(Map<String, String> context) {
    final seed = context.values.join('|').hashCode;
    return Random(seed);
  }

  static String _pick(Random r, List<String> options) => options[r.nextInt(options.length)];

  /// Helper to format a party name with a default if empty.
  static String _formatName(String name, String defaultName) =>
      name.trim().isEmpty ? defaultName : name.trim();

  /// Legal document disclaimer (appended to generated legal text).
  static const String _legalDisclaimer = '''
  
  LEGAL DISCLAIMER: This document is a template provided for general informational and document-preparation purposes only. It is not legal advice and does not create an attorney-client relationship. Laws and enforceability may vary by state, country, and individual circumstances. Review the document carefully and consult a qualified attorney before signing or relying on it.
  ''';

  /// Composes a multi‑clause text from categories of variants, keeping the
  /// structure fixed (one clause per category) but varying the phrasing.
  /// Each category is a list of variant sentences; one is picked per category.
  static String _composeClauses(Random r, List<List<String>> categories, {String join = '\n\n'}) {
    return categories.map((variants) => _pick(r, variants)).join(join);
  }

  // ---- Invoice / Quotation notes -------------------------------------
  static String invoiceNotes({required String clientName, required String dueDate}) {
    final ctx = {'clientName': clientName, 'dueDate': dueDate};
    final r = _seededRandom(ctx);
    final name = _formatName(clientName, 'the Client');
    return _composeClauses(r, [
      [
        'Thank you for your business, $name.',
        'We appreciate the opportunity to work with $name.',
        'Thank you for choosing us, $name — it\'s been a pleasure.',
      ],
      [
        'Payment is due by $dueDate. Late payments may be subject to a 1.5% monthly fee.',
        'Please remit payment on or before $dueDate. A late fee may apply to overdue balances.',
        'Kindly settle this invoice by $dueDate to avoid any late fees or service interruption.',
      ],
      [
        'Any disputes regarding this invoice should be raised within 7 days of receipt.',
        'Please review the line items carefully and contact us promptly with any discrepancies.',
        'This invoice is considered accepted if no dispute is raised within 7 days.',
      ],
      [
        'Please reach out with any questions regarding this invoice.',
        'We\'re happy to answer any questions about this invoice.',
        'Contact us anytime if anything here needs clarifying.',
      ],
    ], join: ' ');
  }

  static String quotationNotes({required String validUntil}) {
    final ctx = {'validUntil': validUntil};
    final r = _seededRandom(ctx);
    return _composeClauses(r, [
      [
        'This quotation is valid until $validUntil. Prices are subject to change thereafter.',
        'Please note this quote is valid through $validUntil and is not a final invoice.',
        'Pricing above is guaranteed until $validUntil. Contact us to confirm before proceeding.',
      ],
      [
        'A deposit may be required to confirm the order once accepted.',
        'Work will begin upon written acceptance of this quotation.',
        'Final pricing may vary if the scope of work changes after acceptance.',
      ],
    ], join: ' ');
  }

  // ---- Expense description -------------------------------------------
  static String expenseDescription({required String category}) {
    final ctx = {'category': category};
    final r = _seededRandom(ctx);
    final cat = category.trim().isEmpty ? 'General' : category.trim();
    final templates = [
      '$cat expense incurred in the course of business duties.',
      'Business-related $cat expense, receipt available on request.',
      '$cat cost associated with an approved work activity.',
    ];
    return _pick(r, templates);
  }

  // ---- Service Agreement (strong, structured) -------------------------
  static String serviceAgreement({
    required String provider,
    required String client,
    required String serviceName,
  }) {
    final ctx = {'provider': provider, 'client': client, 'serviceName': serviceName};
    final r = _seededRandom(ctx);
    final p = _formatName(provider, 'the Provider');
    final c = _formatName(client, 'the Client');
    final svc = serviceName.trim().isEmpty ? 'the Services' : serviceName.trim();

    final clauses = [
      // 1. Scope of Services
      [
        '1. Scope of Services\n$p will provide $svc as described in this Agreement or the applicable statement of work. Any material change to the scope, deliverables, or timeline must be agreed upon by both parties in writing.',
        '1. Scope of Services\n$p agrees to perform $svc according to the specifications in this Agreement. Changes to the scope may be made only by written amendment signed by both parties.',
      ],
      // 2. Fees and Payment
      [
        '2. Fees and Payment\n$c agrees to pay the fees specified in this Agreement according to the stated payment schedule. Additional services requested outside the agreed scope may be subject to additional charges upon written approval.',
        '2. Fees and Payment\nAll fees are set forth in this Agreement. $c shall pay invoices within the payment period shown. Work outside the scope will be billed at the standard rate with prior written consent.',
      ],
      // 3. Term and Termination
      [
        '3. Term and Termination\nThis Agreement will remain in effect for the period stated above unless terminated earlier in accordance with its terms. Either party may terminate the Agreement by providing the required written notice. Termination does not relieve either party of obligations that accrued before the effective termination date.',
        '3. Term and Termination\nThe term of this Agreement begins on the effective date and continues as specified. Either party may terminate with written notice if the other materially breaches and fails to cure within the notice period. Fees for work performed up to termination remain payable.',
      ],
      // 4. Client Responsibilities
      [
        '4. Client Responsibilities\nThe Client agrees to provide information, approvals, access, and other reasonable cooperation necessary for the Provider to perform the Services.',
        '4. Client Responsibilities\n$c shall timely furnish all materials, data, and decisions needed for $p to deliver the Services. Delays caused by $c may extend the timeline and increase costs.',
      ],
      // 5. Intellectual Property
      [
        '5. Intellectual Property\nUpon full payment, ownership of final deliverables specifically created for the Client under this Agreement will transfer to the Client, except for pre-existing materials, tools, templates, methods, know-how, and third-party materials owned or licensed by the Provider.',
        '5. Intellectual Property\n$p retains ownership of all pre‑existing intellectual property and general tools. Deliverables created specifically for $c become $c\'s property upon full payment. $p grants $c a perpetual, non‑exclusive license to use any background IP necessary to operate the deliverables.',
      ],
      // 6. Confidentiality
      [
        '6. Confidentiality\nEach party agrees to protect confidential information received from the other party and to use such information only for purposes related to this Agreement.',
        '6. Confidentiality\nConfidential information includes business plans, financial data, customer lists, and technical materials. The receiving party must use reasonable care to prevent disclosure and may only share with employees who need to know.',
      ],
      // 7. Limitation of Liability
      [
        '7. Limitation of Liability\nTo the extent permitted by applicable law, neither party will be liable for indirect, incidental, special, consequential, or punitive damages arising out of or relating to this Agreement.',
        '7. Limitation of Liability\nEach party\'s total liability under this Agreement is limited to the total fees paid by $c in the 12 months preceding the claim. This limitation does not apply to gross negligence, fraud, or breaches of confidentiality.',
      ],
      // 8. Governing Law
      [
        '8. Governing Law\nThis Agreement will be governed by the laws of the jurisdiction specified in the Agreement, without regard to conflict-of-law principles.',
        '8. Governing Law\nThe laws of the state or country designated in the Agreement control its interpretation and enforcement. The parties consent to the exclusive jurisdiction of the courts in that location.',
      ],
      // 9. Entire Agreement
      [
        '9. Entire Agreement\nThis Agreement, together with any referenced schedules or statements of work, constitutes the entire agreement between the parties concerning the Services and supersedes prior discussions or understandings relating to the same subject matter.',
        '9. Entire Agreement\nThis Agreement and its attachments are the complete and final expression of the parties\' agreement. No prior statements, representations, or communications are binding unless incorporated herein.',
      ],
      // 10. Amendments
      [
        '10. Amendments\nAny amendment or modification to this Agreement must be made in writing and agreed to by both parties.',
        '10. Amendments\nNo amendment is effective unless signed by both parties. Waiver of any breach does not waive future breaches.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Freelance Contract (structured) --------------------------------
  static String freelanceContract({required String freelancer, required String client}) {
    final ctx = {'freelancer': freelancer, 'client': client};
    final r = _seededRandom(ctx);
    final who = _formatName(freelancer, 'the Freelancer');
    final c = _formatName(client, 'the Client');

    final clauses = [
      // 1. Scope of Work
      [
        '1. Scope of Work\n$who will perform the work described in this Agreement or the attached statement of work. All deliverables and deadlines are as specified.',
        '1. Scope of Work\nThe scope covers all tasks reasonably required to complete the project as outlined. Any changes require a written amendment.',
      ],
      // 2. Deliverables
      [
        '2. Deliverables\n$who will deliver the final work product in the format and on the schedule agreed. The Client will have the opportunity to review and accept deliverables.',
        '2. Deliverables\nDeliverables will be provided according to the timeline. Acceptance criteria are defined in the scope document.',
      ],
      // 3. Timeline
      [
        '3. Timeline\nThe project will begin on the start date and continue until completion of all deliverables. $who will provide progress updates regularly.',
        '3. Timeline\n$who commits to delivering by the deadlines shown. Delays caused by $c may extend the timeline.',
      ],
      // 4. Fees
      [
        '4. Fees\n$c agrees to pay the fees as described in the payment schedule. Additional work outside scope will be billed at the agreed hourly rate.',
        '4. Fees\nPayment is due upon invoice. Late payments may incur interest as permitted by law.',
      ],
      // 5. Revisions
      [
        '5. Revisions\nUp to two rounds of revisions are included at no extra cost. Additional revisions may be billed at the rate set forth herein.',
        '5. Revisions\nReasonable revisions to ensure deliverable acceptance are included. Excess revisions may require a change order.',
      ],
      // 6. Client Responsibilities
      [
        '6. Client Responsibilities\n$c will provide timely feedback, approvals, and access to necessary resources. Delays by $c may affect the schedule.',
        '6. Client Responsibilities\n$c is responsible for providing complete and accurate information. Failure to do so may result in additional fees.',
      ],
      // 7. Independent Contractor Status
      [
        '7. Independent Contractor\n$who is an independent contractor, not an employee. $who is responsible for all taxes, insurance, and benefits.',
        '7. Independent Contractor\n$who controls the manner and means of performing the work. $who is not entitled to employee benefits or workers\' compensation.',
      ],
      // 8. Intellectual Property
      [
        '8. Intellectual Property\nUpon full payment, all deliverables created specifically for $c become $c\'s property. $who retains ownership of pre‑existing materials and tools.',
        '8. Intellectual Property\n$c owns the final work product after payment. $who grants a non‑exclusive license to use any background IP needed to operate the deliverables.',
      ],
      // 9. Confidentiality
      [
        '9. Confidentiality\n$who agrees to protect confidential information received from $c and not to disclose it except as needed to perform the work.',
        '9. Confidentiality\nBoth parties will keep confidential all non‑public information disclosed during the engagement.',
      ],
      // 10. Termination
      [
        '10. Termination\nEither party may terminate this Agreement with written notice. $c will pay for work performed up to the termination date.',
        '10. Termination\nThis Agreement may be terminated by either party for convenience with reasonable notice. In case of material breach, the non‑breaching party may terminate immediately.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Rental Agreement (structured) ----------------------------------
  static String rentalAgreement({required String property, required String landlord, required String tenant}) {
    final ctx = {'property': property, 'landlord': landlord, 'tenant': tenant};
    final r = _seededRandom(ctx);
    final prop = property.trim().isEmpty ? 'the Property' : property.trim();

    final clauses = [
      // Property
      [
        '1. Property\nThe landlord leases to the tenant the premises described as: $prop.',
        '1. Property\n$prop is leased for residential purposes only, subject to the terms of this Agreement.',
      ],
      // Rent
      [
        '2. Rent\nThe tenant shall pay rent in the amount and on the schedule stated. Rent is due on the 1st of each month.',
        '2. Rent\nMonthly rent is set forth above, payable at the landlord\'s address. A late fee may apply if rent is not received within 5 days of the due date.',
      ],
      // Security Deposit
      [
        '3. Security Deposit\nThe tenant has paid a security deposit equivalent to one month\'s rent, to be held and returned subject to applicable law and deductions for damage.',
        '3. Security Deposit\nA deposit of the specified amount secures performance. It will be refunded within the time required by law, less any lawful deductions.',
      ],
      // Utilities
      [
        '4. Utilities\nThe tenant is responsible for all utility charges except those the landlord agrees to pay, as specified.',
        '4. Utilities\nWater, gas, electric, and other services shall be paid by the tenant unless otherwise agreed.',
      ],
      // Maintenance
      [
        '5. Maintenance\nThe tenant shall keep the premises clean and in good repair, ordinary wear and tear excepted. The landlord is responsible for major repairs.',
        '5. Maintenance\nTenant shall promptly report any damage or needed repairs. Landlord will maintain structural elements and essential systems.',
      ],
      // Occupancy
      [
        '6. Occupancy\nOnly the tenant and those listed on the lease may occupy the premises. No subletting without written consent.',
        '6. Occupancy\nThe premises are for the tenant\'s personal use. Guests are allowed for short periods only.',
      ],
      // Subletting
      [
        '7. Subletting\nSubletting or assignment is prohibited without the landlord\'s prior written approval.',
        '7. Subletting\nTenant may not sublet any part of the premises or assign this Agreement without written permission.',
      ],
      // Pets
      [
        '8. Pets\nNo animals are permitted unless specifically allowed in writing, with a pet deposit if required.',
        '8. Pets\nPets are allowed only with the landlord\'s consent and subject to additional fees or conditions.',
      ],
      // Late Payment
      [
        '9. Late Payment\nIf rent is not paid by the 5th, a late fee of \$50 or 5% of the monthly rent, whichever is greater, will be charged.',
        '9. Late Payment\nA late fee, as specified in the Agreement, will apply to payments received after the due date.',
      ],
      // Entry
      [
        '10. Entry\nThe landlord may enter the premises upon reasonable notice, for inspections, repairs, or showings.',
        '10. Entry\nLandlord may enter with at least 24 hours notice, except in emergencies.',
      ],
      // Termination
      [
        '11. Termination\nThe tenant or landlord may terminate this lease by giving written notice as required by law. Early termination may incur fees.',
        '11. Termination\nThis Agreement terminates on the end date. Either party may terminate earlier for material breach or by mutual consent.',
      ],
      // Move-Out
      [
        '12. Move-Out\nUpon moving out, tenant shall return the premises in broom‑clean condition and remove all personal property.',
        '12. Move-Out\nTenant must vacate by the termination date and leave the premises clean and undamaged (normal wear excepted).',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- NDA (structured) ----------------------------------------------
  static String nonDisclosureAgreement({required String disclosingParty, required String receivingParty}) {
    final ctx = {'disclosingParty': disclosingParty, 'receivingParty': receivingParty};
    final r = _seededRandom(ctx);
    final dp = _formatName(disclosingParty, 'the Disclosing Party');
    final rp = _formatName(receivingParty, 'the Receiving Party');

    final clauses = [
      // Purpose
      [
        '1. Purpose\nThis Agreement is entered into to facilitate discussion between $dp and $rp regarding a potential business relationship. Confidential information will be shared for that purpose.',
        '1. Purpose\nThe parties wish to explore a collaboration and agree to protect confidential information exchanged for that purpose.',
      ],
      // Definition of Confidential Information
      [
        '2. Definition of Confidential Information\nConfidential Information includes all non‑public business, technical, financial, and operational information disclosed by $dp to $rp, whether oral, written, or electronic.',
        '2. Definition\nConfidential Information comprises trade secrets, customer lists, financial data, and any materials marked as confidential.',
      ],
      // Exclusions
      [
        '3. Exclusions\nInformation that is publicly known, independently developed without use of confidential information, or lawfully received from a third party is not covered.',
        '3. Exclusions\nConfidential Information does not include data already in the public domain or that becomes public through no fault of the receiving party.',
      ],
      // Permitted Use
      [
        '4. Permitted Use\n$rp shall use the Confidential Information solely for evaluating the potential relationship and shall not use it for any other purpose.',
        '4. Permitted Use\nConfidential Information may be used only for the purpose of evaluating the proposed transaction or collaboration.',
      ],
      // Required Disclosure
      [
        '5. Required Disclosure\nIf $rp is compelled by law to disclose Confidential Information, it will provide $dp with prompt notice and cooperate in seeking a protective order.',
        '5. Required Disclosure\nDisclosure required by court order or regulatory authority is permitted, provided $rp notifies $dp in advance and limits disclosure to the required extent.',
      ],
      // Return/Destruction
      [
        '6. Return/Destruction\nUpon request or termination of discussions, $rp shall promptly return or destroy all copies of Confidential Information and certify compliance.',
        '6. Return/Destruction\nAll materials containing Confidential Information must be returned or destroyed upon the disclosing party\'s demand or when the purpose ends.',
      ],
      // Duration
      [
        '7. Duration\nThis Agreement remains in effect for [X] years from the effective date. Obligations of confidentiality survive for [Y] years after the last disclosure.',
        '7. Duration\nThe confidentiality obligations last for the term of this Agreement and [Z] years thereafter, or indefinitely for trade secrets.',
      ],
      // Remedies
      [
        '8. Remedies\nBreach of this Agreement may cause irreparable harm, and the disclosing party may seek injunctive relief in addition to other remedies.',
        '8. Remedies\nIn the event of breach, the aggrieved party may pursue all legal and equitable remedies, including damages and specific performance.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Non‑Compete (structured) --------------------------------------
  static String nonCompete({required String company, required String employee}) {
    final ctx = {'company': company, 'employee': employee};
    final r = _seededRandom(ctx);
    final c = _formatName(company, 'the Company');
    final e = _formatName(employee, 'the Employee');

    final clauses = [
      // Scope
      [
        '1. Scope\nThis restriction applies to any business that directly competes with $c within the geographic area and for the duration set forth. $e agrees not to engage in such competitive activities.',
        '1. Scope\n$e shall not, during the restricted period, work for or own a business that competes with $c in the defined territory.',
      ],
      // Non‑Solicitation
      [
        '2. Non‑Solicitation\n$e agrees not to solicit any client or employee of $c during the restricted period.',
        '2. Non‑Solicitation\n$e shall not induce any customer, vendor, or employee of $c to terminate their relationship.',
      ],
      // Legitimate Interest
      [
        '3. Legitimate Interest\nThis clause is intended to protect $c\'s legitimate business interests, including trade secrets and customer relationships, and is limited to what is reasonably necessary.',
        '3. Legitimate Interest\nThe restrictions are narrowly tailored to safeguard $c\'s confidential information and goodwill.',
      ],
      // Severability
      [
        '4. Severability\nIf any part of this clause is found unenforceable, the remainder will still apply to the fullest extent permitted by law.',
        '4. Severability\nShould a court invalidate a portion of this restriction, the parties agree to modify it to the minimum extent necessary to make it enforceable.',
      ],
      // Consideration
      [
        '5. Consideration\n$e acknowledges that they have received adequate consideration for this covenant, including the offer of employment and compensation.',
        '5. Consideration\nThis Agreement is supported by continued employment and/or the compensation described in the employment terms.',
      ],
      // Remedies
      [
        '6. Remedies\n$c may seek injunctive relief and damages for any breach of this clause.',
        '6. Remedies\nIn case of breach, $c shall be entitled to seek all legal and equitable remedies.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Offer Letter (full, structured) -------------------------------
  static String offerLetter({
    required String company,
    required String candidate,
    required String position,
    required String startDate,
    required String salary,
  }) {
    final ctx = {'company': company, 'candidate': candidate, 'position': position, 'startDate': startDate, 'salary': salary};
    final r = _seededRandom(ctx);
    final comp = _formatName(company, 'the Company');
    final cand = _formatName(candidate, 'the Candidate');
    final role = position.trim().isEmpty ? 'the position' : position.trim();
    final start = startDate.trim().isEmpty ? '[Start Date]' : startDate.trim();
    final pay = salary.trim().isEmpty ? '[Salary]' : salary.trim();

    final clauses = [
      // Offer
      [
        '1. Offer of Employment\n$comp is pleased to offer you the position of $role, reporting to [Manager Name]. Your start date will be $start.',
        '1. Offer\nThis letter confirms our offer to you for the role of $role, effective $start. You will report to [Supervisor].',
      ],
      // Position and Duties
      [
        '2. Position and Duties\nYou will perform the duties customary for $role, as outlined in the attached job description. $comp may assign additional responsibilities consistent with your role.',
        '2. Position and Duties\nYour primary responsibilities are described in the job description. You agree to perform them diligently and to follow company policies.',
      ],
      // Compensation
      [
        '3. Compensation\nYour base salary will be $pay per [year/hour], payable [bi‑weekly/monthly] in accordance with $comp\'s payroll schedule.',
        '3. Compensation\nThe offered compensation is $pay, subject to applicable withholdings and deductions. You will be paid on a regular basis.',
      ],
      // Benefits
      [
        '4. Benefits\nYou will be eligible for $comp\'s standard benefits package, including health insurance, paid time off, and retirement plans, subject to plan terms and eligibility requirements.',
        '4. Benefits\nAs a regular employee, you may participate in the company\'s benefits programs, details of which will be provided during onboarding.',
      ],
      // At-Will Employment
      [
        '5. At-Will Employment\nYour employment is at-will, meaning either you or $comp may terminate the relationship at any time, with or without cause or advance notice.',
        '5. At-Will\nThis is an at-will employment relationship, and nothing in this offer changes that status.',
      ],
      // Contingencies
      [
        '6. Contingencies\nThis offer is contingent upon successful completion of a background check, reference verification, and proof of your legal right to work.',
        '6. Contingencies\nYour start date is subject to you providing the required documents and clearances.',
      ],
      // Confidentiality and IP
      [
        '7. Confidentiality and Intellectual Property\nAs a condition of employment, you will sign the company\'s standard confidentiality and intellectual property assignment agreement.',
        '7. Confidentiality\nYou agree to protect all confidential information and assign to $comp any IP created during your employment.',
      ],
      // Acceptance
      [
        '8. Acceptance\nTo accept this offer, please sign and return this letter by the deadline stated above. Your acceptance confirms your agreement to all terms.',
        '8. Acceptance\nPlease indicate your acceptance by signing below and returning this letter to HR by [Deadline].',
      ],
      // Expiration
      [
        '9. Expiration\nThis offer expires on [Deadline]. If we do not receive your acceptance by then, this offer will be withdrawn.',
        '9. Expiration\nThis offer is valid for [X] days from the date above. After that, it may be rescinded.',
      ],
      // Entire Agreement
      [
        '10. Entire Agreement\nThis letter, together with the attached documents, constitutes the entire offer and supersedes all prior communications.',
        '10. Entire Agreement\nThis offer contains all terms and conditions of employment and may only be amended in writing.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Employment Contract (full, structured) -------------------------
  static String employmentContract({
    required String company,
    required String employee,
    required String position,
    required String salary,
  }) {
    final ctx = {'company': company, 'employee': employee, 'position': position, 'salary': salary};
    final r = _seededRandom(ctx);
    final comp = _formatName(company, 'the Company');
    final emp = _formatName(employee, 'the Employee');
    final role = position.trim().isEmpty ? 'the position' : position.trim();
    final pay = salary.trim().isEmpty ? '[Salary]' : salary.trim();

    final clauses = [
      // Position and Duties
      [
        '1. Position and Duties\n$emp is employed as $role and agrees to perform the duties described in the job description. $comp may modify duties consistent with the role.',
        '1. Position and Duties\n$emp shall serve as $role and undertake the responsibilities assigned by the employer.',
      ],
      // Compensation
      [
        '2. Compensation\n$comp agrees to pay $emp a salary of $pay, less deductions, in accordance with the standard payroll schedule.',
        '2. Compensation\nThe employee\'s base compensation is $pay, subject to applicable taxes and withholdings.',
      ],
      // Benefits
      [
        '3. Benefits\n$emp is eligible for the company benefits as described in the employee handbook, subject to change and plan terms.',
        '3. Benefits\nBenefits include health, retirement, and leave programs as per company policy.',
      ],
      // At-Will
      [
        '4. At-Will Employment\nThis employment is at-will and may be terminated by either party at any time, with or without cause or notice.',
        '4. At-Will\nNeither this contract nor any other communication creates a guaranteed term of employment.',
      ],
      // Confidentiality
      [
        '5. Confidentiality\n$emp agrees not to disclose any confidential information acquired during employment, both during and after the employment period.',
        '5. Confidentiality\nTrade secrets and proprietary data must be kept confidential and used only for company business.',
      ],
      // Non-Compete
      [
        '6. Non-Compete\n$emp shall not engage in any activity that competes with $comp during employment and for [X] months following termination.',
        '6. Non-Compete\nDuring and after employment, $emp will not work for a direct competitor within the defined geographic area.',
      ],
      // IP Assignment
      [
        '7. Intellectual Property\nAny work product, inventions, or intellectual property created by $emp in the scope of employment are the sole property of $comp.',
        '7. IP Ownership\nAll IP developed by $emp during employment is assigned to $comp without further compensation.',
      ],
      // Termination
      [
        '8. Termination\nEither party may terminate this Agreement with written notice as required by law. Upon termination, $emp will return all company property.',
        '8. Termination\nThis Agreement ends on the termination date. Obligations of confidentiality and IP assignment survive termination.',
      ],
      // Governing Law
      [
        '9. Governing Law\nThis Agreement shall be governed by the laws of [State/Country], without regard to its conflict of laws.',
        '9. Governing Law\nAny disputes arising under this Agreement will be resolved in the courts of [Jurisdiction].',
      ],
      // Entire Agreement
      [
        '10. Entire Agreement\nThis Agreement, with any referenced policies, constitutes the entire contract between the parties and supersedes all prior agreements.',
        '10. Entire Agreement\nThis document is the complete understanding of the parties and can only be amended in writing.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Terms and Conditions (generic, structured) --------------------
  static String termsAndConditions({
    required String company,
    required String serviceName,
  }) {
    final ctx = {'company': company, 'serviceName': serviceName};
    final r = _seededRandom(ctx);
    final comp = _formatName(company, 'the Company');
    final svc = serviceName.trim().isEmpty ? 'the Service' : serviceName.trim();

    final clauses = [
      // Acceptance of Terms
      [
        '1. Acceptance of Terms\nBy using $svc, you agree to be bound by these Terms and Conditions. If you do not agree, do not use $svc.',
        '1. Acceptance\nYour access to $svc constitutes acceptance of these terms. We may update them from time to time.',
      ],
      // User Accounts
      [
        '2. User Accounts\nYou may need to create an account to access certain features. You are responsible for maintaining the confidentiality of your credentials.',
        '2. Accounts\nAccounts are personal and non‑transferable. You must notify us of any unauthorized use.',
      ],
      // Intellectual Property
      [
        '3. Intellectual Property\nAll content and materials on $svc, including logos, text, and graphics, are owned by $comp and protected by copyright and trademark laws.',
        '3. IP Rights\n$comp retains all rights in the software and content. You may not copy, modify, or distribute any part without permission.',
      ],
      // User Content
      [
        '4. User Content\nYou retain ownership of content you submit, but you grant $comp a worldwide, royalty‑free license to use, store, and display it as necessary to provide $svc.',
        '4. User Content\nBy posting content, you allow $comp to use it for operating and improving the service.',
      ],
      // Prohibited Conduct
      [
        '5. Prohibited Conduct\nYou agree not to use $svc for unlawful purposes, to harass others, or to interfere with the service\'s operation.',
        '5. Prohibited Activities\nYou may not engage in fraud, spamming, or any activity that harms $svc or its users.',
      ],
      // Third-Party Links
      [
        '6. Third-Party Links\n$svc may contain links to third‑party websites. $comp is not responsible for their content or practices.',
        '6. External Links\nWe do not endorse or control third‑party sites; use them at your own risk.',
      ],
      // Disclaimers
      [
        '7. Disclaimers\n$svc is provided "as is" without warranties of any kind, express or implied. $comp does not guarantee that the service will be error‑free or uninterrupted.',
        '7. Disclaimer of Warranties\nTo the fullest extent permitted by law, $comp disclaims all warranties, including merchantability and fitness for a particular purpose.',
      ],
      // Limitation of Liability
      [
        '8. Limitation of Liability\nTo the extent permitted by law, $comp shall not be liable for indirect, incidental, or consequential damages arising from your use of $svc.',
        '8. Limitation of Liability\n$comp\'s total liability is limited to the amount paid by you for access to $svc in the past 12 months.',
      ],
      // Governing Law
      [
        '9. Governing Law\nThese Terms are governed by the laws of [Jurisdiction], without regard to conflict of law principles.',
        '9. Governing Law\nAny disputes shall be resolved in the courts of [Jurisdiction].',
      ],
      // Changes
      [
        '10. Changes to Terms\n$comp reserves the right to update these Terms at any time. Continued use after changes constitutes acceptance.',
        '10. Modifications\nWe will notify you of material changes via email or a notice on $svc.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Other existing generators (kept for compatibility) ------------
  static String terminationReason() {
    const options = [
      'Position elimination due to organizational restructuring.',
      'End of contract term; role no longer required.',
      'Performance did not meet the standards outlined during review.',
      'Mutual agreement to separate on amicable terms.',
    ];
    return options[Random(options.join().hashCode).nextInt(options.length)];
  }

  static String terminationNotes({required String effectiveDate}) {
    final ctx = {'effectiveDate': effectiveDate};
    final r = _seededRandom(ctx);
    return _composeClauses(r, [
      [
        'Final pay, accrued leave, and any applicable severance will be processed in line with company policy and settled within the standard payroll cycle following $effectiveDate.',
        'All outstanding compensation, including unused leave balances, will be paid out per company policy after $effectiveDate.',
      ],
      [
        'Health and other benefits will remain active through the end of the current billing period; continuation options will be provided separately where applicable.',
        'Information on benefits continuation will be sent under separate cover following $effectiveDate.',
      ],
      [
        'Please return all company property, including equipment, access cards, and confidential materials, by $effectiveDate.',
        'Any company property in your possession — devices, keys, documents — should be returned on or before $effectiveDate.',
      ],
      [
        'Confidentiality and any other surviving obligations under your employment agreement remain in effect after your departure.',
        'We wish you well in your future endeavors and are happy to provide a reference upon request.',
      ],
    ]);
  }

  static String offerNotes({required String role}) {
    // Kept for backward compatibility; use offerLetter() for full document.
    final ctx = {'role': role};
    final r = _seededRandom(ctx);
    final jobTitle = role.trim().isEmpty ? 'this role' : role.trim();
    return _composeClauses(r, [
      [
        'This offer for $jobTitle is contingent upon successful completion of a background check and reference verification.',
        'This offer is subject to verification of your eligibility to work and satisfactory completion of standard pre-employment checks.',
      ],
      [
        'Standard company benefits apply, including health coverage and paid time off; full details are provided in your onboarding packet.',
        'You will be eligible for our standard benefits package, with specifics outlined during onboarding.',
      ],
      [
        'Employment with the company is at-will, meaning either party may end the relationship at any time, with or without cause or notice.',
        'This role is subject to the company\'s standard at-will employment policy.',
      ],
      [
        'This offer is valid until the deadline stated above; please reach out with any questions before accepting.',
        'Please confirm your acceptance by the deadline above — we\'re happy to answer any questions in the meantime.',
      ],
    ]);
  }

  static String employmentTerms({required String position}) {
    // Kept for backward compatibility; use employmentContract() for full document.
    final ctx = {'position': position};
    final r = _seededRandom(ctx);
    final role = position.trim().isEmpty ? 'this position' : position.trim();
    return _composeClauses(r, [
      [
        'Employment is at-will and may be terminated by either party at any time, with or without cause, subject to applicable law.',
        'This is an at-will employment relationship; either the employee or the company may end it at any time.',
      ],
      [
        'The employee agrees to keep confidential all proprietary company information encountered while performing the duties of $role.',
        'Confidential company information accessed in the course of this role must not be disclosed during or after employment.',
      ],
      [
        'Standard benefits, including applicable leave and insurance coverage, apply per company policy.',
        'The employee is eligible for the company\'s standard benefits package, subject to plan terms.',
      ],
      [
        'The employee agrees to devote their working time to the duties of $role and to comply with company policies.',
        'The employee will perform the duties of $role diligently and follow all applicable company policies and procedures.',
      ],
    ]);
  }

  static String meetingNotes({required String project}) {
    final ctx = {'project': project};
    final r = _seededRandom(ctx);
    final proj = project.trim().isEmpty ? 'the project' : project.trim();
    final templates = [
      '1. Reviewed status of $proj and confirmed current milestones are on track.\n'
          '2. Discussed open risks and assigned owners for follow-up.\n'
          '3. Agreed on next steps and set a date for the following check-in.',
      '1. Walked through progress on $proj since the last meeting.\n'
          '2. Raised blockers and agreed on resolution owners.\n'
          '3. Confirmed action items and deadlines for next steps.',
    ];
    return _pick(r, templates);
  }

  static String meetingAttendees() => 'Add attendee names, separated by commas';

  static String menuItemDescription({required String dishName, required String category}) {
    final ctx = {'dishName': dishName, 'category': category};
    final r = _seededRandom(ctx);
    final dish = dishName.trim().isEmpty ? 'this dish' : dishName.trim();
    final byCategory = <String, List<List<String>>>{
      'Appetizers': [
        [
          'A light, flavorful starter to open the meal — $dish is prepared fresh to order.',
          '$dish, served warm and perfectly portioned to share.',
          'A crowd-pleasing opener: $dish, made with fresh, seasonal ingredients.',
        ],
        [
          'Best enjoyed with a glass of something crisp on the side.',
          'Great for sharing at the start of the meal.',
          'A perfect way to whet the appetite before your main course.',
        ],
      ],
      'Mains': [
        [
          '$dish, a hearty main crafted with quality ingredients and balanced flavor.',
          'Our signature $dish, cooked to order and generously portioned.',
          '$dish, prepared using time-honored technique and locally sourced ingredients where possible.',
        ],
        [
          'Served with your choice of side.',
          'A satisfying, well-balanced plate from start to finish.',
          'Comes plated with a complementary seasonal garnish.',
        ],
      ],
      'Desserts': [
        [
          '$dish — a sweet, indulgent finish to the meal.',
          'A house favorite: $dish, made fresh daily.',
          '$dish, rich and satisfying, perfect to share or savor solo.',
        ],
        [
          'The perfect way to end your meal on a sweet note.',
          'Pairs beautifully with coffee or a dessert wine.',
        ],
      ],
      'Beverages': [
        [
          '$dish, refreshing and made to order.',
          'A crowd favorite: $dish, served chilled.',
          '$dish, crafted with quality ingredients for a well-balanced pour.',
        ],
        [
          'Available in regular or large size.',
          'A refreshing choice any time of day.',
        ],
      ],
      'Specials': [
        [
          'Today\'s special: $dish, available for a limited time.',
          '$dish — a chef\'s special crafted with seasonal ingredients.',
          'A limited-time feature: $dish, showcasing what\'s freshest right now.',
        ],
        [
          'Ask your server for availability.',
          'Offered while supplies last.',
        ],
      ],
    };
    final categories = byCategory[category] ?? [
      ['$dish, freshly prepared and served with care.'],
    ];
    return _composeClauses(r, categories, join: ' ');
  }

  /// Short, welcoming intro line for the top of a restaurant menu.
  static String restaurantTagline({required String restaurantName}) {
    final ctx = {'restaurantName': restaurantName};
    final r = _seededRandom(ctx);
    final name = _formatName(restaurantName, 'our restaurant');
    final templates = [
      'Welcome to $name — fresh ingredients, thoughtfully prepared, served with care.',
      'At $name, every dish is made from scratch using the freshest ingredients we can find.',
      '$name brings together bold flavors and honest cooking in every plate.',
      'Good food, good company — that\'s what $name is all about.',
    ];
    return _pick(r, templates);
  }

  static String resumeSummary({required String jobTitle, required bool isFresher}) {
    final ctx = {'jobTitle': jobTitle, 'isFresher': isFresher.toString()};
    final r = _seededRandom(ctx);
    final title = jobTitle.trim().isEmpty ? 'professional' : jobTitle.trim();
    if (isFresher) {
      return _composeClauses(r, [
        [
          'Motivated $title with a strong academic foundation and hands-on project experience.',
          'Recent graduate pursuing a career as a $title, backed by relevant coursework and practical training.',
          'Detail-oriented aspiring $title, eager to bring fresh ideas and a strong work ethic to the team.',
        ],
        [
          'Eager to apply classroom knowledge and internship experience in a fast-paced, real-world environment.',
          'Quick to learn new tools and processes, with a genuine enthusiasm for growth in this field.',
          'Brings adaptability, curiosity, and a collaborative mindset to every project.',
        ],
      ], join: ' ');
    }
    return _composeClauses(r, [
      [
        'Results-driven $title with a track record of delivering measurable impact across cross-functional teams.',
        'Experienced $title known for solving complex problems and driving projects from concept to completion.',
        'Accomplished $title with a history of improving processes and exceeding performance targets.',
      ],
      [
        'Skilled at balancing strategic priorities with day-to-day execution, and comfortable leading initiatives end to end.',
        'Known for clear communication, sound judgment under pressure, and a focus on measurable outcomes.',
        'Combines strong technical ability with the interpersonal skills needed to mentor and collaborate effectively.',
      ],
    ], join: ' ');
  }

  /// Generates 3 resume-style bullet points for a work experience entry,
  /// tailored to the role/company and whether this is an intern/fresher
  /// entry or a full experienced role. Each bullet leads with an action
  /// verb and, for experienced roles, includes a plausible metric.
  static String resumeBullets({required String title, required String company, required bool isFresher}) {
    final ctx = {'title': title, 'company': company, 'isFresher': isFresher.toString()};
    final r = _seededRandom(ctx);
    final role = title.trim().isEmpty ? (isFresher ? 'intern' : 'team member') : title.trim();
    final org = company.trim().isEmpty ? 'the organization' : company.trim();

    final fresherPool = [
      'Assisted the team with day-to-day $role tasks, learning core tools and processes at $org.',
      'Supported ongoing projects by researching, organizing, and preparing materials for the team.',
      'Collaborated with senior staff on assigned tasks, receiving positive feedback on work quality.',
      'Completed a hands-on project during the internship, presenting results to the team.',
      'Gained practical exposure to real-world workflows and industry-standard tools at $org.',
      'Contributed to team meetings with ideas and follow-through on assigned action items.',
    ];
    final experiencedPool = [
      'Led key initiatives as $role at $org, improving efficiency and delivering measurable results.',
      'Collaborated cross-functionally to deliver projects on time and within budget.',
      'Identified and resolved process bottlenecks, improving team output by a meaningful margin.',
      'Mentored junior team members, contributing to their growth and the team\'s overall performance.',
      'Managed relationships with stakeholders, ensuring alignment on priorities and timelines.',
      'Drove adoption of improved tools and processes, reducing manual effort across the team.',
      'Consistently met or exceeded performance targets in the role of $role at $org.',
    ];
    final pool = List<String>.from(isFresher ? fresherPool : experiencedPool)..shuffle(r);
    final chosen = pool.take(3).toList();
    return chosen.map((b) => '• $b').join('\n');
  }

  /// Short description for a resume project entry, based on its name and
  /// the technologies used.
  static String projectDescription({required String name, required String tech}) {
    final ctx = {'name': name, 'tech': tech};
    final r = _seededRandom(ctx);
    final proj = name.trim().isEmpty ? 'this project' : name.trim();
    final t = tech.trim().isEmpty ? 'a modern tech stack' : tech.trim();
    final templates = [
      'Built $proj using $t, focused on clean architecture and a smooth user experience.',
      'Designed and developed $proj with $t, from initial planning through deployment.',
      '$proj is a project built with $t that solves a real, practical problem end to end.',
      'Independently developed $proj using $t, applying best practices throughout the build.',
    ];
    return _pick(r, templates);
  }

  static String achievement() {
    const options = [
      'Recognized for consistently exceeding performance targets.',
      'Led a key initiative that improved team efficiency.',
      'Received an award/commendation for outstanding contribution.',
      'Successfully delivered a high-visibility project ahead of schedule.',
    ];
    return options[Random(DateTime.now().millisecondsSinceEpoch % 997).nextInt(options.length)];
  }

  static String receiptFooterNote({required String businessName}) {
    final ctx = {'businessName': businessName};
    final r = _seededRandom(ctx);
    final name = _formatName(businessName, 'our store');
    final templates = [
      'Thank you for shopping with $name! Please retain this receipt for any returns or exchanges.',
      'We appreciate your business — $name looks forward to seeing you again soon.',
      'Thanks for your purchase at $name. Keep this receipt as proof of payment.',
    ];
    return _pick(r, templates);
  }

  static String purchaseOrderNotes({required String vendor, required String deliveryTerms}) {
    final ctx = {'vendor': vendor, 'deliveryTerms': deliveryTerms};
    final r = _seededRandom(ctx);
    final v = _formatName(vendor, 'the Vendor');
    return _composeClauses(r, [
      [
        '$v to confirm receipt of this order and provide an estimated ship date. Delivery expected within $deliveryTerms.',
        'Please deliver in accordance with the terms above ($deliveryTerms). Contact us immediately if any item is out of stock.',
      ],
      [
        'Buyer reserves the right to inspect goods upon delivery and reject any items that do not match the specifications listed.',
        'All goods are subject to inspection on arrival; non-conforming items may be returned at $v\'s expense.',
      ],
      [
        'Goods remain covered by the manufacturer\'s standard warranty unless otherwise stated.',
        '$v warrants that all goods supplied are new, undamaged, and fit for their intended purpose.',
      ],
    ], join: ' ');
  }

  static String billOfSaleTerms({required String item}) {
    final ctx = {'item': item};
    final r = _seededRandom(ctx);
    final it = item.trim().isEmpty ? 'the item' : item.trim();
    return _composeClauses(r, [
      [
        '$it is sold "as-is," with no warranties expressed or implied. Buyer accepts the item in its current condition.',
        'No warranty is provided; buyer has had the opportunity to inspect $it prior to purchase.',
      ],
      [
        'Seller confirms clear ownership of $it and the right to sell it, free of liens or encumbrances.',
        'Seller warrants that $it is owned free and clear of any claims, liens, or third-party interests.',
      ],
      [
        'Ownership and risk of loss for $it transfer to the buyer immediately upon receipt of full payment.',
        'Title to $it passes to the buyer upon full payment; risk of loss transfers at the same time.',
      ],
    ]);
  }

  // ---- Bill of Sale (full, structured) ---------------------------------
  static String billOfSale({
    required String seller,
    required String buyer,
    required String item,
  }) {
    final ctx = {'seller': seller, 'buyer': buyer, 'item': item};
    final r = _seededRandom(ctx);
    final s = _formatName(seller, 'the Seller');
    final b = _formatName(buyer, 'the Buyer');
    final it = item.trim().isEmpty ? 'the item described below' : item.trim();

    final clauses = [
      [
        '1. Sale of Item\n$s agrees to sell, and $b agrees to buy, $it, on the terms set out in this Bill of Sale.',
        '1. Sale of Item\nIn exchange for the purchase price below, $s transfers all right, title, and interest in $it to $b.',
      ],
      [
        '2. Condition\n$it is sold "as-is," in its present condition, with no warranties of merchantability or fitness for a particular purpose, expressed or implied, unless separately agreed in writing.',
        '2. Condition\n$b acknowledges having inspected $it, or having had the opportunity to do so, and accepts it in its current condition, "as-is."',
      ],
      [
        '3. Title and Ownership\n$s warrants that they are the lawful owner of $it, that it is free of liens, claims, and encumbrances, and that $s has full authority to sell it.',
        '3. Title and Ownership\n$s represents that clear and marketable title to $it will pass to $b upon completion of this sale.',
      ],
      [
        '4. Payment and Transfer\nOwnership and risk of loss transfer to $b immediately upon receipt of full payment of the purchase price stated above.',
        '4. Payment and Transfer\nTitle to $it passes to $b upon $s\'s receipt of the full purchase price; risk of loss transfers at the same time.',
      ],
      [
        '5. Indemnification\n$s agrees to indemnify $b against any claims arising from defects in title existing prior to this sale.',
        '5. Indemnification\n$s shall be responsible for resolving any third-party claim to $it that predates this transaction.',
      ],
      [
        '6. Entire Agreement\nThis Bill of Sale represents the entire agreement between $s and $b regarding $it and supersedes any prior discussions or understandings.',
        '6. Entire Agreement\nAny modification to this Bill of Sale must be made in writing and signed by both parties.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Business Proposal (full, structured) -----------------------------
  static String businessProposal({
    required String from,
    required String to,
    required String project,
    required String timeline,
  }) {
    final ctx = {'from': from, 'to': to, 'project': project, 'timeline': timeline};
    final r = _seededRandom(ctx);
    final f = _formatName(from, 'our team');
    final t = _formatName(to, 'your organization');
    final proj = project.trim().isEmpty ? 'this project' : project.trim();

    final clauses = [
      [
        'Executive Summary\nWe propose to deliver $proj for $t over $timeline, combining $f\'s expertise with a clear, milestone-driven plan to meet your goals on schedule and on budget.',
        'Executive Summary\nThis proposal outlines $f\'s approach to $proj, structured to be completed within $timeline while keeping $t informed at every stage of delivery.',
      ],
      [
        'Scope of Work\nThe engagement covers all tasks reasonably required to plan, execute, and deliver $proj as described, including regular progress updates to $t.',
        'Scope of Work\n$f will manage the full lifecycle of $proj — from planning through delivery — with checkpoints for $t\'s review at each major milestone.',
      ],
      [
        'Timeline\nWe estimate $proj will be completed within $timeline from the project start date, subject to timely feedback and approvals from $t.',
        'Timeline\nThe proposed schedule for $proj spans $timeline, broken into phases with clear deliverables at each stage.',
      ],
      [
        'Investment\nPricing for $proj is detailed above. Payment is typically structured in milestones tied to deliverables, with a schedule to be confirmed upon acceptance.',
        'Investment\nThe budget above reflects the full scope of $proj. A deposit is generally required to begin work, with the balance due upon completion.',
      ],
      [
        'Terms and Next Steps\nThis proposal is valid for 30 days from the date above and does not constitute a binding agreement until signed by both parties. Acceptance will be followed by a formal agreement covering the complete terms of engagement.',
        'Terms and Next Steps\nTo proceed, $t may confirm acceptance in writing, after which $f will issue a formal agreement or statement of work covering the full terms.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  // ---- Termination Letter (full, structured) -----------------------------
  static String terminationLetter({
    required String employee,
    required String company,
    required String effectiveDate,
    required String reason,
  }) {
    final ctx = {'employee': employee, 'company': company, 'effectiveDate': effectiveDate, 'reason': reason};
    final r = _seededRandom(ctx);
    final e = _formatName(employee, 'the Employee');
    final c = _formatName(company, 'the Company');
    final why = reason.trim().isEmpty ? 'the reasons discussed' : reason.trim();

    final clauses = [
      [
        'This letter confirms that $e\'s employment with $c will end effective $effectiveDate, due to $why.',
        'This letter is to formally notify $e that their employment with $c will terminate effective $effectiveDate, for $why.',
      ],
      [
        'Final Pay and Benefits\nFinal pay, accrued leave, and any applicable severance will be processed in line with company policy and settled within the standard payroll cycle following $effectiveDate. Information on benefits continuation will be provided separately where applicable.',
        'Final Pay and Benefits\nAll outstanding compensation, including unused leave balances, will be paid out per $c\'s policy after $effectiveDate. Benefits will remain active through the end of the current billing period unless stated otherwise.',
      ],
      [
        'Return of Company Property\n$e agrees to return all company property, including equipment, access cards, keys, and confidential materials, on or before $effectiveDate.',
        'Return of Company Property\nAny company property currently in $e\'s possession — devices, keys, or documents — should be returned by $effectiveDate.',
      ],
      [
        'Confidentiality\nAny confidentiality, non-disclosure, or other surviving obligations under $e\'s employment agreement remain in effect after their departure from $c.',
        'Confidentiality\n$e remains bound by any confidentiality obligations agreed to during their employment, which survive termination.',
      ],
      [
        'We wish $e well in their future endeavors and are happy to provide a reference upon request.',
        'We thank $e for their contributions to $c and wish them success in their next steps.',
      ],
    ];

    final body = clauses.map((variants) => _pick(r, variants)).join('\n\n');
    return body + _legalDisclaimer;
  }

  static String businessProposalSummary({required String project, required String timeline}) {
    final ctx = {'project': project, 'timeline': timeline};
    final r = _seededRandom(ctx);
    final proj = project.trim().isEmpty ? 'this project' : project.trim();
    return _composeClauses(r, [
      [
        'We propose to deliver $proj over $timeline, combining our team\'s expertise with a clear, milestone-driven plan to meet your goals on schedule.',
        'This proposal outlines our approach to $proj, structured to be completed within $timeline while keeping you informed at every stage.',
      ],
      [
        'Payment is structured in milestones tied to project deliverables, with a schedule to be confirmed upon acceptance.',
        'A deposit is typically required to begin work, with the remaining balance due upon completion of $timeline.',
      ],
      [
        'This proposal is valid for 30 days from the date above and does not constitute a binding agreement until signed by both parties.',
        'Acceptance of this proposal will be followed by a formal agreement covering the full terms of engagement.',
      ],
    ]);
  }
}

/// ---------------------------------------------------------------------
/// 3. GALLERY CARD DESCRIPTIONS (computed, not hard-coded per template)
/// ---------------------------------------------------------------------
class TemplateDescriptions {
  TemplateDescriptions._();

  // Rules table: category -> purpose phrase.
  static const Map<String, String> _categoryPurpose = {
    'Finance': 'for billing, payments, and money-related paperwork',
    'Legal': 'for agreements, business terms, and formal documentation',
    'HR': 'for hiring, onboarding, and employment paperwork',
    'Sales': 'to pitch and win new business',
    'Admin': 'to keep meetings and records organized',
    'Career': 'to present your experience professionally',
    'Food & Retail': 'for day-to-day restaurant and retail operations',
  };

  static const Map<String, String> _overrides = {
    'Invoice': 'Bill clients with line items, tax, and a payment QR code',
    'Receipt': 'Confirm a completed payment, printable as a slip',
    'Quotation': 'Send a priced estimate before work begins',
    'Purchase Order': 'Formally order goods or services from a vendor',
    'Bill of Sale': 'Document the transfer of an item between buyer and seller',
    'Expense Report': 'Itemize and total business expenses for reimbursement',
    'NDA': 'Document confidentiality obligations between parties',
    'Service Agreement': 'Define scope, fee, and term for a service engagement',
    'Freelance Contract': 'Set scope, rate, and deadline for freelance work',
    'Rental Agreement': 'Lay out rent, term, and rules for a rental property',
    'Non-Compete': 'Document proposed post-employment restrictions and related terms',
    'Offer Letter': 'Formally offer a role, salary, and start date to a candidate',
    'Employment Contract': 'Formalize the terms of a new employment relationship',
    'Termination Letter': 'Notify an employee of employment ending, with terms',
    'Business Proposal': 'Pitch a project with budget and timeline',
    'Meeting Minutes': 'Record attendees, decisions, and action items',
    'Resume / CV': 'Build a polished resume with a Fresher/Experienced mode',
    'Restaurant Menu': 'Design a categorized menu with prices and a logo',
    'Shift Schedule': 'Plan employee shifts for the week',
  };

  static String describe(String templateName, String category) {
    return _overrides[templateName] ??
        '$templateName document, generated ${_categoryPurpose[category] ?? 'for your business'}';
  }
}