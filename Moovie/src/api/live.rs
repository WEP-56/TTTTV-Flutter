use axum::{
    Json, Router,
    body::Body,
    extract::ws::WebSocketUpgrade,
    extract::{Path, Query, State},
    http::{self, HeaderMap, Response, header},
    response::IntoResponse,
    routing::get,
};
use futures::StreamExt;
use serde::Deserialize;
use url::Url;

use crate::core::AppState;
use crate::live::danmaku;
use crate::live::models::{
    LivePlatformInfo, LivePlayQuality, LivePlayUrl, LiveRoomDetail, LiveRoomItem,
};
use crate::live::providers::{
    LiveProvider, bilibili::BiliBiliProvider, douyin::DouyinProvider, douyu::DouyuProvider,
    huya::HuyaProvider,
};
use crate::utils::error::MoovieError;
use crate::utils::response::{ApiResponse, ApiResult};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/platforms", get(get_platforms))
        .route("/:platform/recommend", get(get_recommend_rooms))
        .route("/:platform/search", get(search_rooms))
        .route("/:platform/room/detail", get(get_room_detail))
        .route("/:platform/room/qualities", get(get_play_qualities))
        .route("/:platform/room/play", get(get_play_urls))
        .route("/:platform/room/danmaku", get(danmaku_ws))
        .route("/proxy", get(proxy))
        .route("/proxy/set_stream_url", get(set_stream_url))
        .route("/proxy/start", get(start_proxy_endpoint))
        .route("/proxy/stop", get(stop_proxy_endpoint))
        .nest("/history", super::live_history::router())
        .nest("/favorites", super::live_favorites::router())
        .nest("/auth", super::live_auth::router())
}

pub async fn get_platforms() -> ApiResult<Vec<LivePlatformInfo>> {
    let platforms = vec![
        LivePlatformInfo {
            id: "bilibili".to_string(),
            name: "Bilibili".to_string(),
        },
        LivePlatformInfo {
            id: "douyu".to_string(),
            name: "斗鱼".to_string(),
        },
        LivePlatformInfo {
            id: "huya".to_string(),
            name: "虎牙".to_string(),
        },
        LivePlatformInfo {
            id: "douyin".to_string(),
            name: "抖音".to_string(),
        },
    ];
    Ok(Json(ApiResponse::success(platforms)))
}

#[derive(Deserialize)]
pub struct PageQuery {
    pub page: Option<i32>,
}

#[derive(Deserialize)]
pub struct SearchQuery {
    pub kw: String,
    pub page: Option<i32>,
}

#[derive(Deserialize)]
pub struct RoomIdQuery {
    pub room_id: String,
}

#[derive(Deserialize)]
pub struct PlayQuery {
    pub room_id: String,
    pub quality_id: String,
}

pub async fn get_recommend_rooms(
    State(state): State<AppState>,
    Path(platform): Path<String>,
    Query(query): Query<PageQuery>,
) -> ApiResult<Vec<LiveRoomItem>> {
    let provider = build_provider(&platform, &state)?;
    let page = query.page.unwrap_or(1);
    let items = provider.recommend_rooms(page).await?;
    Ok(Json(ApiResponse::success(items)))
}

pub async fn search_rooms(
    State(state): State<AppState>,
    Path(platform): Path<String>,
    Query(query): Query<SearchQuery>,
) -> ApiResult<Vec<LiveRoomItem>> {
    let provider = build_provider(&platform, &state)?;
    let page = query.page.unwrap_or(1);
    let items = provider.search_rooms(&query.kw, page).await?;
    Ok(Json(ApiResponse::success(items)))
}

pub async fn get_room_detail(
    State(state): State<AppState>,
    Path(platform): Path<String>,
    Query(query): Query<RoomIdQuery>,
) -> ApiResult<LiveRoomDetail> {
    let provider = build_provider(&platform, &state)?;
    let detail = provider.room_detail(&query.room_id).await?;
    Ok(Json(ApiResponse::success(detail)))
}

pub async fn get_play_qualities(
    State(state): State<AppState>,
    Path(platform): Path<String>,
    Query(query): Query<RoomIdQuery>,
) -> ApiResult<Vec<LivePlayQuality>> {
    let provider = build_provider(&platform, &state)?;
    let qualities = provider.play_qualities(&query.room_id).await?;
    Ok(Json(ApiResponse::success(qualities)))
}

pub async fn get_play_urls(
    State(state): State<AppState>,
    Path(platform): Path<String>,
    Query(query): Query<PlayQuery>,
) -> ApiResult<LivePlayUrl> {
    let provider = build_provider(&platform, &state)?;
    let play = provider
        .play_urls(&query.room_id, &query.quality_id)
        .await?;
    Ok(Json(ApiResponse::success(play)))
}

pub async fn danmaku_ws(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    Path(platform): Path<String>,
    Query(query): Query<RoomIdQuery>,
) -> impl IntoResponse {
    let bili_cookie = if platform == "bilibili" {
        state
            .storage
            .lock()
            .unwrap()
            .get_live_cookie("bilibili")
            .unwrap_or_default()
    } else {
        String::new()
    };

    ws.on_upgrade(move |socket| async move {
        if platform == "bilibili" {
            let _ =
                danmaku::bilibili::bridge(state.client.clone(), bili_cookie, query.room_id, socket)
                    .await;
        } else if platform == "douyu" {
            let _ = danmaku::douyu::bridge(query.room_id, socket).await;
        } else if platform == "huya" {
            let provider = HuyaProvider::new(state.client.clone());
            match provider.get_danmaku_args(&query.room_id).await {
                Ok(args) => {
                    let _ = danmaku::huya::bridge(args, socket).await;
                }
                Err(_) => {
                    let _ = socket;
                }
            }
        } else {
            // For now, close immediately for unsupported platforms.
            let _ = socket;
        }
    })
}

fn build_provider(platform: &str, state: &AppState) -> Result<Box<dyn LiveProvider>, MoovieError> {
    match platform {
        "bilibili" => {
            let cookie = state
                .storage
                .lock()
                .unwrap()
                .get_live_cookie("bilibili")
                .unwrap_or_default();
            Ok(Box::new(BiliBiliProvider::new(
                state.client.clone(),
                cookie,
            )))
        }
        "douyu" => Ok(Box::new(DouyuProvider::new(state.client.clone()))),
        "huya" => Ok(Box::new(HuyaProvider::new(state.client.clone()))),
        "douyin" => {
            let cookie = state
                .storage
                .lock()
                .unwrap()
                .get_live_cookie("douyin")
                .unwrap_or_default();
            Ok(Box::new(DouyinProvider::new(state.client.clone(), cookie)))
        }
        _ => Err(MoovieError::InvalidParameter("未知直播平台".to_string())),
    }
}

#[derive(Deserialize)]
pub struct ProxyQuery {
    pub platform: Option<String>,
    pub url: String,
}

pub async fn proxy(
    State(state): State<AppState>,
    Query(query): Query<ProxyQuery>,
) -> Result<Response<Body>, MoovieError> {
    let url = Url::parse(&query.url)
        .map_err(|_| MoovieError::InvalidParameter("url 参数无效".to_string()))?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err(MoovieError::InvalidParameter(
            "url 必须以 http:// 或 https:// 开头".to_string(),
        ));
    }

    let platform = query.platform.as_deref();
    let headers = platform_default_headers(platform);

    let mut req = state.client.get(url.clone());
    for (k, v) in headers.iter() {
        req = req.header(k, v);
    }

    let upstream = req.send().await?;
    let status = upstream.status();
    let upstream_headers = upstream.headers().clone();

    if is_m3u8(&url, &upstream_headers) {
        let text = upstream.text().await?;
        let rewritten = rewrite_m3u8(&text, &url, platform);

        let mut builder = Response::builder()
            .status(status)
            .header(header::CONTENT_TYPE, "application/vnd.apple.mpegurl");

        if let Some(cache_control) = upstream_headers.get(header::CACHE_CONTROL) {
            builder = builder.header(header::CACHE_CONTROL, cache_control);
        }

        return builder
            .body(Body::from(rewritten))
            .map_err(|e| MoovieError::Unknown(e.to_string()));
    }

    let builder = Response::builder().status(status);
    let builder = copy_passthrough_headers(&upstream_headers, builder);

    let stream = upstream
        .bytes_stream()
        .map(|item| item.map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e)));
    let body = Body::from_stream(stream);
    builder
        .body(body)
        .map_err(|e| MoovieError::Unknown(e.to_string()))
}

fn platform_default_headers(platform: Option<&str>) -> HeaderMap {
    let mut headers = HeaderMap::new();

    // A reasonably modern UA avoids some platform quirks.
    headers.insert(
        header::USER_AGENT,
        header::HeaderValue::from_static(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
        ),
    );

    match platform.unwrap_or_default() {
        "bilibili" => {
            headers.insert(
                header::REFERER,
                header::HeaderValue::from_static("https://live.bilibili.com/"),
            );
        }
        "douyu" => {
            headers.insert(
                header::REFERER,
                header::HeaderValue::from_static("https://www.douyu.com/"),
            );
        }
        "huya" => {
            // Huya streams are sensitive to UA; mimic HYSDK (from dart_simple_live).
            headers.insert(
                header::USER_AGENT,
                header::HeaderValue::from_static(
                    "HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)",
                ),
            );
            headers.insert(
                header::REFERER,
                header::HeaderValue::from_static("https://www.huya.com/"),
            );
        }
        "douyin" => {
            // Use a QQBrowser UA (from dart_simple_live) to avoid douyin quirks.
            headers.insert(
                header::USER_AGENT,
                header::HeaderValue::from_static(
                    "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400",
                ),
            );
            headers.insert(
                header::REFERER,
                header::HeaderValue::from_static("https://live.douyin.com/"),
            );
        }
        _ => {}
    }

    headers
}

fn is_m3u8(url: &Url, headers: &HeaderMap) -> bool {
    if url.path().to_ascii_lowercase().ends_with(".m3u8") {
        return true;
    }

    if let Some(ct) = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
    {
        let ct = ct.to_ascii_lowercase();
        if ct.contains("application/vnd.apple.mpegurl") || ct.contains("application/x-mpegurl") {
            return true;
        }
    }

    false
}

fn copy_passthrough_headers(
    upstream: &HeaderMap,
    mut builder: http::response::Builder,
) -> http::response::Builder {
    for key in [
        header::CONTENT_TYPE,
        header::CONTENT_LENGTH,
        header::ACCEPT_RANGES,
        header::CONTENT_RANGE,
        header::CACHE_CONTROL,
        header::ETAG,
        header::LAST_MODIFIED,
    ] {
        if let Some(v) = upstream.get(&key) {
            builder = builder.header(key, v);
        }
    }
    builder
}

fn rewrite_m3u8(content: &str, base: &Url, platform: Option<&str>) -> String {
    let mut out = String::with_capacity(content.len() + 256);

    for line in content.lines() {
        if line.trim().is_empty() {
            out.push('\n');
            continue;
        }

        if line.starts_with('#') {
            out.push_str(&rewrite_uri_attributes(line, base, platform));
            out.push('\n');
            continue;
        }

        let abs = resolve_m3u8_uri(base, line.trim(), platform);
        out.push_str(&make_proxy_url(platform, &abs));
        out.push('\n');
    }

    out
}

fn rewrite_uri_attributes(line: &str, base: &Url, platform: Option<&str>) -> String {
    let mut remaining = line;
    let mut result = String::with_capacity(line.len() + 64);

    loop {
        let Some(pos) = remaining.find("URI=\"") else {
            result.push_str(remaining);
            break;
        };

        let start = pos + 5; // after URI="
        result.push_str(&remaining[..start]);
        let rest = &remaining[start..];
        let Some(end_quote) = rest.find('"') else {
            // malformed, keep as-is
            result.push_str(rest);
            break;
        };

        let uri_str = &rest[..end_quote];
        let abs = resolve_m3u8_uri(base, uri_str, platform);
        result.push_str(&make_proxy_url(platform, &abs));

        remaining = &rest[end_quote..];
    }

    result
}

fn resolve_m3u8_uri(base: &Url, uri: &str, platform: Option<&str>) -> Url {
    if let Ok(abs) = Url::parse(uri) {
        return abs;
    }

    let mut joined = base.join(uri).unwrap_or_else(|_| base.clone());

    // Some platforms (notably Bilibili) embed access tokens in the playlist query string,
    // but use relative URIs for segments/keys. Propagate the base query to joined URIs
    // when the reference doesn't specify its own query.
    if matches!(platform, Some("bilibili"))
        && base.query().is_some()
        && joined.query().is_none()
        && !uri.contains('?')
    {
        joined.set_query(base.query());
    }

    joined
}

fn make_proxy_url(platform: Option<&str>, abs: &Url) -> String {
    let encoded = urlencoding::encode(abs.as_str());
    match platform {
        Some(p) if !p.is_empty() => format!("/api/live/proxy?platform={}&url={}", p, encoded),
        _ => format!("/api/live/proxy?url={}", encoded),
    }
}

#[derive(Deserialize)]
pub struct SetStreamUrlQuery {
    pub url: String,
    pub platform: Option<String>,
}

pub async fn set_stream_url(
    State(state): State<AppState>,
    Query(query): Query<SetStreamUrlQuery>,
) -> ApiResult<String> {
    *state.stream_url_store.url.lock().unwrap() = query.url.clone();
    *state.stream_url_store.platform.lock().unwrap() = query.platform.unwrap_or_default();
    Ok(Json(ApiResponse::success(query.url)))
}

pub async fn start_proxy_endpoint(
    State(state): State<AppState>,
) -> Result<Json<ApiResponse<String>>, MoovieError> {
    let proxy_url = crate::proxy::start_proxy(
        state.proxy_server_handle.clone(),
        state.stream_url_store.clone(),
    )
    .await
    .map_err(|e| MoovieError::Unknown(e))?;

    Ok(Json(ApiResponse::success(proxy_url)))
}

pub async fn stop_proxy_endpoint(
    State(state): State<AppState>,
) -> Result<Json<ApiResponse<()>>, MoovieError> {
    crate::proxy::stop_proxy(state.proxy_server_handle.clone())
        .await
        .map_err(|e| MoovieError::Unknown(e))?;

    Ok(Json(ApiResponse::success(())))
}
