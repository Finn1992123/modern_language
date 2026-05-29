import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherPaymentsPage extends StatefulWidget {
  const TeacherPaymentsPage({super.key});

  @override
  State<TeacherPaymentsPage> createState() => _TeacherPaymentsPageState();
}

class _TeacherPaymentsPageState extends State<TeacherPaymentsPage> {
  late Future<List<_TeacherPaymentRow>> _paymentsFuture = _loadPayments();

  Future<List<_TeacherPaymentRow>> _loadPayments() async {
    final rows = await Supabase.instance.client.rpc('get_teacher_payment_rows');

    if (rows is! List) {
      return const [];
    }

    return rows
        .whereType<Map>()
        .map(
          (row) => _TeacherPaymentRow.fromRow(Map<String, dynamic>.from(row)),
        )
        .where((row) => row.userId.isNotEmpty)
        .toList();
  }

  void _refresh() {
    setState(() {
      _paymentsFuture = _loadPayments();
    });
  }

  Future<void> _openPaymentDetails(_TeacherPaymentRow payment) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _TeacherPaymentDetailsPage(payment: payment),
      ),
    );

    if (!mounted) {
      return;
    }

    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const _TeacherPaymentsHeader(title: 'Πληρωμές'),
          Expanded(
            child: FutureBuilder<List<_TeacherPaymentRow>>(
              future: _paymentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _TeacherPaymentsMessage(
                    text: 'Δεν μπορέσαμε να φορτώσουμε τις πληρωμές.',
                    onRetry: _refresh,
                  );
                }

                final payments = snapshot.data ?? const [];

                if (payments.isEmpty) {
                  return const _TeacherPaymentsMessage(
                    text: 'Δεν υπάρχουν γονείς στον πίνακα πληρωμών.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
                  itemCount: payments.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final payment = payments[index];
                    return _ParentPaymentTile(
                      payment: payment,
                      onTap: () => _openPaymentDetails(payment),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherPaymentDetailsPage extends StatefulWidget {
  const _TeacherPaymentDetailsPage({required this.payment});

  final _TeacherPaymentRow payment;

  @override
  State<_TeacherPaymentDetailsPage> createState() =>
      _TeacherPaymentDetailsPageState();
}

class _TeacherPaymentDetailsPageState
    extends State<_TeacherPaymentDetailsPage> {
  late final Map<String, bool> _months = Map<String, bool>.from(
    widget.payment.months,
  );
  final Set<String> _savingMonths = {};

  Future<void> _toggleMonth(_PaymentMonth month, bool paid) async {
    if (_savingMonths.contains(month.column)) {
      return;
    }

    setState(() {
      _months[month.column] = paid;
      _savingMonths.add(month.column);
    });

    try {
      await Supabase.instance.client.rpc(
        'update_teacher_payment_month',
        params: {
          'input_user_id': widget.payment.userId,
          'input_month': month.column,
          'input_paid': paid,
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _months[month.column] = !paid;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Δεν μπορέσαμε να ενημερώσουμε την πληρωμή.'),
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingMonths.remove(month.column);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _TeacherPaymentsHeader(title: widget.payment.userName),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
              itemCount: _paymentMonths.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final month = _paymentMonths[index];
                final isPaid = _months[month.column] ?? false;
                final isSaving = _savingMonths.contains(month.column);

                return _TeacherPaymentMonthTile(
                  month: month,
                  isPaid: isPaid,
                  isSaving: isSaving,
                  onChanged: (value) => _toggleMonth(month, value ?? false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherPaymentsHeader extends StatelessWidget {
  const _TeacherPaymentsHeader({required this.title});

  static const Color _headerColor = Color(0x9FF9FF89);
  static const Color _contentColor = Color(0xFFDB9538);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: const BoxDecoration(
        color: _headerColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(42),
          bottomRight: Radius.circular(42),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 12,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(18),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFF8E8E93),
                    size: 22,
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 70),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _contentColor,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Icon(
                      Icons.savings_rounded,
                      color: _contentColor,
                      size: 74,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentPaymentTile extends StatelessWidget {
  const _ParentPaymentTile({required this.payment, required this.onTap});

  final _TeacherPaymentRow payment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFCF0),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              const Icon(Icons.person_rounded, color: Color(0xFFDB9538)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  payment.userName,
                  style: const TextStyle(
                    color: Color(0xFF202124),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (payment.paymentAmount != null) ...[
                const SizedBox(width: 10),
                Text(
                  _formatPaymentAmount(payment.paymentAmount!),
                  style: const TextStyle(
                    color: Color(0xFF202124),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Text(
                '${payment.paidCount}/${_paymentMonths.length}',
                style: const TextStyle(
                  color: Color(0xFFDB9538),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeacherPaymentMonthTile extends StatelessWidget {
  const _TeacherPaymentMonthTile({
    required this.month,
    required this.isPaid,
    required this.isSaving,
    required this.onChanged,
  });

  final _PaymentMonth month;
  final bool isPaid;
  final bool isSaving;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: isPaid ? const Color(0xFFE6F8D8) : const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPaid ? const Color(0xFF86C85F) : const Color(0xFFE5E8F2),
          width: 1.3,
        ),
      ),
      child: CheckboxListTile(
        value: isPaid,
        onChanged: isSaving ? null : onChanged,
        activeColor: const Color(0xFF58B832),
        checkColor: Colors.white,
        controlAffinity: ListTileControlAffinity.trailing,
        title: Text(
          month.label,
          style: const TextStyle(
            color: Color(0xFF202124),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        secondary: isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Icon(
                isPaid ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isPaid
                    ? const Color(0xFF58B832)
                    : const Color(0xFFB7BBC4),
              ),
      ),
    );
  }
}

class _TeacherPaymentsMessage extends StatelessWidget {
  const _TeacherPaymentsMessage({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Δοκιμή ξανά'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeacherPaymentRow {
  const _TeacherPaymentRow({
    required this.userId,
    required this.userName,
    required this.paymentAmount,
    required this.months,
  });

  factory _TeacherPaymentRow.fromRow(Map<String, dynamic> row) {
    return _TeacherPaymentRow(
      userId: row['user_id']?.toString() ?? '',
      userName: _readText(row['user_name']) ?? 'Γονιός',
      paymentAmount: _readNumber(row['payment']),
      months: {
        for (final month in _paymentMonths)
          month.column: _isPaid(row[month.column]),
      },
    );
  }

  final String userId;
  final String userName;
  final double? paymentAmount;
  final Map<String, bool> months;

  int get paidCount => months.values.where((paid) => paid).length;
}

class _PaymentMonth {
  const _PaymentMonth({required this.label, required this.column});

  final String label;
  final String column;
}

const _paymentMonths = [
  _PaymentMonth(label: 'Σεπτέμβρης', column: 'september'),
  _PaymentMonth(label: 'Οκτώβρης', column: 'october'),
  _PaymentMonth(label: 'Νοέμβρης', column: 'november'),
  _PaymentMonth(label: 'Δεκέμβρης', column: 'december'),
  _PaymentMonth(label: 'Ιανουάριος', column: 'january'),
  _PaymentMonth(label: 'Φεβρουάριος', column: 'february'),
  _PaymentMonth(label: 'Μάρτιος', column: 'march'),
  _PaymentMonth(label: 'Απρίλιος', column: 'april'),
  _PaymentMonth(label: 'Μάιος', column: 'may'),
  _PaymentMonth(label: 'Ιούνιος', column: 'june'),
  _PaymentMonth(label: 'Ιούλιος', column: 'july'),
  _PaymentMonth(label: 'Αύγουστος', column: 'august'),
];

bool _isPaid(Object? value) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == 'paid' ||
        normalized == 'yes' ||
        normalized == '1';
  }

  return false;
}

String? _readText(Object? value) {
  if (value is! String) {
    return null;
  }

  final text = value.trim();
  return text.isEmpty ? null : text;
}

double? _readNumber(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }

  return null;
}

String _formatPaymentAmount(double value) {
  final rounded = value.roundToDouble();
  final text = value == rounded
      ? rounded.toInt().toString()
      : value.toStringAsFixed(2);

  return '$text€';
}
