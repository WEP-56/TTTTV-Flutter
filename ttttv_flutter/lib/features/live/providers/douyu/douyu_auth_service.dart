import '../../data/storage/live_cookie_store.dart';

class DouyuAuthService {
  DouyuAuthService({
    required LiveCookieStore cookieStore,
  }) : _cookieStore = cookieStore;

  final LiveCookieStore _cookieStore;

  Future<String> getCookie() {
    return _cookieStore.getCookie('douyu');
  }

  Future<void> saveCookie(String cookie) {
    return _cookieStore.saveCookie('douyu', cookie);
  }

  Future<void> clearCookie() {
    return _cookieStore.clearCookie('douyu');
  }

  Future<bool> hasCookie() async {
    return (await getCookie()).trim().isNotEmpty;
  }
}
