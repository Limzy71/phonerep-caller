import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/phone_record.dart';
import '../theme/app_theme.dart';

class TagChipCard extends StatelessWidget {
  final TagItem tag;
  final Function(String voteType) onVote;

  const TagChipCard({
    super.key,
    required this.tag,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            tag.isSpam ? Icons.warning_amber_rounded : Icons.local_offer_rounded,
            color: tag.isSpam ? AppColors.accentRed : AppColors.accentCyan,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    tag.labelName,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (tag.isSpam) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'SPAM',
                      style: GoogleFonts.outfit(
                        color: AppColors.accentRed,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildVoteButton(
                icon: Icons.thumb_up_alt_rounded,
                count: tag.upvotes,
                color: AppColors.accentGreen,
                onTap: () => onVote('UPVOTE'),
              ),
              const SizedBox(width: 6),
              _buildVoteButton(
                icon: Icons.thumb_down_alt_rounded,
                count: tag.downvotes,
                color: AppColors.accentRed,
                onTap: () => onVote('DOWNVOTE'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoteButton({
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
