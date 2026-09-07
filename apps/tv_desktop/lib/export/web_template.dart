import 'dart:convert';

import 'package:tv_core/tv_core.dart';

/// 生成 Story 网页。
///
/// 单文件、无构建步骤、双击就能看。地图用 Leaflet + OSM 栅格瓦片
/// （**仅用于本地预览**；正式发布要换成自托管的 Protomaps，见 map-tiles.md）。
///
/// 关键效果:
///   - 滚动驱动: 滚到哪一天，小车就开到哪一天
///   - 走过的路线逐渐画出来，未走的淡着
///   - 车头跟着道路方向转
/// [coverMode] 片头用什么: 'map' 路线图（默认）/ 'photo' 一张照片。
/// **必须显式传进来** —— Story.toJson() 里没有这个字段，
/// 它是导出时的展示选项，不属于行程数据本身。
String buildStoryHtml(Story story, {String coverMode = 'map'}) {
  final json = story.toJson();
  json['coverMode'] = coverMode == 'photo' ? 'photo' : 'map';
  final data = const JsonEncoder().convert(json);
  return _template.replaceFirst('__STORY_JSON__', data);
}

const _template = r'''<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TravelView Story</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>
  :root{
    --bg:#0f1113; --fg:#f2f0ec; --muted:#9aa0a6;
    --accent:#4fbfa8; --card:#191c1f;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--fg);
    font:16px/1.6 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif}
  a{color:var(--accent)}

  .hero{position:relative;height:88vh;display:flex;align-items:flex-end;
    overflow:hidden}
  .hero img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;
    filter:brightness(.62)}
  /* 片头的真地图。**底图一点都不压暗** —— 只有下方一条渐变托住标题 */
  .hero .heromap{position:absolute;inset:0}
  /* 暗角: 摄影里把视线收进画面中心的手法。压的是四角，不是整张图 */
  .vignette{position:absolute;inset:0;pointer-events:none;
    background:radial-gradient(120% 85% at 50% 42%,rgba(0,0,0,0) 55%,
      rgba(12,14,16,.55) 100%)}
  .hero, .cardhero .mapwrap{user-select:none}
  .hero .scrim{position:absolute;left:0;right:0;bottom:0;height:58%;
    background:linear-gradient(to top,#0f1113 0%,rgba(15,17,19,.75) 45%,
      rgba(15,17,19,0) 100%);pointer-events:none}
  .hero .inner{text-shadow:0 2px 18px rgba(0,0,0,.55)}
  .hero .stats{display:inline-flex;gap:26px;flex-wrap:wrap;
    background:rgba(0,0,0,.25);padding:14px 22px;border-radius:16px;
    backdrop-filter:blur(4px)}
  /* 方案 B: 标题在地图外面，地图是一张干净的卡片 */
  .cardhero{padding:9vh 6vw 6vh}
  .cardhero h1{font-size:clamp(34px,6vw,68px);line-height:1.1;margin:0 0 14px;
    letter-spacing:-.02em}
  .cardhero .sub{color:#8a9196;font-size:clamp(14px,2vw,19px)}
  .cardhero .stats{margin-top:22px;display:flex;gap:26px;flex-wrap:wrap}
  .cardhero .stats .n{font-size:26px;font-weight:600;display:block}
  .cardhero .stats .k{font-size:12px;color:#8a9196;letter-spacing:.08em;
    display:block}
  .cardhero .mapwrap{position:relative;height:62vh;margin-top:30px;
    border-radius:24px;overflow:hidden}
  .cardhero .mapwrap .edge{position:absolute;inset:0;border-radius:24px;
    box-shadow:inset 0 0 90px rgba(15,17,19,.55);pointer-events:none}
  .hero .inner{position:relative;padding:0 6vw 8vh;max-width:900px}
  .hero h1{font-size:clamp(34px,6vw,68px);line-height:1.1;margin:0 0 14px;
    letter-spacing:-.02em}
  .hero .sub{color:#e6e3dd;font-size:clamp(14px,2vw,19px)}
  .hero .stats{margin-top:22px;display:flex;gap:26px;flex-wrap:wrap}
  .hero .stats div span{display:block}
  .hero .stats .n{font-size:26px;font-weight:600}
  .hero .stats .k{font-size:12px;color:#cfcbc4;letter-spacing:.08em}

  .layout{display:grid;grid-template-columns:minmax(0,1fr) 46vw;gap:0;
    align-items:start}
  @media (max-width:900px){.layout{grid-template-columns:1fr}}

  .content{padding:6vh 5vw 12vh;max-width:760px}
  .day{margin:0 0 10vh}
  .day h2{font-size:13px;letter-spacing:.16em;color:var(--muted);
    text-transform:uppercase;margin:0 0 6px}
  .stop{margin:0 0 7vh;scroll-margin-top:20vh}
  .stop h3{font-size:clamp(22px,3vw,32px);margin:0 0 4px;letter-spacing:-.01em}
  .stop .meta{color:var(--muted);font-size:13px;margin-bottom:12px}
  .stop .note{max-width:62ch;font-size:15px;line-height:1.75;
    color:#dcd8d1;margin:0 0 18px}
  .hero-shot img{width:100%;border-radius:14px;display:block}
  .grid{display:grid;gap:10px;margin-top:10px;
    grid-template-columns:repeat(auto-fill,minmax(180px,1fr))}
  .grid img{width:100%;border-radius:10px;display:block;
    aspect-ratio:1/1;object-fit:cover;cursor:zoom-in}
  .grid img.portrait{aspect-ratio:3/4}
  /* 和地图互相指认时的高亮 */
  .hero-shot img, .grid img{outline:0 solid var(--accent);
    transition:outline-width .12s ease}
  .hero-shot img.located, .grid img.located{outline-width:3px}
  .stop.current h3{color:var(--accent)}

  .routemap{padding:8vh 6vw 4vh}
  .routemap h2{font-size:clamp(22px,3vw,32px);margin:0 0 6px;
    letter-spacing:-.01em}
  .rm-sub{color:var(--muted);font-size:13px;margin-bottom:22px}
  #omap{width:100%;height:min(70vh,680px);border-radius:16px;
    background:#0c0e10;border:1px solid #23282c}
  .pin{display:flex;align-items:center;justify-content:center;
    width:26px;height:26px;border-radius:50%;background:var(--accent);
    color:#08211d;font:600 12px/1 -apple-system,sans-serif;
    border:2px solid #0f1113;box-shadow:0 2px 6px rgba(0,0,0,.5)}

  #mapwrap{position:sticky;top:0;height:100vh}
  #map{width:100%;height:100%;background:#0c0e10}
  .leaflet-container{background:#0c0e10}
  #mapwrap{position:relative}
  .pinsize{position:absolute;left:12px;bottom:12px;z-index:500;
    display:flex;align-items:center;gap:4px;padding:4px 8px;border-radius:999px;
    background:rgba(15,17,19,.8);backdrop-filter:blur(6px);
    color:#8a9196;font-size:12px}
  .pinsize button{width:22px;height:22px;border:0;border-radius:999px;
    background:transparent;color:#faf8f5;cursor:pointer;font-size:14px}
  .pinsize button:hover{background:rgba(255,255,255,.12)}
  .pinsize i{display:inline-block;width:10px;height:10px;border-radius:999px;
    background:#ff8a5b;border:2px solid #fff}
  @media (max-width:900px){#mapwrap{height:52vh;top:0}}

  .car{font-size:26px;line-height:1;filter:drop-shadow(0 2px 4px rgba(0,0,0,.6))}

  .summary{padding:14vh 6vw;text-align:center;background:var(--card)}
  .summary .card{display:inline-block;padding:48px 56px;border-radius:22px;
    background:linear-gradient(150deg,#1d2226,#12161a);
    border:1px solid #2a3034}
  .summary h2{font-size:clamp(26px,4vw,40px);margin:0 0 8px}
  .summary .dates{color:var(--muted);margin-bottom:34px}
  .summary .nums{display:flex;gap:40px;justify-content:center;flex-wrap:wrap}
  .summary .nums .n{font-size:40px;font-weight:600;line-height:1}
  .summary .nums .k{font-size:12px;color:var(--muted);letter-spacing:.1em;
    margin-top:6px}
  footer{padding:40px;text-align:center;color:var(--muted);font-size:12px}

  .lightbox{position:fixed;inset:0;background:rgba(0,0,0,.94);display:none;
    align-items:center;justify-content:center;z-index:9999;cursor:zoom-out}
  .lightbox img{max-width:94vw;max-height:94vh;border-radius:6px}
  .lightbox.on{display:flex}
  .lb-nav{position:absolute;top:50%;transform:translateY(-50%);
    background:rgba(255,255,255,.08);color:#fff;border:0;border-radius:50%;
    width:52px;height:52px;font-size:30px;line-height:1;cursor:pointer}
  .lb-nav:hover{background:rgba(255,255,255,.18)}
  .lb-nav[data-d="-1"]{left:2vw}
  .lb-nav[data-d="1"]{right:2vw}
  .lightbox .count{position:absolute;bottom:3vh;left:0;right:0;text-align:center;
    color:#9aa0a6;font-size:13px;letter-spacing:.08em}
</style>
</head>
<body>
<div id="app"></div>
<div class="lightbox" id="lb">
  <button class="lb-nav" data-d="-1" aria-label="上一张">&#8249;</button>
  <img alt="">
  <button class="lb-nav" data-d="1" aria-label="下一张">&#8250;</button>
  <div class="count"></div>
</div>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
const STORY = __STORY_JSON__;
// 导出包是自包含的，但瓦片只能联网取。离线打开时地图是空的，
// 照片和文字照常能看 —— 这是刻意的取舍
const TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/* ---------- polyline6 解码：和 Dart 端是同一套算法 ---------- */
function decodePolyline(str, precision){
  const factor = Math.pow(10, precision || 6);
  let index=0, lat=0, lng=0; const out=[];
  while(index < str.length){
    let b, shift=0, result=0;
    do { b = str.charCodeAt(index++)-63; result |= (b & 0x1f) << shift; shift += 5; }
    while (b >= 0x20);
    lat += (result & 1) ? ~(result >> 1) : (result >> 1);
    shift=0; result=0;
    do { b = str.charCodeAt(index++)-63; result |= (b & 0x1f) << shift; shift += 5; }
    while (b >= 0x20);
    lng += (result & 1) ? ~(result >> 1) : (result >> 1);
    out.push([lat/factor, lng/factor]);
  }
  return out;
}

const photoById = {};
STORY.photos.forEach(p => photoById[p.id] = p);
const stopById = {};
STORY.stops.forEach(s => stopById[s.id] = s);

function fmtDate(iso){
  const d = new Date(iso);
  return d.toLocaleDateString('zh-CN', {month:'long', day:'numeric'});
}
function fmtTime(iso){
  const d = new Date(iso);
  return d.toTimeString().slice(0,5);
}

/* ---------- Story Cover: 这本作品的封面画布 ----------
   **地图在这里不是一个 UI 组件，是封面画。**
   所以: 没有控件、不能交互、没有角标，路线是画上去的笔触而不是数据图层。
   底图一点都不压暗: 要让标题读得清，就去处理标题（下方一条局部渐变
   + 文字阴影），而不是把整张地图糊掉 —— 那样地图就不成其为地图了。
   路线两层画: 深色粗描边打底 + 亮青细线在上，
   任何底图（浅色街道、地形、卫星）上都跳得出来。 */
let heroMap = null;

function initStoryCover(elId, bottomPad){
  const el = document.getElementById(elId);
  if (!el || !window.L) return;
  heroMap = L.map(elId, {
    zoomControl:false, attributionControl:false,
    dragging:false, scrollWheelZoom:false, doubleClickZoom:false,
    boxZoom:false, keyboard:false, touchZoom:false, tap:false,
  });
  L.tileLayer(TILE_URL, {maxZoom:19}).addTo(heroMap);

  const all = [];
  (STORY.routes||[]).forEach(r => {
    const pts = decodePolyline(r.geometry, r.precision || 6);
    if (pts.length < 2) return;
    all.push.apply(all, pts);
    L.polyline(pts, {color:'#0f1113', weight:9, opacity:.55,
      lineCap:'round', lineJoin:'round'}).addTo(heroMap);
    L.polyline(pts, {color:'#4fbfa8', weight:4,
      lineCap:'round', lineJoin:'round'}).addTo(heroMap);
  });
  (STORY.stops||[]).forEach(st => {
    L.circleMarker([st.lat, st.lon], {radius:4, color:'#0f1113', weight:2,
      fillColor:'#ffffff', fillOpacity:1}).addTo(heroMap);
    all.push([st.lat, st.lon]);
  });

  if (all.length) {
    // 底部多留出标题的高度，路线自然被推到上半屏，不被字压住
    heroMap.fitBounds(L.latLngBounds(all),
      {paddingTopLeft:[40, 40], paddingBottomRight:[40, bottomPad || 40]});
  }
  setTimeout(() => heroMap && heroMap.invalidateSize(), 60);
}

/* ---------- 渲染 ---------- */
function render(){
  const cover = photoById[STORY.cover];
  const st = STORY.stats;
  const miles = Math.round(st.distanceMeters / 1609.344);

  let html = '';
  /* Story Cover 的形态。默认由**内容**决定: 有路线就地图封面，
     没有就照片封面 —— 以后生日 / 婚礼 / 演唱会没有路线，
     封面引擎该自己退回照片，而不是画一张空地图。 */
  const hasRoute = (STORY.routes||[]).length > 0
                || (STORY.stops||[]).length > 1;
  const mode = STORY.coverMode === 'photo' ? 'photo'
             : !hasRoute ? 'photo'
             : STORY.coverMode === 'mapcard' ? 'mapcard' : 'map';
  // 封面已经是地图了，下面就不该再来一张大地图
  const showOverview = (mode === 'photo');

  if (mode === 'mapcard') {
    // 方案 B: 标题在地图外面，地图是一张干净的卡片 —— 地图一个像素没被遮
    html += '<section class="cardhero"><h1>'+esc(STORY.title)+'</h1>';
    if (STORY.subtitle) html += '<div class="sub">'+esc(STORY.subtitle)+'</div>';
    html += '<div class="stats">'
         + stat(st.days,'DAYS') + stat(st.stops,'STOPS')
         + stat(miles,'MILES') + stat(st.photos,'PHOTOS')
         + '</div>'
         + '<div class="mapwrap"><div id="heromap" style="height:100%"></div>'
         + '<div class="vignette"></div><div class="edge"></div>'
         + '</div></section>';
  } else {
    html += '<section class="hero">';
    if (mode === 'map') {
      html += '<div class="heromap" id="heromap"></div>'
           + '<div class="vignette"></div><div class="scrim"></div>';
    } else if (cover) {
      html += '<img src="'+cover.web.path+'" alt="">';
    }
  html += '<div class="inner"><h1>'+esc(STORY.title)+'</h1>';
  if (STORY.subtitle) html += '<div class="sub">'+esc(STORY.subtitle)+'</div>';
  html += '<div class="stats">'
       + stat(st.days,'DAYS') + stat(st.stops,'STOPS')
       + stat(miles,'MILES') + stat(st.photos,'PHOTOS')
         + '</div></div></section>';
  }

  // ② 行程全览。**封面已经是地图时不显示** ——
  // 同一页两张大地图，第二张会把封面的分量整个稀释掉。
  // 读者要动手看地图，右侧那张跟着阅读走的就是。
  if (showOverview) {
    html += '<section class="routemap">';
    html += '<h2>行程全览</h2>';
    html += '<div class="rm-sub">'+st.stops+' 站 &middot; '+miles
         +' 英里 &middot; 点地图上的站可以跳到对应的照片</div>';
    html += '<div id="omap"></div>';
    html += '</section>';
  }

  html += '<div class="layout"><div class="content">';
  STORY.days.forEach((day, di) => {
    html += '<section class="day"><h2>Day '+(di+1)+' &middot; '+day.date+'</h2>';
    day.stops.forEach(sid => {
      const s = stopById[sid];
      if (!s) return;
      const hero = photoById[s.hero];
      const rest = s.photos.filter(pid => pid !== s.hero);
      html += '<article class="stop" id="'+s.id+'" data-stop="'+s.id+'">';
      html += '<h3>'+esc(s.name || ('第 '+(s.seq+1)+' 站'))+'</h3>';
      html += '<div class="meta">'+fmtTime(s.arrive)+' - '+fmtTime(s.leave)
           +' &middot; 选了 '+s.photos.length+' 张</div>';
      if (s.note) html += '<p class="note">'+esc(s.note).replace(/\n/g,'<br>')+'</p>';
      if (hero) html += '<div class="hero-shot"><img src="'+hero.web.path
           +'" loading="lazy" alt="" data-photo="'+hero.id+'"></div>';
      if (rest.length){
        html += '<div class="grid">';
        rest.forEach(pid => {
          const ph = photoById[pid];
          if (!ph) return;
          const cls = ph.web.h > ph.web.w ? ' class="portrait"' : '';
          // 网格用 480px 的缩略图。网格里一张图显示出来也就两三百像素宽，
          // 拿 1600px 去填等于让每个访客白下几十兆
          // data-full 记着 1600px 那张 —— 网格显示缩略图，
          // 点开灯箱要换成大图，否则点开还是糊的
          html += '<img'+cls+' src="'+(ph.thumb || ph.web.path)
               +'" data-full="'+ph.web.path
               +'" loading="lazy" alt="" data-photo="'+ph.id+'">';
        });
        html += '</div>';
      }
      html += '</article>';
    });
    html += '</section>';
  });
  html += '</div><div id="mapwrap"><div id="map"></div>'
       + '<div class="pinsize">定位点'
       + '<button onclick="setPinScale(pinScale-0.3)" aria-label="调小">-</button>'
       + '<i id="pindot"></i>'
       + '<button onclick="setPinScale(pinScale+0.3)" aria-label="调大">+</button>'
       + '</div></div></div>';

  html += '<section class="summary"><div class="card">';
  html += '<h2>'+esc(STORY.title)+'</h2>';
  html += '<div class="dates">'+fmtDate(STORY.start)+' - '+fmtDate(STORY.end)+'</div>';
  html += '<div class="nums">'
       + big(st.days,'天') + big(st.stops,'站')
       + big(miles,'英里') + big(st.photos,'张照片')
       + '</div></div></section>';
  html += '<footer>路线根据照片位置推算 &middot; 地图数据 &copy; OpenStreetMap 贡献者'
       + ' &middot; 由 TravelView 生成</footer>';

  document.getElementById('app').innerHTML = html;

  // 片头地图要等 DOM 落地之后才能初始化
  if (mode !== 'photo') {
    initStoryCover('heromap', mode === 'map' ? 260 : 40);
  }
  // 把读者上次调好的定位点大小同步到那个示例小圆点上
  setPinScale(pinScale);
}
function stat(n,k){return '<div><span class="n">'+n+'</span><span class="k">'+k+'</span></div>';}
function big(n,k){return '<div><div class="n">'+n+'</div><div class="k">'+k+'</div></div>';}
function esc(s){return String(s).replace(/[&<>"]/g, c =>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));}

/* ---------- 地图与小车 ---------- */
let map, traveledLine, carMarker, allPoints = [], cum = [], total = 0;
const markerByStop = {};
let activeStop = null;
let photoPin = null;   // 当前这张照片拍摄的位置
let omap = null;

function initMap(){
  map = L.map('map', {zoomControl:false, attributionControl:false,
    scrollWheelZoom:false, dragging:true});
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    {maxZoom:19, opacity:.85}).addTo(map);

  // 把所有段拼成一条连续路线，方便按整体进度推小车
  STORY.routes.forEach(r => {
    const pts = decodePolyline(r.geometry, r.precision || 6);
    const dashed = (r.mode === 'flight');
    L.polyline(pts, {color:'#5a6b6a', weight:3, opacity:.55,
      dashArray: dashed ? '6 8' : null}).addTo(map);
    allPoints = allPoints.concat(pts);
  });

  gaps().forEach(([a, b]) => {
    L.polyline([[a.lat, a.lon], [b.lat, b.lon]],
      {color:'#8a9a98', weight:2, opacity:.45, dashArray:'3 7'}).addTo(map);
  });

  STORY.stops.forEach((s, i) => {
    const m = L.circleMarker([s.lat, s.lon], {radius:5, color:'#ffffff',
      weight:2, fillColor:'#4fbfa8', fillOpacity:1}).addTo(map).bindTooltip(
        (s.name || ('第 '+(i+1)+' 站')), {direction:'top'});
    // 地图和正文是同一件事的两个视图，点哪边都该带着另一边走
    m.on('click', () => {
      const el = document.getElementById(s.id);
      if (el) el.scrollIntoView({behavior:'smooth', block:'center'});
    });
    markerByStop[s.id] = m;
  });

  if (allPoints.length > 1){
    cum = [0];
    for (let i=1;i<allPoints.length;i++){
      cum.push(cum[i-1] + dist(allPoints[i-1], allPoints[i]));
    }
    total = cum[cum.length-1];
    traveledLine = L.polyline([allPoints[0]],
      {color:'#4fbfa8', weight:5, opacity:.95}).addTo(map);
    carMarker = L.marker(allPoints[0], {icon: L.divIcon({
      className:'', html:'<div class="car">🚗</div>', iconSize:[26,26],
      iconAnchor:[13,13]})}).addTo(map);
    map.fitBounds(L.latLngBounds(allPoints), {padding:[40,40]});
  } else if (STORY.stops.length){
    map.setView([STORY.stops[0].lat, STORY.stops[0].lon], 10);
  }
}

/* 相邻两站之间没有路线的地方 */
function gaps(){
  const has = new Set(STORY.routes.map(r => r.from + '>' + r.to));
  const out = [];
  for (let i = 0; i + 1 < STORY.stops.length; i++){
    const a = STORY.stops[i], b = STORY.stops[i+1];
    if (!has.has(a.id + '>' + b.id)) out.push([a, b]);
  }
  return out;
}

/* 行程全览: 一整条路线 + 编号的站，点站就跳到正文 */
function initOverview(){
  const el = document.getElementById('omap');
  if (!el || !STORY.stops.length) return;
  omap = L.map('omap', {scrollWheelZoom:false, attributionControl:false});
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    {maxZoom:19, opacity:.85}).addTo(omap);

  let pts = [];
  STORY.routes.forEach(r => {
    const g = decodePolyline(r.geometry, r.precision || 6);
    L.polyline(g, {color:'#4fbfa8', weight:4, opacity:.9,
      dashArray: r.mode === 'flight' ? '6 8' : null}).addTo(omap);
    pts = pts.concat(g);
  });

  // 没有路线数据的相邻两站，用淡虚线连上。
  // 地图上凭空断一截，读者只会以为产品坏了。
  gaps().forEach(([a, b]) => {
    L.polyline([[a.lat, a.lon], [b.lat, b.lon]],
      {color:'#8a9a98', weight:2, opacity:.5, dashArray:'3 7'}).addTo(omap);
  });

  STORY.stops.forEach((s, i) => {
    const m = L.marker([s.lat, s.lon], {icon: L.divIcon({
      className:'', html:'<div class="pin">'+(i+1)+'</div>',
      iconSize:[26,26], iconAnchor:[13,13]})}).addTo(omap);
    m.bindTooltip(s.name || ('第 '+(i+1)+' 站'), {direction:'top'});
    m.on('click', () => {
      const card = document.getElementById(s.id);
      if (card) card.scrollIntoView({behavior:'smooth', block:'center'});
    });
    pts.push([s.lat, s.lon]);
  });

  omap.fitBounds(L.latLngBounds(pts), {padding:[50,50]});
  // 关掉滚轮缩放，免得页面滚不下去；想缩放双击或用右上角按钮
  omap.on('click', () => omap.scrollWheelZoom.enable());
  omap.on('mouseout', () => omap.scrollWheelZoom.disable());
}

function dist(a,b){
  const R=6371008.8, r=Math.PI/180;
  const dLat=(b[0]-a[0])*r, dLon=(b[1]-a[1])*r;
  const s=Math.sin(dLat/2)**2 +
    Math.cos(a[0]*r)*Math.cos(b[0]*r)*Math.sin(dLon/2)**2;
  return 2*R*Math.atan2(Math.sqrt(s), Math.sqrt(1-s));
}

/* 滚动驱动: 滚到哪一天，车就开到哪一天，走过的路线逐渐画出来 */
function onScroll(){
  if (!traveledLine || !total) return;
  const content = document.querySelector('.content');
  if (!content) return;
  const rect = content.getBoundingClientRect();
  const span = rect.height - window.innerHeight;
  let progress = span > 0 ? (-rect.top) / span : 0;
  progress = Math.max(0, Math.min(1, progress));

  const target = total * progress;
  let i = 1;
  while (i < cum.length - 1 && cum[i] < target) i++;
  const segStart = cum[i-1], segLen = cum[i] - segStart;
  const t = segLen > 0 ? (target - segStart) / segLen : 0;
  const pos = [
    allPoints[i-1][0] + (allPoints[i][0]-allPoints[i-1][0])*t,
    allPoints[i-1][1] + (allPoints[i][1]-allPoints[i-1][1])*t,
  ];
  traveledLine.setLatLngs(allPoints.slice(0, i).concat([pos]));
  carMarker.setLatLng(pos);

  // 车头朝向前进方向
  const el = carMarker.getElement();
  if (el){
    const b = bearing(allPoints[i-1], allPoints[i]);
    el.querySelector('.car').style.transform = 'rotate('+(b-90)+'deg)';
  }
}

function bearing(a,b){
  const r=Math.PI/180;
  const y=Math.sin((b[1]-a[1])*r)*Math.cos(b[0]*r);
  const x=Math.cos(a[0]*r)*Math.sin(b[0]*r)-
          Math.sin(a[0]*r)*Math.cos(b[0]*r)*Math.cos((b[1]-a[1])*r);
  return (Math.atan2(y,x)*180/Math.PI+360)%360;
}

/* 滚到某一站时，地图轻轻跟过去 */
function watchStops(){
  const obs = new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      const s = stopById[e.target.dataset.stop];
      if (!s || !map) return;
      map.panTo([s.lat, s.lon], {animate:true, duration:.8});
      highlight(s.id);
    });
  }, {rootMargin:'-45% 0px -45% 0px'});
  document.querySelectorAll('.stop').forEach(el => obs.observe(el));
}

/* 当前这一站的点放大变白，其它的收回去 —— 不然地图上认不出在讲哪一站 */
function highlight(stopId){
  if (activeStop === stopId) return;
  const prev = markerByStop[activeStop];
  if (prev) prev.setStyle({radius:5, fillColor:'#4fbfa8'});
  const cur = markerByStop[stopId];
  if (cur){
    cur.setStyle({radius:9, fillColor:'#ffffff'});
    cur.bringToFront();
  }
  document.querySelectorAll('.stop.current')
      .forEach(el => el.classList.remove('current'));
  const card = document.getElementById(stopId);
  if (card) card.classList.add('current');
  activeStop = stopId;
}

/* 灯箱: 在当前这一站的照片之间左右翻，键盘也能翻 */
let lbList = [], lbIds = [], lbIndex = 0;

function lbShow(i){
  if (!lbList.length) return;
  lbIndex = (i + lbList.length) % lbList.length;
  const lb = document.getElementById('lb');
  lb.querySelector('img').src = lbList[lbIndex];
  lb.querySelector('.count').textContent =
    (lbIndex+1) + ' / ' + lbList.length;
  // 灯箱里翻到哪张，地图上就指到哪张 —— 全屏看图时最想知道"这是在哪拍的"
  if (lbIds[lbIndex]) locate(lbIds[lbIndex]);
  lb.classList.add('on');
}

/* 点/悬停一张照片，就在地图上把它拍摄的位置指出来 */
function locate(photoId){
  const ph = photoById[photoId];
  if (!ph || !map) return;
  document.querySelectorAll('img.located')
    .forEach(el => el.classList.remove('located'));
  const el = document.querySelector('img[data-photo="'+photoId+'"]');
  if (el) el.classList.add('located');

  const stop = STORY.stops.find(s => s.photos.indexOf(photoId) >= 0);
  if (stop) highlight(stop.id);

  if (ph.lat == null || ph.lon == null) return;
  if (!photoPin){
    photoPin = L.circleMarker([ph.lat, ph.lon], {radius:8*pinScale, weight:3,
      color:'#ffffff', fillColor:'#ff8a5b', fillOpacity:1}).addTo(map);
  } else {
    photoPin.setLatLng([ph.lat, ph.lon]);
    photoPin.setRadius(8*pinScale);
  }
  photoPin.bringToFront();

  /* **只在点快跑出画面时才动镜头。**
     像电视转播的跟拍: 主体在画面里就不动机位，快出画了才推一下，
     而且保持读者自己调好的缩放级别。
     每换一张就 panTo 会让放大看细节的读者被反复拽走。 */
  const b = map.getBounds();
  const w = b.getEast() - b.getWest(), h = b.getNorth() - b.getSouth();
  const inside = ph.lon > b.getWest() + w*0.18 && ph.lon < b.getEast() - w*0.18
              && ph.lat > b.getSouth() + h*0.18 && ph.lat < b.getNorth() - h*0.18;
  if (!inside) map.panTo([ph.lat, ph.lon], {animate:true, duration:.5});
}

/* 定位点大小: 手机小屏上 8px 几乎看不见，大屏上又嫌小，
   而且视力和看的距离因人而异。存在这台设备上，不属于作品本身。 */
let pinScale = 1;
try {
  const v = Number(localStorage.getItem('tv.pinScale'));
  if (v >= 0.6 && v <= 3) pinScale = v;
} catch (e) { /* 隐私模式下不给用 localStorage，用默认值就好 */ }

function setPinScale(v){
  pinScale = Math.round(Math.max(0.6, Math.min(3, v)) * 10) / 10;
  try { localStorage.setItem('tv.pinScale', String(pinScale)); } catch (e) {}
  if (photoPin) photoPin.setRadius(8*pinScale);
  const dot = document.getElementById('pindot');
  if (dot) {
    dot.style.width = Math.round(10*pinScale)+'px';
    dot.style.height = Math.round(10*pinScale)+'px';
  }
}

function initLocate(){
  document.addEventListener('mouseover', e => {
    const img = e.target.closest('img[data-photo]');
    if (img) locate(img.dataset.photo);
  });
}

function initLightbox(){
  const lb = document.getElementById('lb');
  document.addEventListener('click', e => {
    const nav = e.target.closest('.lb-nav');
    if (nav){
      lbShow(lbIndex + (nav.dataset.d === '1' ? 1 : -1));
      return;
    }
    if (e.target.tagName === 'IMG' && e.target.closest('.grid, .hero-shot')){
      // 灯箱里能翻的是**这一站**的照片，翻到别的站会让人失去方位
      const card = e.target.closest('.stop');
      const imgs = card
        ? Array.from(card.querySelectorAll('.hero-shot img, .grid img'))
        : [e.target];
      lbList = imgs.map(x => x.dataset.full || x.src);
      lbIds = imgs.map(x => x.dataset.photo);
      lbShow(imgs.indexOf(e.target));
    } else if (e.target.closest('.lightbox')){
      lb.classList.remove('on');
    }
  });
  document.addEventListener('keydown', e => {
    if (!lb.classList.contains('on')) return;
    if (e.key === 'Escape') lb.classList.remove('on');
    if (e.key === 'ArrowRight') lbShow(lbIndex + 1);
    if (e.key === 'ArrowLeft') lbShow(lbIndex - 1);
  });
}

render();
initMap();
initOverview();
initLocate();
watchStops();
initLightbox();
window.addEventListener('scroll', onScroll, {passive:true});
onScroll();
</script>
</body>
</html>
''';
