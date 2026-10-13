import 'package:flutter/material.dart';

import 'models.dart';

enum CouponLayout { stack, wide }

double wideCardHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(18) / 18;
  return 148 * (scale < 1 ? 1 : scale);
}

/// A flat, compact strip; square artwork retains its proportions at the right.
class WideCouponCard extends StatelessWidget {
  final Coupon coupon;
  final Widget image;
  final bool selected, favourite;
  final VoidCallback onSelect;
  final VoidCallback? onFavourite, onDetails;
  const WideCouponCard({
    super.key,
    required this.coupon,
    required this.image,
    required this.selected,
    required this.favourite,
    required this.onSelect,
    required this.onFavourite,
    required this.onDetails,
  });

  Widget control(
    String label,
    IconData icon,
    VoidCallback? callback, {
    Color? color,
  }) => Material(
    color: const Color(0xb3ffffff),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: label,
      onPressed: callback,
      icon: Icon(icon, color: color ?? const Color(0xff30382d)),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      height: wideCardHeight(context),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: InkWell(onTap: onSelect, child: image),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xd9000000),
                        Color(0x99000000),
                        Colors.transparent,
                      ],
                      stops: [0, .5, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 76,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coupon.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (coupon.benefit.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        coupon.benefit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 12,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  control(
                    favourite ? 'Remove favourite' : 'Favourite coupon',
                    favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                    onFavourite,
                    color: favourite ? const Color(0xffffdf00) : null,
                  ),
                  const SizedBox(height: 8),
                  control(
                    'Offer details',
                    Icons.info_outline_rounded,
                    onDetails,
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xffb6f52a)
                          : favourite
                          ? const Color(0xffffd43b)
                          : Colors.transparent,
                      width: selected ? 4 : 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
