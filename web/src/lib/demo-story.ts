import type { Story } from './story';

/**
 * 落地页用的示例 Story。
 *
 * 上线前把它换成你横穿美国那一趟的真实数据 ——
 * 首屏的说服力几乎全靠这一份数据的质量。
 * 照片路径指向 public/demo/ 下的静态文件。
 */
export const demoStory: Story = {
  version: 1,
  id: 'demo',
  slug: 'demo',
  title: 'A Weekend in Chicago',
  subtitle: 'September 3–5, 2025 · 3 days · 1 city',
  start: '2025-09-03T09:10:00.000Z',
  end: '2025-09-05T18:40:00.000Z',
  cover: 'p1',
  template: 'classic',
  stats: { days: 3, stops: 4, photos: 6, distanceMeters: 42700 },
  days: [
    { date: '2025-09-03', stops: ['stop-0'] },
    { date: '2025-09-04', stops: ['stop-1', 'stop-2'] },
    { date: '2025-09-05', stops: ['stop-3'] },
  ],
  stops: [
    {
      id: 'stop-0', seq: 0, name: 'Millennium Park',
      lat: 41.8826, lon: -87.6226,
      arrive: '2025-09-03T09:10:00.000Z', leave: '2025-09-03T11:30:00.000Z',
      hero: 'p1', photos: ['p1', 'p2'],
    },
    {
      id: 'stop-1', seq: 1, name: 'Chicago Riverwalk',
      lat: 41.8882, lon: -87.6350,
      arrive: '2025-09-04T13:40:00.000Z', leave: '2025-09-04T14:42:00.000Z',
      hero: 'p3', photos: ['p3', 'p4'],
    },
    {
      id: 'stop-2', seq: 2, name: 'Navy Pier',
      lat: 41.8919, lon: -87.6051,
      arrive: '2025-09-04T16:05:00.000Z', leave: '2025-09-04T18:20:00.000Z',
      hero: 'p5', photos: ['p5'],
    },
    {
      id: 'stop-3', seq: 3, name: 'Evanston',
      lat: 42.0451, lon: -87.6877,
      arrive: '2025-09-05T15:20:00.000Z', leave: '2025-09-05T18:40:00.000Z',
      hero: 'p6', photos: ['p6'],
    },
  ],
  photos: [
    photo('p1', '2025-09-03T09:12:00.000Z', 41.8826, -87.6226),
    photo('p2', '2025-09-03T10:40:00.000Z', 41.8830, -87.6230),
    photo('p3', '2025-09-04T13:44:00.000Z', 41.8882, -87.6350),
    photo('p4', '2025-09-04T14:20:00.000Z', 41.8885, -87.6340, true),
    photo('p5', '2025-09-04T16:30:00.000Z', 41.8919, -87.6051),
    photo('p6', '2025-09-05T15:50:00.000Z', 42.0451, -87.6877),
  ],
  routes: [
    route('stop-0', 'stop-1', 1900, '_p~iF~ps|U_ulLnnqC_mqNvxq`@'),
    route('stop-1', 'stop-2', 2600, '_p~iF~ps|U_ulLnnqC_mqNvxq`@'),
    route('stop-2', 'stop-3', 21000, '_p~iF~ps|U_ulLnnqC_mqNvxq`@'),
  ],
};

function photo(
  id: string, takenAt: string, lat: number, lon: number, portrait = false,
) {
  return {
    id,
    takenAt,
    lat,
    lon,
    web: {
      path: `demo/${id}.webp`,
      w: portrait ? 1200 : 1600,
      h: portrait ? 1600 : 1200,
    },
    thumb: `demo/${id}-t.webp`,
  };
}

function route(from: string, to: string, distanceMeters: number, geometry: string) {
  return {
    from, to,
    mode: 'driving',
    source: 'inferred',
    provider: 'osrm',
    distanceMeters,
    geometry,
    precision: 5,
  };
}
