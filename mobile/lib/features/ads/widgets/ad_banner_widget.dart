import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/features/ads/services/ad_service.dart';

class SafeAdBannerWidget extends StatefulWidget {
  final String screenName;
  final bool isLiveRacing;

  const SafeAdBannerWidget({
    super.key,
    required this.screenName,
    this.isLiveRacing = false,
  });

  @override
  State<SafeAdBannerWidget> createState() => _SafeAdBannerWidgetState();
}

class _SafeAdBannerWidgetState extends State<SafeAdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoadAd();
  }

  void _checkAndLoadAd() {
    // Check strict safety policy: Never show during active race!
    if (!AdService.canShowAd(
      screenName: widget.screenName,
      isLiveRacing: widget.isLiveRacing,
    )) {
      return;
    }

    final adUnitId = AdService.bannerAdUnitId;
    if (adUnitId.isEmpty) return;

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!_isDisposed) {
            setState(() {
              _isAdLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!_isDisposed) {
            setState(() {
              _bannerAd = null;
              _isAdLoaded = false;
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.canShowAd(
      screenName: widget.screenName,
      isLiveRacing: widget.isLiveRacing,
    )) {
      return const SizedBox.shrink();
    }

    if (!_isAdLoaded || _bannerAd == null) {
      // Reserved clean container space with subtle border
      return Container(
        height: 50,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Sponsored Partner Space',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      );
    }

    return Container(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
