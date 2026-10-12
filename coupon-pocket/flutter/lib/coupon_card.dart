import 'package:flutter/material.dart';

import 'models.dart';

class CouponCard extends StatelessWidget {
  final Coupon coupon;
  final String locale;
  final Widget image;
  final bool favourite, selected, showFavourite;
  final VoidCallback? onFavourite, onDetails, onSelect;
  const CouponCard({
    super.key,
    required this.coupon,
    required this.locale,
    required this.image,
    this.favourite = false,
    this.selected = false,
    this.showFavourite = true,
    this.onFavourite,
    this.onDetails,
    this.onSelect,
  });

  Widget control({
    required String label,
    required IconData icon,
    required VoidCallback? action,
    Color background = Colors.white,
    Color foreground = const Color(0xff30382d),
  }) => Material(
    color: background,
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: label,
      onPressed: action,
      icon: Icon(icon, color: foreground),
    ),
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
    child: Material(
      color: const Color(0xffedf0e9),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 1,
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
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xe0000000),
                      ],
                      stops: [0, .42, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showFavourite) ...[
                    control(
                      label: favourite
                          ? 'Remove favourite'
                          : 'Favourite coupon',
                      icon: favourite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      action: onFavourite,
                      background: Colors.white,
                      foreground: favourite
                          ? const Color(0xffffdf00)
                          : const Color(0xff42483d),
                    ),
                    const SizedBox(height: 8),
                  ],
                  control(
                    label: 'Offer details',
                    icon: Icons.info_outline_rounded,
                    action: onDetails,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 18,
              right: 14,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onSelect,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            coupon.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (coupon.benefit.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                coupon.benefit,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selected || favourite)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: selected
                            ? const Color(0xffb6f52a)
                            : const Color(0xffffd43b),
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
