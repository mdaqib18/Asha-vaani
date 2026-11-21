import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Calm-clinical warm page scaffold enforcing uniform margins and navigation chrome.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.bottomNavigationBar,
    this.banner,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenHorizontal,
    ),
    this.resizeToAvoidBottomInset = true,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? banner;
  final Widget body;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hasAppBar =
        title != null || titleWidget != null || actions != null || leading != null;

    return Scaffold(
      backgroundColor: tokens.surface,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: hasAppBar
          ? AppBar(
              backgroundColor: tokens.surface,
              foregroundColor: tokens.ink,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: leading,
              title: titleWidget ??
                  (title != null
                      ? Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null),
              actions: actions,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(AppSizes.borderWidth),
                child: Divider(
                  height: AppSizes.borderWidth,
                  thickness: AppSizes.borderWidth,
                  color: tokens.outline,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (banner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  AppSpacing.md,
                  AppSpacing.screenHorizontal,
                  0,
                ),
                child: banner!,
              ),
            Expanded(
              child: Padding(padding: padding, child: body),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottomNavigationBar != null
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border(
                  top: BorderSide(
                    color: tokens.outline,
                    width: AppSizes.borderWidth,
                  ),
                ),
              ),
              child: bottomNavigationBar!,
            )
          : null,
    );
  }
}
