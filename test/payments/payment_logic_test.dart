import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/payments/data/payment_logic.dart';

void main() {
  group('computePaymentSplit', () {
    // ── Normal payment (partial) ──────────────────────────────────────────────
    test('partial payment: applied = amount, surplus = 0', () {
      final result = computePaymentSplit(
        paymentAmount: 5000,
        outstandingBalance: 10000,
      );
      expect(result.appliedToLoan, 5000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 5000);
    });

    // ── Exact payment ─────────────────────────────────────────────────────────
    test('exact payment: applied = outstanding, surplus = 0, new balance = 0', () {
      final result = computePaymentSplit(
        paymentAmount: 10000,
        outstandingBalance: 10000,
      );
      expect(result.appliedToLoan, 10000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 0);
    });

    // ── Overpayment ───────────────────────────────────────────────────────────
    test('overpayment: applied = outstanding, surplus = excess, new balance = 0', () {
      final result = computePaymentSplit(
        paymentAmount: 12000,
        outstandingBalance: 10000,
      );
      expect(result.appliedToLoan, 10000);
      expect(result.overpaymentSurplus, 2000);
      expect(result.newLoanBalance, 0);
    });

    test('overpayment: loan balance never goes negative', () {
      final result = computePaymentSplit(
        paymentAmount: 50000,
        outstandingBalance: 1000,
      );
      expect(result.newLoanBalance, 0);
      expect(result.overpaymentSurplus, 49000);
    });

    test('small overpayment: fractional surplus is correct', () {
      final result = computePaymentSplit(
        paymentAmount: 10001,
        outstandingBalance: 10000,
      );
      expect(result.overpaymentSurplus, closeTo(1, 0.001));
      expect(result.appliedToLoan, 10000);
    });

    // ── Payment beyond the next installment (H1 regression guard) ───────────
    test('payment larger than one installment applies fully to the loan', () {
      // outstanding=10000, payment=7000, NO installment context supplied —
      // a settlement/"quick pay" payment caps at the outstanding balance and
      // must reduce the loan by the full amount, not dump the rest to savings.
      final result = computePaymentSplit(
        paymentAmount: 7000,
        outstandingBalance: 10000,
      );
      expect(result.appliedToLoan, 7000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 3000);
    });

    test('payment equals outstanding: clears the loan, no surplus', () {
      final result = computePaymentSplit(
        paymentAmount: 5000,
        outstandingBalance: 5000,
      );
      expect(result.appliedToLoan, 5000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 0);
    });

    test('payment less than outstanding: partial, no surplus', () {
      final result = computePaymentSplit(
        paymentAmount: 3000,
        outstandingBalance: 10000,
      );
      expect(result.appliedToLoan, 3000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 7000);
    });

    test('payment beyond outstanding: capped at outstanding, surplus to savings', () {
      // outstanding=2000, payment=10000 — only the excess beyond the balance
      // is credited to savings.
      final result = computePaymentSplit(
        paymentAmount: 10000,
        outstandingBalance: 2000,
      );
      expect(result.appliedToLoan, 2000);
      expect(result.overpaymentSurplus, 8000);
      expect(result.newLoanBalance, 0);
    });

    test('zero outstanding: entire payment goes to savings', () {
      final result = computePaymentSplit(
        paymentAmount: 5000,
        outstandingBalance: 0,
      );
      expect(result.appliedToLoan, 0);
      expect(result.overpaymentSurplus, 5000);
      expect(result.newLoanBalance, 0);
    });

    // ── Excess over the installment goes to savings (2026-08-01 rule) ────────
    test('excess over installment: applied = installment, surplus to savings', () {
      // outstanding=10000, installment=1000, payment=1500 — the 500 above the
      // installment is credited to savings, NOT applied to the loan.
      final result = computePaymentSplit(
        paymentAmount: 1500,
        outstandingBalance: 10000,
        installmentDue: 1000,
      );
      expect(result.appliedToLoan, 1000);
      expect(result.overpaymentSurplus, 500);
      expect(result.newLoanBalance, 9000);
    });

    test('payment at or below installment applies fully to the loan', () {
      final result = computePaymentSplit(
        paymentAmount: 800,
        outstandingBalance: 10000,
        installmentDue: 1000,
      );
      expect(result.appliedToLoan, 800);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 9200);
    });

    test('exact installment: no surplus', () {
      final result = computePaymentSplit(
        paymentAmount: 1000,
        outstandingBalance: 10000,
        installmentDue: 1000,
      );
      expect(result.appliedToLoan, 1000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 9000);
    });

    test('zero/omitted installment falls back to the outstanding balance', () {
      final result = computePaymentSplit(
        paymentAmount: 7000,
        outstandingBalance: 10000,
        installmentDue: 0,
      );
      expect(result.appliedToLoan, 7000);
      expect(result.overpaymentSurplus, 0);
      expect(result.newLoanBalance, 3000);
    });

    test('large overpayment with installment context caps loan at installment', () {
      // outstanding=10000, installment=1000, payment=12000 — 1000 to the loan,
      // 11000 to savings.
      final result = computePaymentSplit(
        paymentAmount: 12000,
        outstandingBalance: 10000,
        installmentDue: 1000,
      );
      expect(result.appliedToLoan, 1000);
      expect(result.overpaymentSurplus, 11000);
      expect(result.newLoanBalance, 9000);
    });
  });

  group('computeReversalLoanDelta', () {
    test('reversing a normal payment: delta = full payment amount', () {
      final delta = computeReversalLoanDelta(
        paymentAmount: 5000,
        overpaymentSurplus: 0,
      );
      expect(delta, 5000);
    });

    test('reversing an overpayment: delta excludes the savings-credited surplus', () {
      // Payment of 12000 on a 10000 loan → 10000 applied to loan, 2000 to savings.
      // Reversal should restore exactly 10000 to the loan, not 12000.
      final delta = computeReversalLoanDelta(
        paymentAmount: 12000,
        overpaymentSurplus: 2000,
      );
      expect(delta, 10000);
    });

    test('reversing exact full payment: delta = full payment amount', () {
      final delta = computeReversalLoanDelta(
        paymentAmount: 10000,
        overpaymentSurplus: 0,
      );
      expect(delta, 10000);
    });

    test('loan balance invariant: restored balance ≤ original outstanding', () {
      // This asserts the critical invariant: we never restore more than
      // what was actually applied to the loan.
      const paymentAmount = 15000.0;
      const outstanding = 10000.0;
      final split = computePaymentSplit(
        paymentAmount: paymentAmount,
        outstandingBalance: outstanding,
      );
      final delta = computeReversalLoanDelta(
        paymentAmount: paymentAmount,
        overpaymentSurplus: split.overpaymentSurplus,
      );
      // After reversal, new loan balance = 0 + delta = delta.
      // delta must equal the original outstanding (what was applied to the loan).
      expect(delta, split.appliedToLoan);
      expect(delta, outstanding); // since payment > outstanding, all outstanding applied
    });
  });

  group('computeSavingsReversal', () {
    test('sufficient balance: full surplus deducted', () {
      final (newBalance, deducted) = computeSavingsReversal(
        balance: 5000,
        overpaymentSurplus: 2000,
      );
      expect(newBalance, 3000);
      expect(deducted, 2000);
    });

    test('insufficient balance: deducts only what is available, never goes negative', () {
      // Customer withdrew some savings between the overpayment and the reversal.
      final (newBalance, deducted) = computeSavingsReversal(
        balance: 1500,
        overpaymentSurplus: 2000,
      );
      expect(newBalance, 0);
      expect(deducted, 1500); // only 1500 available
    });

    test('exact balance: account reaches zero', () {
      final (newBalance, deducted) = computeSavingsReversal(
        balance: 2000,
        overpaymentSurplus: 2000,
      );
      expect(newBalance, 0);
      expect(deducted, 2000);
    });
  });

  group('schedule recalculation — mixed payment sequences', () {
    // Simulates the SQL logic used by _recalculateScheduleFromPayments:
    // each payment's "loan-applied" portion = amount - overpaymentSurplus
    double simulateScheduleTotal(
        List<({double amount, double overpaymentSurplus})> completedPayments) {
      return completedPayments.fold(
          0.0, (sum, p) => sum + (p.amount - p.overpaymentSurplus));
    }

    test('partial + overpayment: schedule total equals sum of loan-applied portions', () {
      // Loan: 10000. Payment 1: 3000 (partial). Payment 2: 8000 (overpays by 1000).
      // Applied to loan: P1=3000, P2=7000. Total applied=10000 (clears loan).
      const outstanding = 10000.0;

      final p1 = computePaymentSplit(paymentAmount: 3000, outstandingBalance: outstanding);
      final p2 = computePaymentSplit(paymentAmount: 8000, outstandingBalance: outstanding - p1.appliedToLoan);

      final scheduleTotal = simulateScheduleTotal([
        (amount: 3000, overpaymentSurplus: p1.overpaymentSurplus),
        (amount: 8000, overpaymentSurplus: p2.overpaymentSurplus),
      ]);

      expect(scheduleTotal, closeTo(outstanding, 0.001)); // loan fully settled
      expect(p2.overpaymentSurplus, closeTo(1000, 0.001)); // 1000 went to savings
    });

    test('reversing partial payment: schedule total does NOT overstate loan balance', () {
      // Loan: 10000.
      // P1 = 3000 (partial, normal). P2 = 8000 (overpayment by 1000 vs remaining 7000).
      // Reverse P1. Remaining completed = [P2].
      // P2 loan-applied = 7000 (not 8000). Schedule total should be 7000,
      // which matches loan balance restored to outstanding - P2.appliedToLoan = 3000.
      const outstanding = 10000.0;

      final p1 = computePaymentSplit(paymentAmount: 3000, outstandingBalance: outstanding);
      final remainingAfterP1 = outstanding - p1.appliedToLoan; // 7000
      final p2 = computePaymentSplit(paymentAmount: 8000, outstandingBalance: remainingAfterP1);

      // After P1 reversal, only P2 remains completed.
      final scheduleTotal = simulateScheduleTotal([
        (amount: 8000, overpaymentSurplus: p2.overpaymentSurplus),
      ]);

      expect(p2.appliedToLoan, closeTo(7000, 0.001));
      expect(scheduleTotal, closeTo(7000, 0.001)); // schedule correctly reflects 7000 applied
      expect(p2.overpaymentSurplus, closeTo(1000, 0.001));

      // Reversal delta for P1 (no overpayment)
      final p1ReversalDelta = computeReversalLoanDelta(
        paymentAmount: 3000,
        overpaymentSurplus: 0,
      );
      final loanOutstandingAfterReversal = p2.newLoanBalance + p1ReversalDelta;
      // loan outstanding + schedule applied = original outstanding
      expect(loanOutstandingAfterReversal + scheduleTotal, closeTo(outstanding, 0.001));
    });

    test('raw payment amount overstates schedule when overpayment exists', () {
      // Documents the bug fixed by using loan-applied amounts:
      // Using raw amounts would give 11000 (3000 + 8000) instead of 10000.
      const outstanding = 10000.0;
      final p1 = computePaymentSplit(paymentAmount: 3000, outstandingBalance: outstanding);
      final p2 = computePaymentSplit(paymentAmount: 8000, outstandingBalance: outstanding - p1.appliedToLoan);

      final rawTotal = 3000.0 + 8000.0; // naïve sum
      final correctedTotal = simulateScheduleTotal([
        (amount: 3000, overpaymentSurplus: p1.overpaymentSurplus),
        (amount: 8000, overpaymentSurplus: p2.overpaymentSurplus),
      ]);

      expect(rawTotal, 11000); // overstates by 1000 (the savings surplus)
      expect(correctedTotal, closeTo(10000, 0.001)); // correct
    });
  });

  group('end-to-end invariants', () {
    test('loan balance + savings balance conserved after payment and reversal', () {
      // Initial state
      const outstanding = 10000.0;
      const initialSavings = 500.0;
      const paymentAmount = 12500.0;

      // === Payment ===
      final split = computePaymentSplit(
        paymentAmount: paymentAmount,
        outstandingBalance: outstanding,
      );
      // Loan balance after payment
      final loanAfterPayment = split.newLoanBalance; // 0
      // Savings balance after payment
      final savingsAfterPayment = initialSavings + split.overpaymentSurplus; // 500 + 2500

      expect(loanAfterPayment, 0);
      expect(savingsAfterPayment, 3000);

      // === Reversal ===
      final loanDelta = computeReversalLoanDelta(
        paymentAmount: paymentAmount,
        overpaymentSurplus: split.overpaymentSurplus,
      );
      final (savingsAfterReversal, _) = computeSavingsReversal(
        balance: savingsAfterPayment,
        overpaymentSurplus: split.overpaymentSurplus,
      );
      final loanAfterReversal = loanAfterPayment + loanDelta;

      // Invariant: system returns to the original state
      expect(loanAfterReversal, closeTo(outstanding, 0.001));
      expect(savingsAfterReversal, closeTo(initialSavings, 0.001));
    });

    test('normal payment reversal: loan balance fully restored', () {
      const outstanding = 8000.0;
      const paymentAmount = 3000.0; // partial

      final split = computePaymentSplit(
        paymentAmount: paymentAmount,
        outstandingBalance: outstanding,
      );
      expect(split.overpaymentSurplus, 0);

      final delta = computeReversalLoanDelta(
        paymentAmount: paymentAmount,
        overpaymentSurplus: 0,
      );
      final loanAfterReversal = split.newLoanBalance + delta;
      expect(loanAfterReversal, closeTo(outstanding, 0.001));
    });
  });

  group('invalid numeric inputs are rejected', () {
    // NaN/±Infinity (from typed text like "1e309") must never flow into the
    // schedule math and get stored as NULL. The debug-only asserts previously
    // never ran in release builds.
    test('NaN paymentAmount throws', () {
      expect(
        () => computePaymentSplit(
            paymentAmount: double.nan, outstandingBalance: 10000),
        throwsArgumentError,
      );
    });

    test('Infinity paymentAmount (1e309) throws', () {
      expect(
        () => computePaymentSplit(
            paymentAmount: double.infinity, outstandingBalance: 10000),
        throwsArgumentError,
      );
      expect(
        () => computePaymentSplit(
            paymentAmount: double.negativeInfinity, outstandingBalance: 10000),
        throwsArgumentError,
      );
    });

    test('zero and negative paymentAmount throw', () {
      expect(
        () => computePaymentSplit(
            paymentAmount: 0, outstandingBalance: 10000),
        throwsArgumentError,
      );
      expect(
        () => computePaymentSplit(
            paymentAmount: -100, outstandingBalance: 10000),
        throwsArgumentError,
      );
    });

    test('non-finite outstandingBalance throws', () {
      expect(
        () => computePaymentSplit(
            paymentAmount: 500, outstandingBalance: double.nan),
        throwsArgumentError,
      );
      expect(
        () => computePaymentSplit(
            paymentAmount: 500, outstandingBalance: double.infinity),
        throwsArgumentError,
      );
    });

    test('valid payment with installment context still splits correctly', () {
      final split = computePaymentSplit(
        paymentAmount: 1200,
        outstandingBalance: 10000,
        installmentDue: 500,
      );
      expect(split.appliedToLoan, 500);
      expect(split.overpaymentSurplus, 700);
      expect(split.newLoanBalance, 9500);
    });
  });
}
