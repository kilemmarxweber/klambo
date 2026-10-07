import "dart:async";
import "dart:js_interop";

import "package:web/web.dart" as web;

bool get platformNetworkIsUp => web.window.navigator.onLine;

Stream<bool> get platformNetworkChanges => Stream<bool>.multi((controller) {
      final online = ((web.Event _) => controller.add(true)).toJS;
      final offline = ((web.Event _) => controller.add(false)).toJS;
      web.window.addEventListener("online", online);
      web.window.addEventListener("offline", offline);
      controller.onCancel = () {
        web.window.removeEventListener("online", online);
        web.window.removeEventListener("offline", offline);
      };
    });
