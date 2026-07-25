import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:loantrack/features/business/data/models/business_profile_entity.dart';
import 'package:loantrack/features/customers/data/models/customer_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';
import 'package:loantrack/core/constants/app_constants.dart';

class DocumentService {
  DocumentService._();

  static Future<void> previewPdf(pw.Document document) async {
    await Printing.layoutPdf(onLayout: (format) async => document.save());
  }

  static Future<File> savePdf(String fileName, pw.Document document) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName.pdf');
    await file.writeAsBytes(await document.save());
    return file;
  }

  static pw.Widget _buildHeader(String title, Uint8List? logoBytes) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        if (logoBytes != null)
          pw.Image(pw.MemoryImage(logoBytes), width: 100, height: 60)
        else
          pw.Text(AppConstants.appName,
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _sectionTitle(String title) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 16, fontWeight: pw.FontWeight.bold)));

  static Future<void> generateLoanAgreement({
    required BusinessProfile business,
    required Customer customer,
    required Loan loan,
    Uint8List? logoBytes,
    Uint8List? borrowerSignature,
    Uint8List? guarantorSignature,
  }) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (context) => [
        _buildHeader('LOAN AGREEMENT', logoBytes),
        pw.SizedBox(height: 12),
        pw.Text('Business: ${business.name}'),
        pw.Text('Customer: ${customer.fullName}'),
        pw.Text('Loan ID: ${loan.id}'),
        pw.Text('Amount: ${loan.amount}'),
        pw.Text('Interest: ${loan.interestRate}%'),
        pw.Text(
            'Duration: ${loan.duration} ${loan.loanType.name == 'daily' ? 'days' : 'months'}'),
        _sectionTitle('Terms and Conditions'),
        pw.Text(
            'This loan agreement outlines the terms and conditions for the loan above. The borrower agrees to repay the loan according to the repayment schedule produced by the app.'),
        pw.SizedBox(height: 24),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(children: [
              if (borrowerSignature != null)
                pw.Image(pw.MemoryImage(borrowerSignature),
                    width: 120, height: 60),
              pw.Text('Borrower Signature'),
            ]),
            pw.Column(children: [
              if (guarantorSignature != null)
                pw.Image(pw.MemoryImage(guarantorSignature),
                    width: 120, height: 60),
              pw.Text('Guarantor Signature'),
            ]),
            pw.Column(children: [
              pw.Container(
                  width: 120,
                  height: 60,
                  decoration: pw.BoxDecoration(
                      border:
                          pw.Border(bottom: pw.BorderSide(width: 1)))),
              pw.Text('Lender Signature'),
            ]),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: loan.id,
          width: 100,
          height: 100,
        ),
      ],
    ));

    await previewPdf(doc);
  }

  static Future<void> generateReceipt({
    required BusinessProfile business,
    required Customer customer,
    required Loan loan,
    required Payment payment,
    Uint8List? logoBytes,
  }) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (context) => [
        _buildHeader('PAYMENT RECEIPT', logoBytes),
        pw.SizedBox(height: 12),
        pw.Text('Receipt #: ${payment.receiptNumber}'),
        pw.Text('Date: ${payment.paymentDate.toIso8601String()}'),
        _sectionTitle('Payment details'),
        pw.Text('Customer: ${customer.fullName}'),
        pw.Text('Loan ID: ${loan.id}'),
        pw.Text('Amount Paid: ${payment.amount}'),
        pw.Text('Outstanding Balance: ${loan.outstandingBalance}'),
        pw.Text('Payment method: ${payment.method.name.toUpperCase()}'),
        pw.Text('Collector: ${payment.collector}'),
        pw.SizedBox(height: 16),
        pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: payment.receiptNumber,
            width: 200,
            height: 80),
      ],
    ));
    await previewPdf(doc);
  }
}
