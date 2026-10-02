/// Declaration order defines both the 1/2/3 key slots and the panel order.
enum SuggestionRegister {
  // Names remain stable because existing history records persist them.
  formal,
  casual,
  shorter;

  String get label => switch (this) {
    formal => 'Corrected',
    casual => 'Casual',
    shorter => 'Short',
  };
}
