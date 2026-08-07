import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';

/// The fully derived repayment view for one loan: the deterministic
/// installment list plus the aggregate figures consumers display.
class LoanScheduleResult {
  const LoanScheduleResult({
    required this.installments,
    required this.totalPaid,
    required this.pendingBalance,
  });

  /// Installments in installment-number (due-date) order, each carrying the
  /// derived `status` / `paid_amount`.
  final List<RepaymentInstallment> installments;

  /// Total loan-applied money (completed payments minus overpayment surplus).
  /// Capped at `total_repayment`.
  final double totalPaid;

  /// `total_repayment − totalPaid` (>= 0). Always computed, never stored.
  final double pendingBalance;
}

/// Derives a loan's full repayment schedule as a **pure function of its source
/// data** — the loan itself, the enabled holidays, and the total money applied
/// to the loan — with no dependency on whatever happened to be stored in the
/// `repayment_schedule` table on this device.
///
/// The derivation is deterministic:
///  * due dates come from `ScheduleGenerator.generate` (a pure function of
///    start date + loan type + duration + holidays), so the same loan built on
///    two devices produces byte-for-byte identical rows; and
///  * paid allocation walks the installments oldest-first, marking each `paid`
///    or `partial` until the applied total is exhausted — the same money rule
///    `_recalculateScheduleFromPayments` used to enforce (sum of completed
///    payments minus overpayment surplus), just computed rather than stored.
class LoanScheduleCalculator {
  LoanScheduleCalculator._();

  /// Builds the derived schedule for [loan].
  ///
  /// [totalAppliedToLoan] is the money that actually reduced the loan balance:
  /// `Σ(completed payment.amount − overpayment surplus)`. Overpayment surplus
  /// is deliberately excluded (owner lock-in, 2026-08-01: excess over the
  /// current installment is always credited to savings and never applied past
  /// the installment to the loan), and `clearLoanWithSavings` payments are
  /// fully applied (they have no surplus).
  static LoanScheduleResult build({
    required Loan loan,
    required List<Holiday> holidays,
    required double totalAppliedToLoan,
  }) {
    final totalRepayment = loan.totalRepayment;
    final applied = totalAppliedToLoan.isFinite
        ? totalAppliedToLoan.clamp(0.0, totalRepayment)
        : 0.0;

    // Per-installment amounts split evenly so their sum exactly equals
    // total_repayment (H2 guard) — a loan must be able to reach `completed`.
    final amounts = CurrencyUtils.splitEvenly(totalRepayment, loan.duration);
    final generated = ScheduleGenerator.generate(
      loanId: loan.id,
      loanType: loan.loanType,
      startDate: loan.repaymentStartDate,
      amounts: amounts,
      holidays: holidays,
    );

    // Allocate the applied total chronologically (oldest unpaid first). This
    // is order-independent in the payment history — only the total matters —
    // so it is deterministic across devices regardless of payment order.
    final installments = <RepaymentInstallment>[];
    var remaining = applied;
    for (final base in generated) {
      if (remaining >= base.amount - 0.005) {
        installments.add(base.copyWith(
          status: RepaymentStatus.paid,
          paidAmount: base.amount,
        ));
        remaining -= base.amount;
      } else if (remaining > 0.005) {
        installments.add(base.copyWith(
          status: RepaymentStatus.partial,
          paidAmount: remaining,
        ));
        remaining = 0;
      } else {
        installments.add(base);
      }
    }

    return LoanScheduleResult(
      installments: installments,
      totalPaid: applied,
      pendingBalance: totalRepayment - applied,
    );
  }
}
