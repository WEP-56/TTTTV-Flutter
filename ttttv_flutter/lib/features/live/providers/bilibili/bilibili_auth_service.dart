import '../../data/storage/live_cookie_store.dart';

class BilibiliAuthService {
  BilibiliAuthService({
    required LiveCookieStore cookieStore,
  }) : _cookieStore = cookieStore;

  final LiveCookieStore _cookieStore;

  Future<String> getCookie() {
    return _cookieStore.getCookie('bilibili');
  }

  Future<void> saveCookie(String cookie) {
    return _cookieStore.saveCookie('bilibili', cookie);
  }

  Future<void> clearCookie() {
    return _cookieStore.clearCookie('bilibili');
  }

  Future<bool> hasCookie() async {
    return (await getCookie()).trim().isNotEmpty;
  }

  Future<int> getUserId() async {
    final cookie = await getCookie();
    final match = RegExp(r'DedeUserID=([^;]+)').firstMatch(cookie);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}
