use serde::{Deserialize, Serialize};
use tracing::info;

const PROXY_BASE: &str = "http://127.0.0.1:5007";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayEpisode {
    pub name: String,
    /// 原始播放 URL
    pub url: String,
    /// 若为 M3U8，此字段为经本地代理重写后的 URL；Flutter 侧优先使用此字段
    pub proxy_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlaySource {
    pub name: String,
    pub episodes: Vec<PlayEpisode>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayResult {
    pub sources: Vec<PlaySource>,
}

#[derive(Clone)]
pub struct PlayParser;

impl PlayParser {
    pub fn new() -> Self {
        PlayParser
    }

    /// 解析 vod_play_url 字符串，同时为 M3U8 链接生成本地代理 URL。
    /// `referer` 通常传数据源的 detail 域名，用于绕过防盗链。
    pub fn parse_play_url(&self, play_url: &str, referer: &str) -> PlayResult {
        info!("解析播放链接，referer={}", referer);

        let mut sources = Vec::new();
        let source_parts: Vec<&str> = play_url.split("$$$").collect();

        for (source_idx, source_part) in source_parts.iter().enumerate() {
            if source_part.is_empty() {
                continue;
            }

            let source_name = format!("源{}", source_idx + 1);
            let mut episodes = Vec::new();

            for episode_part in source_part.split('#') {
                if episode_part.is_empty() {
                    continue;
                }

                let name_url: Vec<&str> = episode_part.split('$').collect();
                if name_url.len() >= 2 {
                    let name = name_url[0].to_string();
                    let url = name_url[1..].join("$");
                    let proxy_url = build_proxy_url(&url, referer);
                    episodes.push(PlayEpisode { name, url, proxy_url });
                }
            }

            if !episodes.is_empty() {
                sources.push(PlaySource {
                    name: source_name,
                    episodes,
                });
            }
        }

        PlayResult { sources }
    }
}

impl Default for PlayParser {
    fn default() -> Self {
        Self::new()
    }
}

/// 若 URL 是 M3U8，返回本地代理地址；否则返回 None。
fn build_proxy_url(url: &str, referer: &str) -> Option<String> {
    let lower = url.to_lowercase();
    if lower.contains(".m3u8") || lower.contains("m3u8") {
        Some(format!(
            "{}/proxy/m3u8?url={}&referer={}",
            PROXY_BASE,
            urlencoding::encode(url),
            urlencoding::encode(referer)
        ))
    } else {
        None
    }
}
