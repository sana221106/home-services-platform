import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_style.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/localization/app_localizations.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/models/home_models.dart';
import '../controllers/home_controller.dart';

/// Customer home: greeting counts, quick services, in-flight requests and
/// unread badges. Every value comes from the server so lifecycle wording can
/// never drift from the backend state machine.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => ref.read(homeProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final HomeState state = ref.watch(homeProvider);
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    final name = ref.watch(authProvider).customer?.firstName ?? '';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(homeProvider.notifier).load(silent: true),
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    AppSpacing.md,
                    AppSpacing.screenHorizontal,
                    0,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.homeGreeting(name),
                          style: context.text.heading,
                        ),
                      ),
                      _NotificationBell(
                        count: state.dashboard?.unreadTotal ?? 0,
                      ),
                    ],
                  ),
                ),
              ),
              if (state.status == HomeStatus.loading && state.dashboard == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.isFatalError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    message: state.errorMessage ?? l10n.errorGeneric,
                    onRetry: () => ref.read(homeProvider.notifier).load(),
                  ),
                )
              else if (state.dashboard != null)
                _HomeContent(dashboard: state.dashboard!)
              else
                const SliverFillRemaining(hasScrollBody: false),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(AppRoute.requestNew.name),
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        icon: const AppIcon('assets/icons/wrench.svg', size: 20),
        label: Text(l10n.requestsNew),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.dashboard});

  final HomeDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.md,
        AppSpacing.screenHorizontal,
        96,
      ),
      sliver: SliverList.list(
        children: <Widget>[
          _CountsRow(counts: dashboard.greeting),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.homeQuickActions, style: context.text.title),
          const SizedBox(height: AppSpacing.md),
          _CategoryGrid(categories: dashboard.categories),
          if (dashboard.activeRequests.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.homeActiveRequestTitle, style: context.text.title),
            const SizedBox(height: AppSpacing.md),
            for (final request in dashboard.activeRequests)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ActiveRequestCard(request: request),
              ),
          ] else ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _EmptyActiveRequest(),
          ],
        ],
      ),
    );
  }
}

class _CountsRow extends StatelessWidget {
  const _CountsRow({required this.counts});

  final GreetingCounts counts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: <Widget>[
        Expanded(
          child: _CountTile(
            value: counts.activeRequests,
            label: l10n.requestsActive,
            icon: 'assets/icons/orders.svg',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _CountTile(
            value: counts.openQuotes,
            label: l10n.requestQuoteTitle,
            icon: 'assets/icons/card.svg',
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _CountTile(
            value: counts.awaitingPayment,
            label: l10n.paymentsTitle,
            icon: 'assets/icons/wallet.svg',
          ),
        ),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.value,
    required this.label,
    required this.icon,
  });

  final int value;
  final String label;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: <Widget>[
          AppIcon(icon, size: 20, color: colors.primary),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$value',
            style: context.text.display.copyWith(color: colors.primary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories});

  final List<ServiceCategorySummary> categories;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    if (categories.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (BuildContext context, int index) {
        final category = categories[index];
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => context.pushNamed(
            AppRoute.requestNew.name,
            queryParameters: <String, String>{'category': category.id},
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: AppIcon(
                  _iconAssetFor(category.iconKey),
                  size: 26,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                category.nameAr,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: context.text.label,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Maps a catalogue icon key to a bundled asset. Unknown keys fall back to a
  /// generic wrench so a new backend key can never produce a broken tile.
  static String _iconAssetFor(String key) {
    const Map<String, String> map = <String, String>{
      'faucet': 'assets/icons/faucet.svg',
      'plumbing': 'assets/icons/faucet.svg',
      'bolt': 'assets/icons/bolt.svg',
      'electrical': 'assets/icons/bolt.svg',
      'paint': 'assets/icons/paint.svg',
      'painting': 'assets/icons/paint.svg',
      'appliance': 'assets/icons/wrench.svg',
      'carpentry': 'assets/icons/wrench.svg',
      'cleaning': 'assets/icons/photoedit.svg',
      'pest': 'assets/icons/photoedit.svg',
      'ac': 'assets/icons/wrench.svg',
    };
    return map[key] ?? 'assets/icons/wrench.svg';
  }
}

class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({required this.request});

  final ActiveRequestSummary request;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.pushNamed(
          AppRoute.requestDetail.name,
          pathParameters: <String, String>{'requestId': request.requestId},
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      request.categoryNameAr,
                      style: context.text.labelStrong,
                    ),
                  ),
                  Text(
                    request.referenceCode,
                    textDirection: TextDirection.ltr,
                    style: context.text.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                request.nextStepAr,
                style: context.text.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.commonSeeDetails,
                style: context.text.label.copyWith(color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyActiveRequest extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: <Widget>[
          AppIcon('assets/icons/check.svg', size: 30, color: colors.success),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.homeNoActiveRequest, style: context.text.body),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AppIcon('assets/icons/bell.svg', size: 24, color: colors.textPrimary),
        if (count > 0)
          PositionedDirectional(
            end: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colors.danger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: context.text.label.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AppIcon('assets/icons/alert.svg', size: 34, color: colors.danger),
          const SizedBox(height: AppSpacing.md),
          Text(message, textAlign: TextAlign.center, style: context.text.body),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}
