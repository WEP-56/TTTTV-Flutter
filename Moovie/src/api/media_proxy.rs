use axum::{
    body::Body,
    extract::{Query, State},
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use futures::TryStreamExt;
use reqwest::Client;
use serde::Deserialize;
use tracing::warn;
use url::Url;

use crate::core::AppState;

#[derive(Deserialize)]
pub struct MediaProxyQuery {
    pub url: String,
    pub referer: Option<String>,
}

// ── M3U8 代理 ────────────────────────────────────────────────────────────────
// 获取原始 M3U8，将 segment / key URL 重写为走本代理，解决防盗链 403。
pub async fn proxy_m3u8(
    State(state): State<AppState>,
    Query(q): Query<MediaProxyQuery>,
) -> Response {
    let referer = q.referer.as_deref().unwrap_or("");

    let (text, final_url) = match fetch_text(&state.client, &q.url, referer).await {
        Ok(t) => t,
        Err(e) => {
            warn!("[media_proxy] fetch m3u8 failed: {}", e);
            return (
                StatusCode::BAD_GATEWAY,
                format!("上游 M3U8 获取失败: {}", e),
            )
                .into_response();
        }
    };

    let rewritten = rewrite_m3u8(&text, &final_url, referer);

    Response::builder()
        .status(200)
        .header(header::CONTENT_TYPE, "application/vnd.apple.mpegurl")
        .header(header::CACHE_CONTROL, "no-store")
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(Body::from(rewritten))
        .unwrap()
}

// ── TS 分片代理 ───────────────────────────────────────────────────────────────
pub async fn proxy_segment(
    State(state): State<AppState>,
    Query(q): Query<MediaProxyQuery>,
) -> Response {
    let referer = q.referer.as_deref().unwrap_or("");
    proxy_bytes(&state.client, &q.url, referer, "video/mp2t").await
}

// ── HLS Key 代理 ──────────────────────────────────────────────────────────────
pub async fn proxy_key(
    State(state): State<AppState>,
    Query(q): Query<MediaProxyQuery>,
) -> Response {
    let referer = q.referer.as_deref().unwrap_or("");
    proxy_bytes(&state.client, &q.url, referer, "application/octet-stream").await
}

// ── 内部工具函数 ──────────────────────────────────────────────────────────────

/// 返回 (响应文本, 最终 URL)，final URL 用于重定向后的相对路径解析（P2）
async fn fetch_text(client: &Client, url: &str, referer: &str) -> Result<(String, String), String> {
    let mut builder = client.get(url).header("User-Agent", UA);
    if !referer.is_empty() {
        builder = builder.header("Referer", referer);
    }
    let resp = builder
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !resp.status().is_success() {
        return Err(format!("HTTP {}", resp.status()));
    }
    let final_url = resp.url().to_string();
    let text = resp.text().await.map_err(|e| e.to_string())?;
    Ok((text, final_url))
}

async fn proxy_bytes(client: &Client, url: &str, referer: &str, content_type: &str) -> Response {
    let mut builder = client.get(url).header("User-Agent", UA);
    if !referer.is_empty() {
        builder = builder.header("Referer", referer);
    }

    let upstream = match builder.send().await {
        Ok(r) => r,
        Err(e) => {
            warn!("[media_proxy] fetch bytes failed {}: {}", url, e);
            return (
                StatusCode::BAD_GATEWAY,
                format!("上游请求失败: {}", e),
            )
                .into_response();
        }
    };

    if !upstream.status().is_success() {
        let status = upstream.status().as_u16();
        return (
            StatusCode::from_u16(status).unwrap_or(StatusCode::BAD_GATEWAY),
            format!("上游返回 HTTP {}", status),
        )
            .into_response();
    }

    let content_length = upstream.headers().get(reqwest::header::CONTENT_LENGTH).cloned();

    let stream = upstream
        .bytes_stream()
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e));

    let mut builder = Response::builder()
        .status(200)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CACHE_CONTROL, "no-store")
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*");
    if let Some(cl) = content_length {
        builder = builder.header(header::CONTENT_LENGTH, cl);
    }
    builder.body(Body::from_stream(stream)).unwrap()
}

/// 重写 M3U8 内容中的 segment / key / 子M3U8 URL，全部走本地代理。
/// 自动区分 Master Playlist（含 #EXT-X-STREAM-INF）和 Media Playlist。
fn rewrite_m3u8(content: &str, base_url: &str, referer: &str) -> String {
    let base = Url::parse(base_url).ok();
    let encoded_referer = urlencoding::encode(referer).into_owned();
    let is_master = content.lines().any(|l| l.starts_with("#EXT-X-STREAM-INF"));

    content
        .lines()
        .map(|line| {
            // HLS 加密 key（仅 Media Playlist 有）
            if line.starts_with("#EXT-X-KEY:") {
                return rewrite_key_tag(line, base.as_ref(), &encoded_referer);
            }
            // 跳过其他 # 注释行和空行
            if line.starts_with('#') || line.trim().is_empty() {
                return line.to_string();
            }
            let abs_url = resolve_url(line.trim(), base.as_ref());
            if is_master {
                // Master Playlist：非 # 行是子 M3U8，走 /proxy/m3u8
                format!(
                    "http://127.0.0.1:5007/proxy/m3u8?url={}&referer={}",
                    urlencoding::encode(&abs_url),
                    encoded_referer
                )
            } else {
                // Media Playlist：非 # 行是 TS segment
                format!(
                    "http://127.0.0.1:5007/proxy/segment?url={}&referer={}",
                    urlencoding::encode(&abs_url),
                    encoded_referer
                )
            }
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn rewrite_key_tag(line: &str, base: Option<&Url>, encoded_referer: &str) -> String {
    // 找到 URI="..." 并替换
    if let Some(start) = line.find("URI=\"") {
        let after_quote = start + 5;
        if let Some(end) = line[after_quote..].find('"') {
            let original_uri = &line[after_quote..after_quote + end];
            let abs_uri = resolve_url(original_uri, base);
            let proxy_uri = format!(
                "http://127.0.0.1:5007/proxy/key?url={}&referer={}",
                urlencoding::encode(&abs_uri),
                encoded_referer
            );
            return format!(
                "{}{}{}",
                &line[..after_quote],
                proxy_uri,
                &line[after_quote + end..]
            );
        }
    }
    line.to_string()
}

fn resolve_url(url: &str, base: Option<&Url>) -> String {
    // 已是绝对 URL
    if url.starts_with("http://") || url.starts_with("https://") {
        return url.to_string();
    }
    // 尝试用 base 解析相对路径
    if let Some(base) = base {
        if let Ok(abs) = base.join(url) {
            return abs.to_string();
        }
    }
    url.to_string()
}

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
