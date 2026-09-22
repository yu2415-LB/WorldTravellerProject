import 'dart:collection';

import 'package:flutter/material.dart';

typedef TagEntry = DropdownMenuEntry<Tag>;

enum Tag {
  landscape("landscape"),
  technology("technology"),
  portrait("portrait"),
  art("art"),
  nature("nature"),
  travel("travel"),
  animals("animals"),
  culture("culture"),
  food("food"),
  fashion("fashion"),
  sports("sports"),
  music("music"),
  vehicles("vehicles"),
  architecture("architecture"),
  people("people");

  const Tag(this.name);
  final String name;

  static final List<TagEntry> entries = UnmodifiableListView<TagEntry>(values.map<TagEntry>(
    (Tag tag) => TagEntry(
      value: tag,
      label: tag.name,
    )
  ));
}