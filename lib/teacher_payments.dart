import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'financial_dashboard_models.dart';

class TeacherPaymentsPage extends StatefulWidget {
  const TeacherPaymentsPage({super.key});

  @override
  State<TeacherPaymentsPage> createState() => _TeacherPaymentsPageState();
}

class _TeacherPaymentsPageState extends State<TeacherPaymentsPage> {
  late final int _academicYear;
  late int _month;
  late Future<_PageData> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _academicYear = academicYearFor(now);
    _month = now.month;
    _future = _load();
  }

  Future<_PageData> _load() async {
    final client = Supabase.instance.client;
    final results = await Future.wait<Object?>([
      client.rpc(
        'get_financial_dashboard',
        params: {'input_academic_year': _academicYear, 'input_month': _month},
      ),
      client.rpc(
        'get_financial_expenses',
        params: {'input_academic_year': _academicYear, 'input_month': _month},
      ),
    ]);
    if (results.first is! Map) {
      throw const FormatException('Invalid financial response');
    }
    return _PageData(
      dashboard: FinancialDashboardData.fromRow(
        Map<String, dynamic>.from(results.first! as Map),
      ),
      expenses: readMapList(results.last)
          .map(FinancialExpense.fromRow)
          .where((row) => row.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _openPayments(String userId) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_teacher_payment_rows',
      );
      _PaymentRow? selected;
      for (final row in readMapList(result).map(_PaymentRow.fromRow)) {
        if (row.userId == userId) selected = row;
      }
      if (!mounted) return;
      if (selected == null) {
        _message('Δεν βρέθηκε η καρτέλα πληρωμών.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PaymentDetails(payment: selected!),
        ),
      );
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) _message('Δεν μπορέσαμε να ανοίξουμε τις πληρωμές.');
    }
  }

  Future<void> _editExpense([FinancialExpense? expense]) async {
    final calendarYear = academicMonthFor(_month).calendarYear(_academicYear);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseDialog(
        expense: expense,
        firstDate: DateTime(calendarYear, _month),
        lastDate: DateTime(calendarYear, _month + 1, 0),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _deleteExpense(FinancialExpense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Διαγραφή εξόδου;'),
        content: Text(
          'Το έξοδο «${expense.category}» (${formatMoney(expense.amount)}) '
          'θα διαγραφεί οριστικά.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ακύρωση'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'delete_financial_expense',
        params: {'input_id': expense.id},
      );
      if (mounted) {
        _message('Το έξοδο διαγράφηκε.');
        _refresh();
      }
    } catch (_) {
      if (mounted) _message('Δεν μπορέσαμε να διαγράψουμε το έξοδο.');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final selected = academicMonthFor(_month);
    final period =
        '${selected.label} '
        '${selected.calendarYear(_academicYear)}';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Column(
        children: [
          const _Header(),
          Expanded(
            child: FutureBuilder<_PageData>(
              future: _future,
              builder: (context, snapshot) => RefreshIndicator(
                onRefresh: () async {
                  _refresh();
                  await _future;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
                  children: [
                    _PeriodSelector(
                      year: _academicYear,
                      month: _month,
                      onChanged: (value) {
                        if (value == null || value == _month) return;
                        setState(() {
                          _month = value;
                          _future = _load();
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    if (snapshot.connectionState != ConnectionState.done)
                      const SizedBox(
                        height: 350,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      _Error(onRetry: _refresh)
                    else
                      _Content(
                        data: snapshot.data!,
                        period: period,
                        openPayments: _openPayments,
                        addExpense: () => _editExpense(),
                        editExpense: _editExpense,
                        deleteExpense: _deleteExpense,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageData {
  const _PageData({required this.dashboard, required this.expenses});
  final FinancialDashboardData dashboard;
  final List<FinancialExpense> expenses;
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFFFFF6CF), Color(0xFFFFE6B7)]),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
    ),
    child: SafeArea(
      bottom: false,
      child: SizedBox(
        height: 130,
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                tooltip: 'Πίσω',
              ),
            ),
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 42,
                    color: Color(0xFFB36B00),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Οικονομικά',
                    style: TextStyle(
                      color: Color(0xFF704800),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.year,
    required this.month,
    required this.onChanged,
  });
  final int year;
  final int month;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final monthField = DropdownButtonFormField<int>(
            initialValue: month,
            decoration: const InputDecoration(
              labelText: 'Μήνας',
              prefixIcon: Icon(Icons.calendar_month_rounded),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in academicMonths)
                DropdownMenuItem(value: item.number, child: Text(item.label)),
            ],
            onChanged: onChanged,
          );
          final yearField = DropdownButtonFormField<int>(
            initialValue: year,
            decoration: const InputDecoration(
              labelText: 'Ακαδημαϊκό έτος',
              prefixIcon: Icon(Icons.school_rounded),
              border: OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: year, child: Text('$year–${year + 1}')),
            ],
            onChanged: (_) {},
          );
          if (constraints.maxWidth < 560) {
            return Column(
              children: [monthField, const SizedBox(height: 12), yearField],
            );
          }
          return Row(
            children: [
              Expanded(child: monthField),
              const SizedBox(width: 12),
              Expanded(child: yearField),
            ],
          );
        },
      ),
    ),
  );
}

class _Content extends StatelessWidget {
  const _Content({
    required this.data,
    required this.period,
    required this.openPayments,
    required this.addExpense,
    required this.editExpense,
    required this.deleteExpense,
  });
  final _PageData data;
  final String period;
  final ValueChanged<String> openPayments;
  final VoidCallback addExpense;
  final ValueChanged<FinancialExpense> editExpense;
  final ValueChanged<FinancialExpense> deleteExpense;

  @override
  Widget build(BuildContext context) {
    final d = data.dashboard;
    final metrics = [
      _Metric(
        'Αναμενόμενα',
        formatMoney(d.expected),
        Icons.payments_outlined,
        const Color(0xFF3758C7),
      ),
      _Metric(
        'Εισπραχθέντα',
        formatMoney(d.received),
        Icons.check_circle_outline,
        const Color(0xFF258548),
      ),
      _Metric(
        'Υπόλοιπο',
        formatMoney(d.outstanding),
        Icons.pending_actions,
        const Color(0xFFD47C00),
      ),
      _Metric(
        'Οφειλέτες',
        '${d.debtorCount}',
        Icons.groups_rounded,
        const Color(0xFFB54747),
      ),
      _Metric(
        'Έξοδα',
        formatMoney(d.expenses),
        Icons.receipt_long,
        const Color(0xFF7D52A1),
      ),
      _Metric(
        'Καθαρό κέρδος',
        formatMoney(d.netProfit),
        Icons.trending_up,
        d.netProfit < 0 ? const Color(0xFFB54747) : const Color(0xFF187C63),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 520
                ? 2
                : 1;
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final m in metrics)
                  SizedBox(width: width, child: _MetricCard(m)),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Υπολογισμός βάσει boolean πληρωμών — όχι πλήρες λογιστικό σύστημα.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        const SizedBox(height: 20),
        _Section(
          title: 'Οφειλέτες · $period',
          icon: Icons.person_search_rounded,
          child: d.debtors.isEmpty
              ? const _Empty('Όλες οι πληρωμές του μήνα έχουν γίνει.')
              : Column(
                  children: [
                    for (final debtor in d.debtors)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(
                          debtor.userName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text('Απλήρωτος επιλεγμένος μήνας'),
                        trailing: _AmountAction(
                          amount: debtor.payment,
                          onPressed: () => openPayments(debtor.userId),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Πολλαπλοί ληξιπρόθεσμοι μήνες',
          icon: Icons.warning_amber_rounded,
          child: d.repeatedDebtors.isEmpty
              ? const _Empty(
                  'Δεν υπάρχουν οικογένειες με πάνω από έναν ληξιπρόθεσμο μήνα.',
                )
              : Column(
                  children: [
                    for (final debtor in d.repeatedDebtors)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text('${debtor.unpaidCount}'),
                        ),
                        title: Text(
                          debtor.userName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(debtor.unpaidMonths.join(', ')),
                        trailing: _AmountAction(
                          amount: debtor.estimatedDebt,
                          onPressed: () => openPayments(debtor.userId),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Έξοδα · $period',
          icon: Icons.receipt_long_rounded,
          action: FilledButton.icon(
            onPressed: addExpense,
            icon: const Icon(Icons.add),
            label: const Text('Νέο έξοδο'),
          ),
          child: data.expenses.isEmpty
              ? const _Empty('Δεν έχουν καταχωριστεί έξοδα για τον μήνα.')
              : Column(
                  children: [
                    for (final expense in data.expenses)
                      _ExpenseTile(
                        expense,
                        edit: () => editExpense(expense),
                        delete: () => deleteExpense(expense),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.metric);
  final _Metric metric;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: metric.color.withValues(alpha: .12),
            foregroundColor: metric.color,
            child: Icon(metric.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metric.value,
                  style: TextStyle(
                    color: metric.color,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF8A5A12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: action!),
          ],
          const Divider(height: 26),
          child,
        ],
      ),
    ),
  );
}

class _AmountAction extends StatelessWidget {
  const _AmountAction({required this.amount, required this.onPressed});
  final double amount;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        formatMoney(amount),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.open_in_new),
        tooltip: 'Πληρωμές',
      ),
    ],
  );
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile(this.expense, {required this.edit, required this.delete});
  final FinancialExpense expense;
  final VoidCallback edit;
  final VoidCallback delete;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const CircleAvatar(child: Icon(Icons.receipt)),
    title: Text(
      expense.category,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
    subtitle: Text(
      '${expense.date.day.toString().padLeft(2, '0')}/'
      '${expense.date.month.toString().padLeft(2, '0')}/${expense.date.year}'
      '${expense.description.isEmpty ? '' : ' · ${expense.description}'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          formatMoney(expense.amount),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        PopupMenuButton<String>(
          onSelected: (value) => value == 'edit' ? edit() : delete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Επεξεργασία')),
            PopupMenuItem(value: 'delete', child: Text('Διαγραφή')),
          ],
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.grey.shade700),
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 330,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('Δεν μπορέσαμε να φορτώσουμε τα οικονομικά.'),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Δοκιμή ξανά')),
        ],
      ),
    ),
  );
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    this.expense,
    required this.firstDate,
    required this.lastDate,
  });
  final FinancialExpense? expense;
  final DateTime firstDate;
  final DateTime lastDate;
  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  static const categories = [
    'Ενοίκιο',
    'Λογαριασμοί',
    'Μισθοδοσία',
    'Εκπαιδευτικό υλικό',
    'Συντήρηση',
    'Διαφήμιση',
    'Λοιπά',
    'Προσαρμοσμένη κατηγορία',
  ];
  final key = GlobalKey<FormState>();
  late final TextEditingController amount;
  late final TextEditingController description;
  late final TextEditingController custom;
  late DateTime date;
  late String category;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    date = expense?.date ?? widget.firstDate;
    final current = expense?.category ?? 'Λογαριασμοί';
    final predefined =
        categories.contains(current) && current != categories.last;
    category = predefined ? current : categories.last;
    amount = TextEditingController(
      text: expense == null ? '' : expense.amount.toStringAsFixed(2),
    );
    description = TextEditingController(text: expense?.description ?? '');
    custom = TextEditingController(text: predefined ? '' : current);
  }

  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    custom.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: widget.firstDate,
      lastDate: widget.lastDate,
      helpText: 'Ημερομηνία εξόδου',
    );
    if (value != null) setState(() => date = value);
  }

  Future<void> save() async {
    if (!key.currentState!.validate() || saving) return;
    setState(() => saving = true);
    try {
      await Supabase.instance.client.rpc(
        'save_financial_expense',
        params: {
          'input_id': widget.expense?.id,
          'input_expense_date': isoDate(date),
          'input_amount': double.parse(amount.text.replaceAll(',', '.')),
          'input_category': category == categories.last
              ? custom.text.trim()
              : category,
          'input_description': description.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Δεν μπορέσαμε να αποθηκεύσουμε το έξοδο.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.expense == null ? 'Νέο έξοδο' : 'Επεξεργασία εξόδου'),
    content: SizedBox(
      width: 470,
      child: Form(
        key: key,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month),
                title: const Text('Ημερομηνία'),
                subtitle: Text('${date.day}/${date.month}/${date.year}'),
                trailing: TextButton(
                  onPressed: saving ? null : pickDate,
                  child: const Text('Αλλαγή'),
                ),
              ),
              TextFormField(
                controller: amount,
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Ποσό',
                  suffixText: '€',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse(
                    (value ?? '').replaceAll(',', '.'),
                  );
                  return parsed == null || parsed <= 0
                      ? 'Συμπλήρωσε θετικό ποσό.'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                  labelText: 'Κατηγορία',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final value in categories)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => category = value!),
              ),
              if (category == categories.last) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: custom,
                  enabled: !saving,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Όνομα κατηγορίας',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Συμπλήρωσε κατηγορία.'
                      : null,
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: description,
                enabled: !saving,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Περιγραφή / σημειώσεις',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Ακύρωση'),
      ),
      FilledButton.icon(
        onPressed: saving ? null : save,
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: const Text('Αποθήκευση'),
      ),
    ],
  );
}

class _PaymentDetails extends StatefulWidget {
  const _PaymentDetails({required this.payment});
  final _PaymentRow payment;
  @override
  State<_PaymentDetails> createState() => _PaymentDetailsState();
}

class _PaymentDetailsState extends State<_PaymentDetails> {
  late final Map<String, bool> paid = Map.of(widget.payment.months);
  final saving = <String>{};

  Future<void> toggle(AcademicMonth month, bool value) async {
    if (saving.contains(month.column)) return;
    setState(() {
      paid[month.column] = value;
      saving.add(month.column);
    });
    try {
      await Supabase.instance.client.rpc(
        'update_teacher_payment_month',
        params: {
          'input_user_id': widget.payment.userId,
          'input_month': month.column,
          'input_paid': value,
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => paid[month.column] = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Η πληρωμή δεν ενημερώθηκε.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving.remove(month.column));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.payment.userName)),
    body: ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: academicMonths.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final month = academicMonths[index];
        final value = paid[month.column] ?? false;
        return Card(
          elevation: 0,
          color: value ? const Color(0xFFE8F6DF) : Colors.white,
          child: CheckboxListTile(
            value: value,
            onChanged: saving.contains(month.column)
                ? null
                : (checked) => toggle(month, checked ?? false),
            title: Text(
              month.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: saving.contains(month.column)
                ? const Text('Αποθήκευση…')
                : null,
          ),
        );
      },
    ),
  );
}

class _PaymentRow {
  const _PaymentRow({
    required this.userId,
    required this.userName,
    required this.months,
  });
  factory _PaymentRow.fromRow(Map<String, dynamic> row) => _PaymentRow(
    userId: row['user_id']?.toString() ?? '',
    userName: readText(row['user_name'], fallback: 'Χρήστης'),
    months: {
      for (final month in academicMonths)
        month.column: _isPaid(row[month.column]),
    },
  );
  final String userId;
  final String userName;
  final Map<String, bool> months;
}

bool _isPaid(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {
    'true',
    'paid',
    'yes',
    '1',
  }.contains(value?.toString().trim().toLowerCase());
}
