import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../controllers/request_wizard_controller.dart';

/// Wizard navigation, kept out of the pages so all five steps behave the same.
///
/// Forward moves use `push` rather than `go` so the hardware back button walks
/// the steps backwards the way a five-part form should, and so the request list
/// underneath keeps its scroll position and loaded pages.
void wizardGoNext(
  BuildContext context,
  RequestWizardController controller,
  RequestWizardStep step,
) {
  controller.goToStep(step);
  context.pushNamed(RequestWizardController.routeFor(step));
}

/// Steps backwards. From the first step there is nothing to pop, so it leaves
/// the wizard entirely rather than silently doing nothing.
void wizardGoBack(
  BuildContext context,
  RequestWizardController controller,
  RequestWizardStep step,
) {
  controller.goToStep(step);
  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.goNamed(AppRoute.requestNew.name);
  }
}
