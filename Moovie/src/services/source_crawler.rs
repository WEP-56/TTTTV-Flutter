use crate::models::VodItem;
use crate::utils::error::{MoovieError, Result};
use async_trait::async_trait;
use reqwest::Client;
use serde::Deserialize;
use std::collections::HashMap;
use std::time::Duration;

#[async_trait]
pub trait SourceCrawler: Send + Sync {
    async fn search(
        &self,
        base_url: &str,
        keyword: &str,
        source_key: &str,
        restricted_categories: &[String],
    ) -> Result<Vec<VodItem>>;

    async fn get_detail(&self, base_url: &str, vod_id: &str, source_key: &str) -> Result<VodItem>;
}

#[derive(Debug, Clone)]
pub struct DefaultSourceCrawler {
    client: Client,
    timeout: Duration,
}

impl DefaultSourceCrawler {
    pub fn new(timeout: Duration) -> Self {
        let client = Client::builder()
            .timeout(timeout)
            .user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")
            .build()
            .expect("Failed to create HTTP client");

        DefaultSourceCrawler { client, timeout }
    }

    fn map_to_vod_item(item: &HashMap<String, serde_json::Value>, source_key: &str) -> VodItem {
        VodItem {
            source_key: source_key.to_string(),
            vod_id: Self::to_string(item.get("vod_id")),
            vod_name: Self::to_string(item.get("vod_name")),
            vod_sub: Self::to_option_string(item.get("vod_sub")),
            vod_en: Self::to_option_string(item.get("vod_en")),
            vod_tag: Self::to_option_string(item.get("vod_tag")),
            vod_class: Self::to_option_string(item.get("vod_class")),
            vod_pic: Self::to_option_string(item.get("vod_pic")),
            vod_actor: Self::to_option_string(item.get("vod_actor")),
            vod_director: Self::to_option_string(item.get("vod_director")),
            vod_blurb: Self::to_option_string(item.get("vod_blurb")),
            vod_remarks: Self::to_option_string(item.get("vod_remarks")),
            vod_pubdate: Self::to_option_string(item.get("vod_pubdate")),
            vod_total: Self::to_option_string(item.get("vod_total")),
            vod_serial: Self::to_option_string(item.get("vod_serial")),
            vod_area: Self::to_option_string(item.get("vod_area")),
            vod_lang: Self::to_option_string(item.get("vod_lang")),
            vod_year: Self::to_option_string(item.get("vod_year")),
            vod_duration: Self::to_option_string(item.get("vod_duration")),
            vod_time: Self::to_option_string(item.get("vod_time")),
            vod_douban_id: Self::to_option_string(item.get("vod_douban_id")),
            vod_content: Self::to_option_string(item.get("vod_content")),
            vod_play_url: Self::to_string(item.get("vod_play_url")),
            type_name: Self::to_option_string(item.get("type_name")),
            last_visited_at: None,
            avg_speed_ms: None,
            sample_count: None,
            failed_count: None,
        }
    }

    fn to_string(v: Option<&serde_json::Value>) -> String {
        if let Some(s) = v.and_then(|val| val.as_str()) {
            return s.to_string();
        }
        if let Some(i) = v.and_then(|val| val.as_i64()) {
            return i.to_string();
        }
        if let Some(f) = v.and_then(|val| val.as_f64()) {
            return f.to_string();
        }
        String::new()
    }

    fn to_option_string(v: Option<&serde_json::Value>) -> Option<String> {
        let s = Self::to_string(v);
        if s.is_empty() { None } else { Some(s) }
    }
}

#[derive(Debug, Deserialize)]
struct VodApiResponse {
    code: Option<serde_json::Value>,
    msg: Option<String>,
    list: Option<Vec<HashMap<String, serde_json::Value>>>,
}

#[async_trait]
impl SourceCrawler for DefaultSourceCrawler {
    async fn search(
        &self,
        base_url: &str,
        keyword: &str,
        source_key: &str,
        restricted_categories: &[String],
    ) -> Result<Vec<VodItem>> {
        let mut url = if base_url.ends_with('/') {
            base_url.to_string()
        } else {
            format!("{}/", base_url)
        };
        url.push_str("?ac=videolist&pg=1&wd=");
        url.push_str(&urlencoding::encode(keyword));

        let response = self.client.get(&url).send().await?;

        if !response.status().is_success() {
            return Err(MoovieError::SourceSearchError(format!(
                "请求失败: {}",
                response.status()
            )));
        }

        let api_resp: VodApiResponse = response.json().await?;

        if let Some(code) = &api_resp.code {
            let code_num = match code {
                serde_json::Value::Number(n) => n.as_i64().unwrap_or(0),
                serde_json::Value::String(s) => s.parse::<i64>().unwrap_or(0),
                _ => 0,
            };
            if ![0, 1, 200].contains(&code_num) {
                if let Some(msg) = &api_resp.msg {
                    return Err(MoovieError::SourceSearchError(format!("API错误: {}", msg)));
                }
                return Err(MoovieError::SourceSearchError(format!(
                    "API错误代码: {}",
                    code_num
                )));
            }
        }

        let list = api_resp.list.unwrap_or_default();

        let mut items = Vec::new();
        for item in list {
            let vod_item = Self::map_to_vod_item(&item, source_key);

            if !restricted_categories.is_empty() {
                if let Some(type_name) = &vod_item.type_name {
                    if restricted_categories.iter().any(|r| type_name.contains(r)) {
                        continue;
                    }
                }
            }

            items.push(vod_item);
        }

        Ok(items)
    }

    async fn get_detail(&self, base_url: &str, vod_id: &str, source_key: &str) -> Result<VodItem> {
        let mut url = if base_url.ends_with('/') {
            base_url.to_string()
        } else {
            format!("{}/", base_url)
        };
        url.push_str("?ac=videolist&ids=");
        url.push_str(vod_id);

        let response = self.client.get(&url).send().await?;

        if !response.status().is_success() {
            return Err(MoovieError::DetailError(format!(
                "请求失败: {}",
                response.status()
            )));
        }

        let api_resp: VodApiResponse = response.json().await?;

        if let Some(code) = &api_resp.code {
            let code_num = match code {
                serde_json::Value::Number(n) => n.as_i64().unwrap_or(0),
                serde_json::Value::String(s) => s.parse::<i64>().unwrap_or(0),
                _ => 0,
            };
            if ![0, 1, 200].contains(&code_num) {
                if let Some(msg) = &api_resp.msg {
                    return Err(MoovieError::DetailError(format!("API错误: {}", msg)));
                }
                return Err(MoovieError::DetailError(format!(
                    "API错误代码: {}",
                    code_num
                )));
            }
        }

        let list = api_resp.list.ok_or_else(|| MoovieError::NotFound)?;

        if list.is_empty() {
            return Err(MoovieError::NotFound);
        }

        let vod_item = Self::map_to_vod_item(&list[0], source_key);

        Ok(vod_item)
    }
}
