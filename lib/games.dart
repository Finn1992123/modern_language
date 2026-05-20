import 'package:flutter/material.dart';

class GamesPage extends StatelessWidget {
  const GamesPage({super.key});

  static const Color _headerColor = Color(0xFF4D4AAD);
  static const Color _contentColor = Color(0xFF18A8EF);

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
                          'Παιχνίδια',
                          style: TextStyle(
                            color: _contentColor,
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                        SizedBox(height: 12),
                        Icon(
                          Icons.sports_esports_rounded,
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
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    );
  }
}
