import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/database/database_service.dart';
import '../../../core/utils/currency_utils.dart';
import '../../../core/utils/date_utils.dart';

/// Generates printable customer statements (loan, savings, and collection history).
class StatementService {
  StatementService(this._dbService);
  final DatabaseService _dbService;

  /// Generates and opens a print dialog for the customer's statement.
  Future<void> printCustomerStatement(String customerId) async {
    final doc = await _buildStatement(customerId);
    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'Customer_Statement_$customerId',
    );
  }

  /// Returns the PDF bytes for a customer statement (for sharing/export).
  Future<Uint8List> buildCustomerStatementPdf(String customerId) async {
    final doc = await _buildStatement(customerId);
    return doc.save();
  }

  /// Generates the PDF document for a customer statement.
  Future<pw.Document> _buildStatement(String customerId) async {
    final db = await _dbService.database;

    // Fetch customer
    final customerRows = await db.query('customers', where: 'id = ?', whereArgs: [customerId]);
    final customer = customerRows.isNotEmpty ? customerRows.first : null;
    final customerName = customer?['full_name'] as String? ?? 'Unknown';
    final customerPhone = customer?['phone'] as String? ?? '';

    // Fetch loans
    final loanRows = await db.query('loans', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'loan_date DESC');

    // Fetch payments
    final paymentRows = await db.query('payments', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'payment_date DESC');

    // Fetch savings balance
    final savingsRows = await db.query('savings_accounts', columns: ['balance'], where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
    final savingsBalance = savingsRows.isNotEmpty ? (savingsRows.first['balance'] as num?)?.toDouble() ?? 0.0 : 0.0;

    // Fetch savings transactions
    final savingsAccountRows = await db.query('savings_accounts', columns: ['id'], where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
    List<Map<String, dynamic>> savingsTransactions = [];
    if (savingsAccountRows.isNotEmpty) {
      final accountId = savingsAccountRows.first['id'] as String;
      savingsTransactions = await db.query('savings_transactions', where: 'savings_account_id = ?', whereArgs: [accountId], orderBy: 'created_at DESC');
    }

    final now = DateTime.now();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          pw.Header(
            level: 0,
            child: pw.Text('Customer Statement', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Generated: ${AppDateUtils.formatDateTime(now)}'),
          pw.SizedBox(height: 16),

          // Customer info
          _section('Customer Information', [
            _row('Name', customerName),
            _row('Phone', customerPhone),
            _row('ID', customerId),
          ]),
          pw.SizedBox(height: 16),

          // Loans summary
          _section('Loans (${loanRows.length})', [
            if (loanRows.isEmpty)
              pw.Text('No loans found.', style: const pw.TextStyle(color: PdfColors.grey)),
            for (final loan in loanRows) ...[
              _row(
                'Loan ${loan['id']}',
                '${CurrencyUtils.format((loan['amount'] as num).toDouble())} — ${loan['status']}',
              ),
              _row('  Outstanding', CurrencyUtils.format((loan['outstanding_balance'] as num).toDouble())),
              _row('  Date', loan['loan_date'] as String? ?? ''),
              pw.Divider(height: 4),
            ],
          ]),
          pw.SizedBox(height: 16),

          // Payments summary
          _section('Payments (${paymentRows.length})', [
            if (paymentRows.isEmpty)
              pw.Text('No payments found.', style: const pw.TextStyle(color: PdfColors.grey)),
            for (final payment in paymentRows) ...[
              _row(
                'Payment ${payment['receipt_no'] ?? payment['id']}',
                CurrencyUtils.format((payment['amount'] as num).toDouble()),
              ),
              _row('  Date', payment['payment_date'] as String? ?? ''),
              _row('  Method', payment['payment_method'] as String? ?? ''),
              pw.Divider(height: 4),
            ],
          ]),
          pw.SizedBox(height: 16),

          // Savings summary
          _section('Savings', [
            _row('Current Balance', CurrencyUtils.format(savingsBalance)),
            if (savingsTransactions.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Text('Recent Transactions:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              for (final tx in savingsTransactions.take(20)) ...[
                _row(
                  '${tx['type']} — ${tx['created_at']?.toString().split('T').first ?? ''}',
                  CurrencyUtils.format((tx['amount'] as num).toDouble()),
                ),
                if (tx['note'] != null) pw.Text('  ${tx['note']}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
              ],
            ],
          ]),
        ],
      ),
    );

    return pdf;
  }

  pw.Widget _section(String title, List<pw.Widget> children) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: pw.BoxDecoration(color: PdfColors.grey300),
          child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
        ),
        pw.SizedBox(height: 8),
        ...children,
      ],
    );
  }

  pw.Widget _row(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 10))),
          pw.SizedBox(width: 16),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
