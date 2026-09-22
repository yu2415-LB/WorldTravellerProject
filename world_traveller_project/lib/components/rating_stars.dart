import 'package:flutter/material.dart';

class RatingStars extends StatelessWidget {
  final double rating;
  final ValueChanged<double> onRatingChanged;
  final double starWidth;
  final double starHeight;
  final double starSpacing;

  const RatingStars({
    super.key,
    required this.rating,
    required this.onRatingChanged,
    required this.starWidth,
    required this.starHeight,
    required this.starSpacing
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(10, (index) {
        final starNumber = index + 1;

        IconData icon;

        if (rating >= starNumber) {
          icon = Icons.star;
        } else if (rating >= starNumber - 0.5) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }

        return
        Padding(
          padding: EdgeInsetsGeometry.only(right: index < 9 ? starSpacing : 0),
          child: GestureDetector(
            onTapUp: (details) {
              final isLeftHalf = details.localPosition.dx < starWidth / 2;

              if (rating == 0.5 && isLeftHalf && starNumber == 1) {
                onRatingChanged(0.0);
                return;
              }

              final newRating = isLeftHalf
                  ? starNumber - 0.5
                  : starNumber.toDouble();

              onRatingChanged(newRating);
            },
            child: SizedBox(
              width: starWidth,
              height: starHeight,
              child: Icon(
                icon,
                color: Colors.amber,
                size: starHeight,
              ),
            ),
          )
        );
      }),
    );
  }
}