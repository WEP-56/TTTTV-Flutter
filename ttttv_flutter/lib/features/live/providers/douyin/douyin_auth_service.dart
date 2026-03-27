import '../../data/storage/live_cookie_store.dart';

class DouyinAuthService {
  DouyinAuthService({
    required LiveCookieStore cookieStore,
  }) : _cookieStore = cookieStore;

  final LiveCookieStore _cookieStore;

  Future<String> getCookie() {
    return _cookieStore.getCookie('douyin');
  }

  Future<void> saveCookie(String cookie) {
    return _cookieStore.saveCookie('douyin', cookie);
  }

  Future<void> clearCookie() {
    return _cookieStore.clearCookie('douyin');
  }

  Future<bool> hasCookie() async {
    return (await getCookie()).trim().isNotEmpty;
  }
}
