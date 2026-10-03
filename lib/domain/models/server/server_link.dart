class ServerLink {
  final String url;
  final String serverId;
  final String? type; // hls | mp4 | embed
  const ServerLink({required this.url, required this.serverId, this.type});
}
