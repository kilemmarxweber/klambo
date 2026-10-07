import "dart:async";

bool get platformNetworkIsUp => true;

Stream<bool> get platformNetworkChanges => const Stream<bool>.empty();
