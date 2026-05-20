import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late final Future<Map<String, bool>> _paymentsFuture = _loadPayments();

  static const Color _headerColor = Color(0x9FF9FF89);
  static const Color _contentColor = Color(0xFFDB9538);
  static const List<_PaymentMonth> _months = [
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

  Future<Map<String, bool>> _loadPayments() async {
    final supabase = Supabase.instance.client;
    final linkedUser = await supabase.rpc('current_linked_user');

    final userRow = _asStringKeyMap(linkedUser);
    final userId = userRow?['id'];

    if (userId is! String || userId.trim().isEmpty) {
      return _emptyPayments();
    }

    final paymentRow = await supabase
        .from('payments')
        .select(_months.map((month) => month.column).join(', '))
        .eq('user_id', userId)
        .maybeSingle();

    if (paymentRow == null) {
      return _emptyPayments();
    }

    final row = Map<String, dynamic>.from(paymentRow);

    return {
      for (final month in _months) month.column: _isPaid(row[month.column]),
    };
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  Map<String, bool> _emptyPayments() {
    return {for (final month in _months) month.column: false};
  }

  bool _isPaid(dynamic value) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            height: 245,
            decoration: const BoxDecoration(
              color: _headerColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(48),
                bottomRight: Radius.circular(48),
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
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Πληρωμές',
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.savings_rounded,
                          color: _contentColor,
                          size: 82,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, bool>>(
              future: _paymentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Δεν μπορέσαμε να φορτώσουμε τις πληρωμές.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                final payments = snapshot.data ?? _emptyPayments();

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                  itemCount: _months.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final month = _months[index];
                    final isPaid = payments[month.column] ?? false;

                    return _PaymentMonthRow(
                      month: month.label,
                      isPaid: isPaid,
                      index: index,
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

class _PaymentMonth {
  const _PaymentMonth({required this.label, required this.column});

  final String label;
  final String column;
}

class _PaymentMonthRow extends StatelessWidget {
  const _PaymentMonthRow({
    required this.month,
    required this.isPaid,
    required this.index,
  });

  final String month;
  final bool isPaid;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isPaid ? const Color(0xFFDDF4E7) : const Color(0xFFECEEF3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 7,
            color: isPaid ? const Color(0xFF20B15A) : const Color(0xFFE5E7EC),
          ),
          const SizedBox(width: 14),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7DC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: _PaymentsPageState._contentColor,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              month,
              style: const TextStyle(
                color: Color(0xFF202124),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: isPaid
                  ? const Color(0xFF20B15A)
                  : const Color(0xFFF1F2F5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPaid ? Icons.check_rounded : Icons.remove_rounded,
              color: isPaid ? Colors.white : const Color(0xFFB7BBC4),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}
