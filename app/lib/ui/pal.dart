import 'package:flutter/material.dart';

/// iTunes 12 colours, in a light and a dark variant so text always sits on a
/// background it can be read against.
class Pal {
  const Pal({
    required this.bg,
    required this.toolbarTop,
    required this.toolbarBottom,
    required this.sidebar,
    required this.selected,
    required this.stripe,
    required this.rule,
    required this.text,
    required this.muted,
    required this.lcd,
    required this.field,
    required this.header,
  });

  final Color bg,
      toolbarTop,
      toolbarBottom,
      sidebar,
      selected,
      stripe,
      rule,
      text,
      muted,
      lcd,
      field,
      header;

  static const light = Pal(
    bg: Colors.white,
    toolbarTop: Color(0xFFF3F3F3),
    toolbarBottom: Color(0xFFD9D9D9),
    sidebar: Color(0xFFF0F0F2),
    selected: Color(0xFF3D80DF),
    stripe: Color(0xFFF3F6FA),
    rule: Color(0xFFBDBDBD),
    text: Color(0xDD000000),
    muted: Color(0xFF666666),
    lcd: Color(0xFFEFEFEF),
    field: Colors.white,
    header: Color(0xFFF7F7F7),
  );

  static const dark = Pal(
    bg: Color(0xFF1C1C1E),
    toolbarTop: Color(0xFF3A3A3C),
    toolbarBottom: Color(0xFF2C2C2E),
    sidebar: Color(0xFF232426),
    selected: Color(0xFF3D80DF),
    stripe: Color(0xFF242426),
    rule: Color(0xFF48484A),
    text: Color(0xDEFFFFFF),
    muted: Color(0xFFA0A0A5),
    lcd: Color(0xFF1F1F21),
    field: Color(0xFF2C2C2E),
    header: Color(0xFF2A2A2C),
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
