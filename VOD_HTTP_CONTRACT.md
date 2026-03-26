# VOD HTTP Contract Freeze

Date: 2026-03-26

This document freezes the HTTP contract for the first Flutter Windows migration cut.

## Scope

- `GET /health`
- `GET /api/search`
- `GET /api/detail`
- `GET /api/play/parse`
- `GET/POST/DELETE /api/history`
- `GET/POST/DELETE /api/favorites`
- `GET/POST/DELETE /api/sources`

Live endpoints are intentionally excluded from this freeze.

## Envelope

All business endpoints return:

```json
{
  "success": true,
  "data": {},
  "message": null,
  "error": null
}
```

Current error policy for the Windows cut:

- keep `ApiResponse<T>` as the transport envelope
- keep backend-generated error strings unchanged for now
- keep HTTP 400 for invalid parameters
- keep HTTP 404 for not found
- keep HTTP 500 for other backend failures

## Time fields

Current HTTP contracts use Unix epoch seconds where timestamps are present.

- `last_play_time`
- `created_time`
- `last_check`

Flutter should convert them at the adapter layer instead of changing backend payloads during the first cut.

## DTOs

### `HealthResponse`

```ts
type HealthResponse = {
  status: string;
  version: string;
};
```

### `SearchResult`

```ts
type SearchResult = {
  items: VodItem[];
  filtered_count: number;
};
```

### `VodItem`

Actual Rust shape is broader than the current TypeScript subset. Flutter should follow the Rust shape, not the trimmed TS interface.

```ts
type VodItem = {
  source_key: string;
  vod_id: string;
  vod_name: string;
  vod_sub?: string | null;
  vod_en?: string | null;
  vod_tag?: string | null;
  vod_class?: string | null;
  vod_pic?: string | null;
  vod_actor?: string | null;
  vod_director?: string | null;
  vod_blurb?: string | null;
  vod_remarks?: string | null;
  vod_pubdate?: string | null;
  vod_total?: string | null;
  vod_serial?: string | null;
  vod_area?: string | null;
  vod_lang?: string | null;
  vod_year?: string | null;
  vod_duration?: string | null;
  vod_time?: string | null;
  vod_douban_id?: string | null;
  vod_content?: string | null;
  vod_play_url: string;
  type_name?: string | null;
  last_visited_at?: string | null;
  avg_speed_ms?: number | null;
  sample_count?: number | null;
  failed_count?: number | null;
};
```

### `PlayResult`

Flutter should use the Rust contract below for episode/source parsing.

```ts
type PlayEpisode = {
  name: string;
  url: string;
};

type PlaySource = {
  name: string;
  episodes: PlayEpisode[];
};

type PlayResult = {
  sources: PlaySource[];
};
```

Important note:

- `moovie-front/src/api/client.ts` currently declares a different `PlayResult` shape with `url` and `headers`.
- That declaration does not match `Moovie/src/services/play_parser.rs`.
- Flutter should align to the Rust `sources -> episodes` contract.

### `WatchHistoryItem`

```ts
type WatchHistoryItem = {
  vod_id: string;
  source_key: string;
  vod_name: string;
  vod_pic?: string | null;
  last_play_time: number;
  progress: number;
  episode?: string | null;
};
```

### `AddWatchHistoryRequest`

```ts
type AddWatchHistoryRequest = {
  vod_id: string;
  source_key: string;
  vod_name: string;
  vod_pic?: string | null;
  progress: number;
  episode?: string | null;
};
```

### `FavoriteItem`

```ts
type FavoriteItem = {
  vod_id: string;
  source_key: string;
  vod_name: string;
  vod_pic?: string | null;
  vod_remarks?: string | null;
  vod_actor?: string | null;
  vod_director?: string | null;
  vod_content?: string | null;
  created_time: number;
};
```

### `AddFavoriteRequest`

```ts
type AddFavoriteRequest = {
  vod_id: string;
  source_key: string;
  vod_name: string;
  vod_pic?: string | null;
  vod_remarks?: string | null;
  vod_actor?: string | null;
  vod_director?: string | null;
  vod_content?: string | null;
};
```

### `CheckFavoriteResponse`

```ts
type CheckFavoriteResponse = {
  is_favorited: boolean;
};
```

### `SiteWithStatus`

```ts
type SiteWithStatus = {
  key: string;
  name: string;
  base_url: string;
  enabled: boolean;
  last_check?: number | null;
  is_healthy?: boolean | null;
  comment?: string | null;
  r18?: boolean | null;
  group?: string | null;
};
```

### `RemoteSource`

```ts
type RemoteSource = {
  key: string;
  name: string;
  api: string;
  detail: string;
  group?: string | null;
  r18?: boolean | null;
  comment?: string | null;
};
```

### `RemoteSourcesResponse`

```ts
type RemoteSourcesResponse = {
  url: string;
  sources: RemoteSource[];
};
```

### `AddSourcesBatchResult`

```ts
type AddSourcesBatchFailure = {
  key: string;
  error: string;
};

type AddSourcesBatchResult = {
  added: string[];
  skipped_existing: string[];
  failed: AddSourcesBatchFailure[];
};
```

## Flutter adapter rules

- Keep one base URL source for HTTP mode.
- Convert `ApiResponse<T>` to typed success/error results inside the adapter layer.
- Parse `vod_play_url` only through `/api/play/parse` in Flutter, not in widgets.
- Treat `vod_pic`, `episode`, remarks, actor, director, and content fields as nullable.
