/// Shared SQL fragment excluding installments due on an ENABLED holiday
/// (one-time or recurring) from collection and overdue queries.
///
/// Holidays behave like weekends everywhere: money is never shown as
/// collectable on a holiday, and a skipped holiday day never counts toward
/// overdue — even when a loan's schedule was generated before the holiday was
/// created (a read-time safety net alongside `LoanScheduleService`, which
/// re-derives every schedule off the holidays after any holiday change).
///
/// Requires `repayment_schedule` to be aliased as `rs` in the query.
const String notOnEnabledHolidaySql = '''
    NOT EXISTS (
      SELECT 1 FROM holidays h
      WHERE h.is_enabled = 1
        AND (
          (h.is_recurring = 0 AND h.date = DATE(rs.due_date))
          OR (h.is_recurring = 1
              AND substr(h.date, 6, 5) = substr(rs.due_date, 6, 5))
        )
    )
  ''';
