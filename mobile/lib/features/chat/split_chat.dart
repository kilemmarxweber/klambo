import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

/// Tablette (portrait ou paysage) ou téléphone tourné en paysage.
bool useSplitConversationLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.shortestSide >= 600) return true;
  return MediaQuery.orientationOf(context) == Orientation.landscape;
}

/// Largeur de la liste : le fil occupe le centre et la droite, donc plus large.
double conversationListPaneWidth(double totalWidth) {
  final preferred = totalWidth * 0.32;
  final maxList = math.min(360.0, totalWidth * 0.38);
  final minList = math.min(220.0, maxList);
  return preferred.clamp(minList, maxList);
}

/// Conversation affichée dans le panneau de droite en vue partagée.
class SplitChatTarget {
  const SplitChatTarget({
    required this.organizationId,
    required this.conversationId,
    required this.title,
    this.peerUserId,
    this.peerImage,
    this.memberImages = const [],
    this.peerTelephone,
    this.peerPrenom,
    this.peerRoleLabel,
    this.peerBranches = const [],
    this.noReply = false,
    this.conversationType,
    this.myRole,
    this.repliesLocked = false,
  });

  final String organizationId;
  final String conversationId;
  final String title;
  final String? peerUserId;
  final String? peerImage;
  final List<String> memberImages;
  final String? peerTelephone;
  final String? peerPrenom;
  final String? peerRoleLabel;
  final List<String> peerBranches;
  final bool noReply;
  final String? conversationType;
  final String? myRole;
  final bool repliesLocked;
}

final splitChatProvider = StateProvider<SplitChatTarget?>((ref) => null);
