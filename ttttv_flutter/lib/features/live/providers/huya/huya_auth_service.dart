import '../../data/storage/live_cookie_store.dart';

class HuyaAuthService {
  HuyaAuthService({
    required LiveCookieStore cookieStore,
  }) : _cookieStore = cookieStore;

  final LiveCookieStore _cookieStore;

  Future<String> getCookie() {
    return _cookieStore.getCookie('huya');
  }

  Future<void> saveCookie(String cookie) {
    return _cookieStore.saveCookie('huya', cookie);
  }

  Future<void> clearCookie() {
    return _cookieStore.clearCookie('huya');
  }

  Future<bool> hasCookie() async {
    return (await getCookie()).trim().isNotEmpty;
  }
}
