class MigrationVersion {
  final int major;
  final int minor;
  final int patch;
  final int code;

  const MigrationVersion(this.major, this.minor, this.patch)
      : code = major * 10000 + minor * 100 + patch;

  String get label => 'v$major.$minor.$patch';

  @override
  String toString() => label;
}
