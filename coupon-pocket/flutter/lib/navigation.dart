import 'package:flutter/material.dart';

class PocketNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  const PocketNavigation({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Semantics(
              selected: selected == i,
              button: true,
              child: Material(
                color: selected == i
                    ? const Color(0xff171713)
                    : const Color(0xfff3f0e8),
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(width: 2, color: Color(0xff171713)),
                        right: BorderSide(width: 1, color: Color(0xff171713)),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ['Coupons', 'Activated', 'Checkout'][i],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: selected == i
                                ? Colors.white
                                : const Color(0xff171713),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
