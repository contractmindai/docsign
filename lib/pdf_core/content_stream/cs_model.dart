class PdfContentOperatorModel {
  final String operatorName;
  final List<dynamic> operands;
  PdfContentOperatorModel(this.operatorName, this.operands);
  @override
  String toString() => 'Op: $operatorName Args: ${operands.join(", ")}';
}