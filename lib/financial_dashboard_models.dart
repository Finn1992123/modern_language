class AcademicMonth {
  const AcademicMonth(this.number, this.column, this.label);

  final int number;
  final String column;
  final String label;

  int calendarYear(int academicYear) =>
      number >= 9 ? academicYear : academicYear + 1;
}

const academicMonths = <AcademicMonth>[
  AcademicMonth(9, 'september', 'Σεπτέμβριος'),
  AcademicMonth(10, 'october', 'Οκτώβριος'),
  AcademicMonth(11, 'november', 'Νοέμβριος'),
  AcademicMonth(12, 'december', 'Δεκέμβριος'),
  AcademicMonth(1, 'january', 'Ιανουάριος'),
  AcademicMonth(2, 'february', 'Φεβρουάριος'),
  AcademicMonth(3, 'march', 'Μάρτιος'),
  AcademicMonth(4, 'april', 'Απρίλιος'),
  AcademicMonth(5, 'may', 'Μάιος'),
  AcademicMonth(6, 'june', 'Ιούνιος'),
  AcademicMonth(7, 'july', 'Ιούλιος'),
  AcademicMonth(8, 'august', 'Αύγουστος'),
];

int academicYearFor(DateTime date) =>
    date.month >= 9 ? date.year : date.year - 1;

AcademicMonth academicMonthFor(int month) => academicMonths.firstWhere(
  (item) => item.number == month,
  orElse: () => throw ArgumentError.value(month, 'month'),
);

class FinancialDashboardData {
  const FinancialDashboardData({
    required this.expected,
    required this.received,
    required this.outstanding,
    required this.debtorCount,
    required this.expenses,
    required this.netProfit,
    required this.debtors,
    required this.repeatedDebtors,
  });

  factory FinancialDashboardData.fromRow(Map<String, dynamic> row) {
    return FinancialDashboardData(
      expected: readAmount(row['expected']),
      received: readAmount(row['received']),
      outstanding: readAmount(row['outstanding']),
      debtorCount: readInteger(row['debtor_count']),
      expenses: readAmount(row['expenses']),
      netProfit: readAmount(row['net_profit']),
      debtors: readMapList(
        row['debtors'],
      ).map(FinancialDebtor.fromRow).toList(growable: false),
      repeatedDebtors: readMapList(
        row['repeated_debtors'],
      ).map(RepeatedFinancialDebtor.fromRow).toList(growable: false),
    );
  }

  final double expected;
  final double received;
  final double outstanding;
  final int debtorCount;
  final double expenses;
  final double netProfit;
  final List<FinancialDebtor> debtors;
  final List<RepeatedFinancialDebtor> repeatedDebtors;
}

class FinancialDebtor {
  const FinancialDebtor({
    required this.userId,
    required this.userName,
    required this.payment,
    required this.month,
  });

  factory FinancialDebtor.fromRow(Map<String, dynamic> row) => FinancialDebtor(
    userId: row['user_id']?.toString() ?? '',
    userName: readText(row['user_name'], fallback: 'Χρήστης'),
    payment: readAmount(row['payment']),
    month: row['month']?.toString() ?? '',
  );

  final String userId;
  final String userName;
  final double payment;
  final String month;
}

class RepeatedFinancialDebtor {
  const RepeatedFinancialDebtor({
    required this.userId,
    required this.userName,
    required this.unpaidCount,
    required this.unpaidMonths,
    required this.estimatedDebt,
  });

  factory RepeatedFinancialDebtor.fromRow(Map<String, dynamic> row) {
    final months = row['unpaid_months'];
    return RepeatedFinancialDebtor(
      userId: row['user_id']?.toString() ?? '',
      userName: readText(row['user_name'], fallback: 'Χρήστης'),
      unpaidCount: readInteger(row['unpaid_count']),
      unpaidMonths: months is List
          ? months.map((value) => value.toString()).toList(growable: false)
          : const [],
      estimatedDebt: readAmount(row['estimated_debt']),
    );
  }

  final String userId;
  final String userName;
  final int unpaidCount;
  final List<String> unpaidMonths;
  final double estimatedDebt;
}

class FinancialExpense {
  const FinancialExpense({
    required this.id,
    required this.date,
    required this.amount,
    required this.category,
    required this.description,
    required this.createdByName,
  });

  factory FinancialExpense.fromRow(Map<String, dynamic> row) {
    return FinancialExpense(
      id: row['id']?.toString() ?? '',
      date:
          DateTime.tryParse(row['expense_date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      amount: readAmount(row['amount']),
      category: readText(row['category'], fallback: 'Λοιπά'),
      description: readText(row['description']),
      createdByName: readText(row['created_by_name']),
    );
  }

  final String id;
  final DateTime date;
  final double amount;
  final String category;
  final String description;
  final String createdByName;
}

List<Map<String, dynamic>> readMapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

String readText(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

double readAmount(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

int readInteger(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String formatMoney(double value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  final formatted = absolute == absolute.roundToDouble()
      ? absolute.toInt().toString()
      : absolute.toStringAsFixed(2).replaceAll('.', ',');
  return '$sign$formatted €';
}

String isoDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
