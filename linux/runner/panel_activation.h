#ifndef RUNNER_PANEL_ACTIVATION_H_
#define RUNNER_PANEL_ACTIVATION_H_

#include <flutter_linux/flutter_linux.h>

// Registration constructs no window and leaves the existing toplevel hidden.
void register_panel_activation(FlView* view);

#endif  // RUNNER_PANEL_ACTIVATION_H_
