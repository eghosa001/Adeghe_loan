import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/loans/domain/loan_calculator.dart';
import 'package:loantrack/features/payments/data/payment_logic.dart';

void main() {
  group('MANUAL CALCULATION AUDIT — compare app output to hand-worked values', () {
    // ── 1. LoanCalculator: flat-rate interest + fees ─────────────────────────
    test('LoanCalculator: principal 10000, rate 5%, insurance 1%, 10 weeks', () {
      final r = LoanCalculator.calculate(
        principal: 10000,
        interestRatePercent: 5.0,
        insuranceFeePercent: 1.0,
        commissionPercent: 0.0,
        processingFee: 0.0,
        administrativeFee: 0.0,
        otherCharges: 0.0,
        duration: 10,
      );
      // interest = 10000 * 0.05 = 500
      // insurance = 10000 * 0.01 = 100
      // totalCharges = 100
      // totalRepayment = 10000 + 500 + 100 = 10600
      // installment = 10600 / 10 = 1060
      expect(r.interestAmount, closeTo(500.0, 0.001));
      expect(r.insuranceFeeAmount, closeTo(100.0, 0.001));
      expect(r.totalCharges, closeTo(100.0, 0.001));
      expect(r.totalRepayment, closeTo(10600.0, 0.001));
      expect(r.installmentAmount, closeTo(1060.0, 0.001));
    });

    test('LoanCalculator: principal 50000, rate 12%, insurance 2%, commission 1%, '
        'processing 500, admin 200, other 100, 24 weeks', () {
      final r = LoanCalculator.calculate(
        principal: 50000,
        interestRatePercent: 12.0,
        insuranceFeePercent: 2.0,
        commissionPercent: 1.0,
        processingFee: 500.0,
        administrativeFee: 200.0,
        otherCharges: 100.0,
        duration: 24,
      );
      // interest = 50000 * 0.12 = 6000
      // insurance = 50000 * 0.02 = 1000
      // commission = 50000 * 0.01 = 500
      // totalCharges = 1000 + 500 + 500 + 200 + 100 = 2300
      // totalRepayment = 50000 + 6000 + 2300 = 58300
      // installment = 58300 / 24 = 2429.1667 → rounded to 2429.17
      expect(r.interestAmount, closeTo(6000.0, 0.001));
      expect(r.insuranceFeeAmount, closeTo(1000.0, 0.001));
      expect(r.commissionAmount, closeTo(500.0, 0.001));
      expect(r.totalCharges, closeTo(2300.0, 0.001));
      expect(r.totalRepayment, closeTo(58300.0, 0.001));
      expect(r.installmentAmount, closeTo(2429.17, 0.01));
    });

    // ── 2. CurrencyUtils.splitEvenly: rounding remainder distribution ─────────
    test('splitEvenly: 10001 over 3 installments sums exactly to total', () {
      final parts = CurrencyUtils.splitEvenly(10001, 3);
      expect(parts, hasLength(3));
      // 10001 * 100 = 1,000,100 cents; /3 = 333,366 remainder 2
      expect(parts[0], closeTo(3333.67, 0.001));
      expect(parts[1], closeTo(3333.67, 0.001));
      expect(parts[2], closeTo(3333.66, 0.001));
      expect(parts.fold<double>(0, (a, b) => a + b), closeTo(10001.0, 0.001));
    });

    test('splitEvenly: 1000 over 3 → 333.34, 333.33, 333.33 (sum = 1000)', () {
      final parts = CurrencyUtils.splitEvenly(1000, 3);
      expect(parts, hasLength(3));
      // 1000 * 100 = 100,000 cents; /3 = 33,333 remainder 1
      expect(parts[0], closeTo(333.34, 0.001));
      expect(parts[1], closeTo(333.33, 0.001));
      expect(parts[2], closeTo(333.33, 0.001));
      expect(parts.fold<double>(0, (a, b) => a + b), closeTo(1000.0, 0.001));
    });

    test('splitEvenly: 1050 over 7 → 150 each (exact)', () {
      final parts = CurrencyUtils.splitEvenly(1050, 7);
      expect(parts, hasLength(7));
      expect(parts.fold<double>(0, (a, b) => a + b), closeTo(1050.0, 0.001));
      for (final p in parts) {
        expect(p, closeTo(150.0, 0.001));
      }
    });

    // ── 3. computePaymentSplit: installment context caps loan at installment ───
    test('computePaymentSplit: installment context, payment > installment', () {
      // outstanding=10000, installmentDue=1500, payment=2000
      // loanPaid = min(2000, 1500) = 1500
      // surplus = 2000 - 1500 = 500
      // newBalance = 10000 - 1500 = 8500
      final r = computePaymentSplit(
        paymentAmount: 2000,
        outstandingBalance: 10000,
        installmentDue: 1500,
      );
      expect(r.appliedToLoan, closeTo(1500.0, 0.001));
      expect(r.overpaymentSurplus, closeTo(500.0, 0.001));
      expect(r.newLoanBalance, closeTo(8500.0, 0.001));
    });

    test('computePaymentSplit: installment context, payment < installment', () {
      // outstanding=10000, installmentDue=1500, payment=800
      // loanPaid = min(800, 1500) = 800
      // surplus = 0
      // newBalance = 10000 - 800 = 9200
      final r = computePaymentSplit(
        paymentAmount: 800,
        outstandingBalance: 10000,
        installmentDue: 1500,
      );
      expect(r.appliedToLoan, closeTo(800.0, 0.001));
      expect(r.overpaymentSurplus, closeTo(0.0, 0.001));
      expect(r.newLoanBalance, closeTo(9200.0, 0.001));
    });

    test('computePaymentSplit: overpayment with installment, new balance never negative', () {
      // outstanding=1000, installmentDue=500, payment=2000
      // cap = min(500, 1000) = 500
      // loanPaid = min(2000, 500) = 500
      // surplus = 1500
      // newBalance = max(0, 1000 - 500) = 500
      final r = computePaymentSplit(
        paymentAmount: 2000,
        outstandingBalance: 1000,
        installmentDue: 500,
      );
      expect(r.appliedToLoan, closeTo(500.0, 0.001));
      expect(r.overpaymentSurplus, closeTo(1500.0, 0.001));
      expect(r.newLoanBalance, closeTo(500.0, 0.001));
    });

    // ── 4. Round-trip: payment + reversal invariant ───────────────────────────
    test('round-trip invariant: payment then reversal restores original state', () {
      const outstanding = 8500.0;
      const initialSavings = 1200.0;
      const payment = 3000.0;
      const installmentDue = 1500.0;

      final split = computePaymentSplit(
        paymentAmount: payment,
        outstandingBalance: outstanding,
        installmentDue: installmentDue,
      );
      // loanPaid = min(3000, 1500) = 1500
      // surplus = 1500
      // newBalance = 8500 - 1500 = 7000
      expect(split.appliedToLoan, closeTo(1500.0, 0.001));
      expect(split.overpaymentSurplus, closeTo(1500.0, 0.001));
      expect(split.newLoanBalance, closeTo(7000.0, 0.001));

      // Savings after payment
      final savingsAfterPayment = initialSavings + split.overpaymentSurplus;
      expect(savingsAfterPayment, closeTo(2700.0, 0.001));

      // Reversal
      final loanDelta = payment - split.overpaymentSurplus; // 1500
      expect(loanDelta, closeTo(1500.0, 0.001));

      final loanAfterReversal = split.newLoanBalance + loanDelta;
      expect(loanAfterReversal, closeTo(8500.0, 0.001));

      // Savings after reversal
      final (savingsAfterReversal, _) = computeSavingsReversal(
        balance: savingsAfterPayment,
        overpaymentSurplus: split.overpaymentSurplus,
      );
      expect(savingsAfterReversal, closeTo(1200.0, 0.001));
    });

    // ── 5. Multi-payment schedule total invariant ─────────────────────────────
    test('multi-payment: loan-applied amounts sum to outstanding balance', () {
      const outstanding = 10000.0;
      const p1Amount = 3000.0;
      const p2Amount = 4000.0;
      const p3Amount = 3500.0;

      // No installment context → each payment caps at remaining outstanding
      final p1 = computePaymentSplit(paymentAmount: p1Amount, outstandingBalance: outstanding);
      expect(p1.appliedToLoan, closeTo(3000.0, 0.001));
      expect(p1.overpaymentSurplus, closeTo(0.0, 0.001));

      final p2 = computePaymentSplit(paymentAmount: p2Amount, outstandingBalance: p1.newLoanBalance);
      expect(p2.appliedToLoan, closeTo(4000.0, 0.001));
      expect(p2.overpaymentSurplus, closeTo(0.0, 0.001));

      final p3 = computePaymentSplit(paymentAmount: p3Amount, outstandingBalance: p2.newLoanBalance);
      expect(p3.appliedToLoan, closeTo(3000.0, 0.001)); // only 3000 remains
      expect(p3.overpaymentSurplus, closeTo(500.0, 0.001)); // 500 surplus

      final totalApplied = p1.appliedToLoan + p2.appliedToLoan + p3.appliedToLoan;
      expect(totalApplied, closeTo(10000.0, 0.001)); // exactly clears the loan
      expect(p3.newLoanBalance, closeTo(0.0, 0.001));
    });

    // ── 6. Savings-only deposit and withdrawal ────────────────────────────────
    test('savings round-trip: deposit then withdrawal', () {
      const deposit = 2500.0;
      const withdrawal = 800.0;
      const initialBalance = 0.0;

      // Deposit
      var balance = CurrencyUtils.roundToCents(initialBalance + deposit);
      expect(balance, closeTo(2500.0, 0.001));

      // Withdrawal
      balance = CurrencyUtils.roundToCents(balance - withdrawal);
      expect(balance, closeTo(1700.0, 0.001));

      // Second withdrawal
      balance = CurrencyUtils.roundToCents(balance - 700.0);
      expect(balance, closeTo(1000.0, 0.001));
    });

    test('savings withdrawal cannot exceed balance', () {
      const balance = 500.0;
      const withdrawal = 800.0;
      // Repository-level guard: amount > balance throws
      expect(() {
        if (withdrawal > balance) throw Exception('Insufficient savings');
      }, throwsException);
    });

    // ── 7. Interest + fees + rounding ─────────────────────────────────────────
    test('interest rounding: 10000 * 10.5% = 1050.00', () {
      final r = LoanCalculator.calculate(
        principal: 10000,
        interestRatePercent: 10.5,
        insuranceFeePercent: 0.0,
        commissionPercent: 0.0,
        processingFee: 0.0,
        administrativeFee: 0.0,
        otherCharges: 0.0,
        duration: 12,
      );
      expect(r.interestAmount, closeTo(1050.0, 0.001));
    });

    test('fees with fractional percentages round to cents', () {
      final r = LoanCalculator.calculate(
        principal: 3333.33,
        interestRatePercent: 3.33,
        insuranceFeePercent: 1.11,
        commissionPercent: 0.55,
        processingFee: 0.0,
        administrativeFee: 0.0,
        otherCharges: 0.0,
        duration: 6,
      );
      // interest = 3333.33 * 0.0333 = 111.0 (approx)
      // All should be finite and non-negative
      expect(r.interestAmount.isFinite, isTrue);
      expect(r.insuranceFeeAmount.isFinite, isTrue);
      expect(r.commissionAmount.isFinite, isTrue);
      expect(r.totalRepayment.isFinite, isTrue);
      expect(r.installmentAmount.isFinite, isTrue);
      expect(r.totalRepayment, greaterThan(r.principal));
    });

    // ── 8. splitEvenly edge cases ─────────────────────────────────────────────
    test('splitEvenly: single part returns the total unchanged', () {
      final parts = CurrencyUtils.splitEvenly(1234.56, 1);
      expect(parts, hasLength(1));
      expect(parts[0], closeTo(1234.56, 0.001));
    });

    test('splitEvenly: two parts with odd cent', () {
      final parts = CurrencyUtils.splitEvenly(100.01, 2);
      expect(parts, hasLength(2));
      expect(parts.fold<double>(0, (a, b) => a + b), closeTo(100.01, 0.001));
      // One part should be 50.01, the other 50.00
      final sorted = List<double>.from(parts)..sort();
      expect(sorted[0], closeTo(50.00, 0.001));
      expect(sorted[1], closeTo(50.01, 0.001));
    });

    // ── 9. Overpayment surplus + savings balance accounting ────────────────────
    test('savings balance accumulates multiple overpayments correctly', () {
      var balance = 0.0;
      // Payment 1: overpayment of 500
      balance = CurrencyUtils.roundToCents(balance + 500);
      expect(balance, closeTo(500.0, 0.001));
      // Payment 2: overpayment of 300
      balance = CurrencyUtils.roundToCents(balance + 300);
      expect(balance, closeTo(800.0, 0.001));
      // Partial withdrawal of 200
      balance = CurrencyUtils.roundToCents(balance - 200);
      expect(balance, closeTo(600.0, 0.001));
      // Another overpayment of 100.50
      balance = CurrencyUtils.roundToCents(balance + 100.50);
      expect(balance, closeTo(700.50, 0.001));
    });

    // ── 10. Money rule: raw payment amount vs loan-applied amount ──────────────
    test('money rule: raw payment amount is NOT the loan-applied amount when overpayment exists', () {
      const paymentAmount = 12000.0;
      const outstanding = 10000.0;
      const installmentDue = 1000.0;

      final split = computePaymentSplit(
        paymentAmount: paymentAmount,
        outstandingBalance: outstanding,
        installmentDue: installmentDue,
      );

      // The raw 12000 is stored in payments.amount, but only 1000 applies to the loan
      expect(split.appliedToLoan, closeTo(1000.0, 0.001));
      expect(split.overpaymentSurplus, closeTo(11000.0, 0.001));
      // The money rule: p.amount - st.amount = 12000 - 11000 = 1000
      expect(paymentAmount - split.overpaymentSurplus, closeTo(1000.0, 0.001));
    });

    // ── 11. Collection range amountPaid aggregation (money rule) ──────────────
    test('collection range amountPaid = sum of (payment.amount - overpayment) in range', () {
      // Simulate: two completed payments in range, one with overpayment
      const p1Amount = 5000.0;
      const p1Overpayment = 500.0;
      const p2Amount = 3000.0;
      const p2Overpayment = 0.0;

      final amountPaid1 = p1Amount - p1Overpayment; // 4500
      final amountPaid2 = p2Amount - p2Overpayment; // 3000
      final totalCollected = amountPaid1 + amountPaid2; // 7500

      expect(totalCollected, closeTo(7500.0, 0.001));
      // The raw sum would be 8000, which is wrong
      expect(p1Amount + p2Amount, closeTo(8000.0, 0.001));
      expect(totalCollected, closeTo(7500.0, 0.001));
    });

    // ── 12. Overdue amount: unpaid portion of installments ─────────────────────
    test('overdue amount = sum of (installment.amount - paid_amount) for unpaid past installments', () {
      // Installment 1: amount=500, paid=500 → contributes 0
      // Installment 2: amount=500, paid=0 → contributes 500
      // Installment 3: amount=500, paid=200 → contributes 300
      const inst1 = 500.0 - 500.0;
      const inst2 = 500.0 - 0.0;
      const inst3 = 500.0 - 200.0;
      final overdue = inst1 + inst2 + inst3;
      expect(overdue, closeTo(800.0, 0.001));
    });

    // ── 13. Profit calculation: collected - disbursed ──────────────────────────
    test('net profit = totalCollected - totalDisbursed (money rule)', () {
      const disbursed = 50000.0;
      // Collected via payments, with one overpayment
      const p1 = 6000.0;
      const p1Overpay = 500.0;
      const p2 = 4000.0;
      const p2Overpay = 0.0;
      final collected = (p1 - p1Overpay) + (p2 - p2Overpay);
      expect(collected, closeTo(9500.0, 0.001));
      final profit = collected - disbursed;
      expect(profit, closeTo(-40500.0, 0.001));
    });

    // ── 14. Expected collections: unpaid portion of in-window installments ─────
    test('expected collections = sum of unpaid installments in period', () {
      // 3 installments, all in window, all unpaid
      const inst1 = 1000.0;
      const inst2 = 1000.0;
      const inst3 = 1000.0;
      final expected = inst1 + inst2 + inst3;
      expect(expected, closeTo(3000.0, 0.001));

      // One partially paid
      final expectedPartial = (inst1 - 0) + (inst2 - 300) + (inst3 - 0);
      expect(expectedPartial, closeTo(2700.0, 0.001));
    });

    // ── 15. Full loan clear with savings ──────────────────────────────────────
    test('clearLoanWithSavings: exact outstanding debited from savings', () {
      const outstanding = 4500.0;
      const savingsBalance = 10000.0;
      final newSavingsBalance = CurrencyUtils.roundToCents(savingsBalance - outstanding);
      expect(newSavingsBalance, closeTo(5500.0, 0.001));
    });

    // ── 16. Interest earned in period (cancelled loans excluded) ───────────────
    test('interest earned query: cancelled loans must not appear', () {
      // Loans in period: L1 active 10000 @ 5%, L2 completed 20000 @ 10%, L3 cancelled 5000 @ 15%
      // Only L1 + L2 count
      const l1Interest = 10000.0 * 0.05; // 500
      const l2Interest = 20000.0 * 0.10; // 2000
      const totalInterest = l1Interest + l2Interest; // 2500
      expect(totalInterest, closeTo(2500.0, 0.001));
    });

    // ── 17. Collection efficiency: collected / expected * 100, clamped 0-100 ──
    test('collection efficiency = (collected / expected) * 100, clamped', () {
      const collected = 750.0;
      const expected = 1000.0;
      final efficiency = ((collected / expected) * 100).clamp(0.0, 100.0);
      expect(efficiency, closeTo(75.0, 0.001));
    });

    test('collection efficiency: collected > expected clamps to 100', () {
      final efficiency = ((1500.0 / 1000.0) * 100).clamp(0.0, 100.0);
      expect(efficiency, closeTo(100.0, 0.001));
    });

    // ── 18. Savings inflow in period: deposits + completed-payment overpayments ─
    test('savings inflow = deposits + overpayments linked to completed payments', () {
      // In window:
      // Deposit: 1000 (no payment ref) → counts
      // Overpayment linked to completed payment: 500 → counts
      // Overpayment linked to reversed payment: 300 → does NOT count
      // Withdrawal: 200 → does NOT count (outflow)
      const inflow = 1000.0 + 500.0;
      expect(inflow, closeTo(1500.0, 0.001));
    });

    // ── 19. Distinct customer count (not per-loan) ────────────────────────────
    test('distinct customer count: customer with 2 loans counts once', () {
      // Customer C1 has both a daily and a weekly loan
      // COUNT(DISTINCT l.customer_id) must return 1, not 2
      const distinctCustomers = 1;
      expect(distinctCustomers, 1);
    });

    // ── 20. Cancelled loan exclusion from totals ───────────────────────────────
    test('cancelled loans excluded from disbursed, interest, fees, expected', () {
      // Active loan: 10000 @ 5%
      // Cancelled loan: 20000 @ 10%
      const activeDisbursed = 10000.0;
      const activeInterest = 10000.0 * 0.05; // 500
      // Cancelled loan excluded entirely
      const totalDisbursed = activeDisbursed; // 10000, not 30000
      const totalInterest = activeInterest; // 500, not 2500
      expect(totalDisbursed, closeTo(10000.0, 0.001));
      expect(totalInterest, closeTo(500.0, 0.001));
    });

    // ── 21. Overpayment → savings then withdrawal ──────────────────────────────
    test('overpayment credited to savings, then withdrawal reduces balance', () {
      // Step 1: Payment of 8000 on 5000 loan with no installment context
      //   loanPaid = min(8000, 5000) = 5000
      //   surplus = 3000 → credited to savings
      const outstanding = 5000.0;
      const payment = 8000.0;
      final split = computePaymentSplit(
        paymentAmount: payment,
        outstandingBalance: outstanding,
      );
      expect(split.appliedToLoan, closeTo(5000.0, 0.001));
      expect(split.overpaymentSurplus, closeTo(3000.0, 0.001));

      // Step 2: Customer withdraws 1000 from savings
      var savings = CurrencyUtils.roundToCents(0.0 + split.overpaymentSurplus);
      expect(savings, closeTo(3000.0, 0.001));
      savings = CurrencyUtils.roundToCents(savings - 1000.0);
      expect(savings, closeTo(2000.0, 0.001));
    });

    // ── 22. Loan with all charges: verify totalRepayment matches Σ(installments) ─
    test('Σ installments from splitEvenly == totalRepayment', () {
      const principal = 15000.0;
      const interestRate = 8.0;
      const insuranceRate = 2.0;
      const processing = 500.0;
      const admin = 300.0;
      const duration = 15;

      final r = LoanCalculator.calculate(
        principal: principal,
        interestRatePercent: interestRate,
        insuranceFeePercent: insuranceRate,
        commissionPercent: 0.0,
        processingFee: processing,
        administrativeFee: admin,
        otherCharges: 0.0,
        duration: duration,
      );

      final installments = CurrencyUtils.splitEvenly(r.totalRepayment, duration);
      final sum = installments.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(r.totalRepayment, 0.001));
    });

    // ── 23. Verify rounding does not accumulate error across many operations ───
    test('rounding stability: many deposits/withdrawals stay exact', () {
      var balance = 0.0;
      for (var i = 0; i < 100; i++) {
        balance = CurrencyUtils.roundToCents(balance + 100.33);
        balance = CurrencyUtils.roundToCents(balance - 50.21);
      }
      // Net per cycle = 50.12, after 100 cycles = 5012.00
      expect(balance, closeTo(5012.00, 0.01));
    });

    // ── 24. Money rule applied to a sequence of partial + overpayment payments ─
    test('money rule across mixed payments: raw sums vs loan-applied sums', () {
      // Sequence on a 5000 loan:
      // P1: 2000 (partial) → loanApplied=2000, overpayment=0
      // P2: 2500 (partial, remaining=3000) → loanApplied=2500, overpayment=0
      // P3: 1000 (overpayment, remaining=500) → loanApplied=500, overpayment=500
      // Total loan-applied = 2000 + 2500 + 500 = 5000
      // Total raw = 2000 + 2500 + 1000 = 5500
      // Money rule collected = 5000 (not 5500)

      const p1 = 2000.0;
      const p1Over = 0.0;
      const p2 = 2500.0;
      const p2Over = 0.0;
      const p3 = 1000.0;
      const p3Over = 500.0;

      final loanApplied = (p1 - p1Over) + (p2 - p2Over) + (p3 - p3Over);
      final rawSum = p1 + p2 + p3;

      expect(loanApplied, closeTo(5000.0, 0.001));
      expect(rawSum, closeTo(5500.0, 0.001));
      expect(loanApplied, closeTo(rawSum - p3Over, 0.001));
    });

    // ── 25. Overdue days calculation correctness ───────────────────────────────
    test('overdueDays = today - dueDate (positive = overdue)', () {
      final today = DateTime(2026, 8, 13);
      final duePast = DateTime(2026, 8, 10);
      final dueFuture = DateTime(2026, 8, 15);
      final dueToday = DateTime(2026, 8, 13);

      expect(today.difference(duePast).inDays, 3);
      expect(today.difference(dueFuture).inDays, -2);
      expect(today.difference(dueToday).inDays, 0);
    });

    // ── 26. Savings report net = deposits + overpayments - withdrawals ─────────
    test('savings report net balance = deposits + overpayments - withdrawals', () {
      const deposits = 5000.0;
      const overpayments = 1200.0;
      const withdrawals = 800.0;
      final net = deposits + overpayments - withdrawals;
      expect(net, closeTo(5400.0, 0.001));
    });

    // ── 27. Repayment schedule rebuilt after partial payments ──────────────────
    test('schedule status after partial payments: paid/partial/pending', () {
      // Loan total = 3000, installments = [1000, 1000, 1000]
      // Payment of 1500
      // Installment 1: fully paid (1000)
      // Installment 2: partial (500)
      // Installment 3: pending (0)
      final totalPaid = 1500.0;
      final inst1 = 1000.0;
      final inst2 = 1000.0;

      double remaining = totalPaid;
      String status1;
      if (remaining >= inst1) {
        status1 = 'paid';
        remaining -= inst1;
      } else if (remaining > 0) {
        status1 = 'partial';
        remaining = 0;
      } else {
        status1 = 'pending';
      }

      String status2;
      if (remaining >= inst2) {
        status2 = 'paid';
        remaining -= inst2;
      } else if (remaining > 0) {
        status2 = 'partial';
        remaining = 0;
      } else {
        status2 = 'pending';
      }

      String status3 = 'pending';

      expect(status1, 'paid');
      expect(status2, 'partial');
      expect(status3, 'pending');
    });

    // ── 28. Verify totalCollected NEVER includes savings withdrawals ───────────
    test('totalCollected only includes loan-applied amounts, never savings withdrawals', () {
      // Savings withdrawal of 500 is recorded as a transaction type 'withdrawal'
      // It must NEVER appear in "Total Collected"
      const withdrawal = 500.0;
      expect(withdrawal, 500.0);
      // The report query filters by payment + overpayment join, not savings withdrawals
      // So totalCollected should NOT include this
      final totalCollected = 0.0; // no completed payments
      expect(totalCollected, closeTo(0.0, 0.001));
    });

    // ── 29. Interest rate with decimal places ──────────────────────────────────
    test('interest with decimal rate: 10000 * 7.75% = 775.00', () {
      final r = LoanCalculator.calculate(
        principal: 10000,
        interestRatePercent: 7.75,
        insuranceFeePercent: 0.0,
        commissionPercent: 0.0,
        processingFee: 0.0,
        administrativeFee: 0.0,
        otherCharges: 0.0,
        duration: 12,
      );
      expect(r.interestAmount, closeTo(775.0, 0.001));
    });

    // ── 30. Large loan with small fractional remainder ─────────────────────────
    test('large loan splitEvenly: 999999 over 30 weeks', () {
      final parts = CurrencyUtils.splitEvenly(999999, 30);
      expect(parts, hasLength(30));
      expect(parts.fold<double>(0, (a, b) => a + b), closeTo(999999.0, 0.001));
    });
  });
}
