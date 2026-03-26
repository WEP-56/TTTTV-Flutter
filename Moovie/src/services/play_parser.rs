use crate::utils::error::{MoovieError, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayEpisode {
    pub name: String,
    pub url: String,
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
pub struct PlayParser {
    client: Client,
}

impl PlayParser {
    pub fn new() -> Self {
        PlayParser {
            client: Client::new(),
        }
    }

    pub fn parse_play_url(&self, play_url: &str) -> Result<PlayResult> {
        info!("解析播放链接: {}", play_url);

        let mut sources = Vec::new();
        let source_parts: Vec<&str> = play_url.split("$$$").collect();

        for (source_idx, source_part) in source_parts.iter().enumerate() {
            if source_part.is_empty() {
                continue;
            }

            let source_name = format!("源{}", source_idx + 1);
            let mut episodes = Vec::new();

            let episode_parts: Vec<&str> = source_part.split('#').collect();

            for episode_part in episode_parts {
                if episode_part.is_empty() {
                    continue;
                }

                let name_url: Vec<&str> = episode_part.split('$').collect();
                if name_url.len() >= 2 {
                    let name = name_url[0].to_string();
                    let url = name_url[1..].join("$");
                    episodes.push(PlayEpisode { name, url });
                }
            }

            if !episodes.is_empty() {
                sources.push(PlaySource {
                    name: source_name,
                    episodes,
                });
            }
        }

        Ok(PlayResult { sources })
    }

    pub async fn resolve_m3u8_url(&self, url: &str) -> Result<String> {
        info!("解析M3U8 URL: {}", url);
        Ok(url.to_string())
    }
}

impl Default for PlayParser {
    fn default() -> Self {
        Self::new()
    }
}
