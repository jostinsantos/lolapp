class Addon {
  final String id;
  final String name;
  final String version;
  final bool enabled;
  const Addon({required this.id, required this.name, required this.version, this.enabled = true});
}
