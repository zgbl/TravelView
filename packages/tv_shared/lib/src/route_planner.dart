import 'package:tv_core/tv_core.dart';

import 'app_settings.dart';

/// 按设置挑路线服务。
///
/// **两端共用这一个函数。** 桌面和手机读的是同一份 [AppSettings]，
/// 要是各自 switch 一遍，迟早会出现"桌面能算出道路、手机只有直线"
/// 这种没人发现的差异 —— 而这正是手机端发布出去的 story 一直没有线的原因。
///
/// 默认走 openrouteservice（注册即有免费额度，起步最快）；
/// 没填 key 时 [RoutePlanner] 会自动退成直线，不会让发布失败。
RouteProvider routeProviderFrom(AppSettings settings) {
  switch (settings.routeProvider) {
    case 'osrm':
      return OsrmRouteProvider(baseUrl: settings.osrmBaseUrl);
    case 'direct':
      return const DirectRouteProvider();
    default:
      return OrsRouteProvider(apiKey: settings.orsApiKey);
  }
}

/// 导出 / 发布前把每一段路补齐。**Story 里绝不能没有线。**
///
/// 地图是这个产品的核心画面，发出去只有几个孤零零的点是不能接受的。
/// 保证由 [RoutePlanner] 兜底，这里只负责"挑服务 + 挂缓存":
///
///   - 飞行段永不贴合道路，直接画直线
///   - 单段失败退回直线，**任何情况下都返回和 `trip.legs` 等长的结果**
///   - 连续失败到一定次数就不再打网络请求（没配 key 时不必把 21 段试一遍）
///
/// 也就是说这个函数不抛异常、不返回空 —— 调用方不需要为它写 try/catch，
/// 最坏的结果是画得朴素一点。
Future<List<RouteLeg>> planStoryLegs(
  TripRoute trip,
  AppSettings settings, {
  RouteCache? cache,
  void Function(int done, int total)? onProgress,
}) {
  return RoutePlanner(
    provider: routeProviderFrom(settings),
    cache: cache,
  ).planTrip(trip, onProgress: onProgress);
}
