class Reply {
  final int status;
  final String body;
  Reply(this.status, this.body);
  bool get ok => status >= 200 && status < 300;
}

typedef Send = Future<Reply> Function(
  String method,
  Uri url,
  Map<String, String> headers,
  String? body,
  String? contentType,
);
void allow(Uri u) {
  if (u.scheme != 'https' ||
      u.userInfo.isNotEmpty ||
      u.port != 443 ||
      u.hasFragment ||
      !(u.host == 'accounts.lidl.com' ||
          u.host == 'coupons.lidlplus.com' ||
          (u.host == 'profile.lidlplus.com' &&
              !u.hasQuery &&
              RegExp(r'^/api/v1/[A-Z]{2}/loyalty$').hasMatch(u.path)))) {
    throw const FormatException(
      'Connection outside account services was blocked.',
    );
  }
}
