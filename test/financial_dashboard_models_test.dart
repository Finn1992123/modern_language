import 'package:flutter_test/flutter_test.dart';
import 'package:modern_language/financial_dashboard_models.dart';

void main() {
  test('academic year runs from September through August', () {
    expect(academicYearFor(DateTime(2026, 8, 31)), 2025);
    expect(academicYearFor(DateTime(2026, 9)), 2026);
    expect(academicMonthFor(9).calendarYear(2026), 2026);
    expect(academicMonthFor(1).calendarYear(2026), 2027);
  });

  test('dashboard reads numeric Supabase values and backend totals', () {
    final dashboard = FinancialDashboardData.fromRow({
      'expected': '1000.00',
      'received': 750,
      'outstanding': '250',
      'debtor_count': 2,
      'expenses': '125.50',
      'net_profit': '624.50',
      'debtors': [
        {
          'user_id': 'user-1',
          'user_name': 'Tonia Kontaxi',
          'payment': '100',
          'month': 'august',
        },
      ],
      'repeated_debtors': [
        {
          'user_id': 'user-2',
          'user_name': 'Family',
          'unpaid_count': 2,
          'unpaid_months': ['Μάιος 2026', 'Ιούνιος 2026'],
          'estimated_debt': '200',
        },
      ],
    });

    expect(dashboard.expected, 1000);
    expect(dashboard.received, 750);
    expect(dashboard.outstanding, 250);
    expect(dashboard.expenses, 125.5);
    expect(dashboard.netProfit, 624.5);
    expect(dashboard.debtors.single.userName, 'Tonia Kontaxi');
    expect(dashboard.repeatedDebtors.single.unpaidCount, 2);
  });

  test('money formatting keeps cents and negative values', () {
    expect(formatMoney(120), '120 €');
    expect(formatMoney(120.5), '120,50 €');
    expect(formatMoney(-20.25), '-20,25 €');
  });
}
