use async_trait::async_trait;
use serde_json::Value;
use url::Url;

use std::collections::HashMap;

use super::super::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail, LiveRoomItem};
use super::LiveProvider;
use super::douyin_abogus_native;
use crate::utils::error::{MoovieError, Result};

pub struct DouyinProvider {
    client: reqwest::Client,
    cookie: String,
}

impl DouyinProvider {
    pub fn new(client: reqwest::Client, cookie: String) -> Self {
        Self { client, cookie }
    }

    fn default_user_agent() -> &'static str {
        // from dart_simple_live (DouyinSite.kDefaultUserAgent)
        "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400"
    }

    fn default_cookie() -> &'static str {
        // from dart_simple_live (DouyinSite.kDefaultCookie)
        "ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511"
    }

    fn cookie_header(&self) -> String {
        let c = self.cookie.trim();
        if c.is_empty() {
            Self::default_cookie().to_string()
        } else {
            c.to_string()
        }
    }

    fn base_headers(&self) -> HashMap<&'static str, String> {
        HashMap::from([
            ("user-agent", Self::default_user_agent().to_string()),
            ("referer", "https://live.douyin.com".to_string()),
            ("cookie", self.cookie_header()),
        ])
    }

    fn generate_ms_token(len: usize) -> String {
        use rand::Rng;
        use rand::distributions::Alphanumeric;
        rand::thread_rng()
            .sample_iter(&Alphanumeric)
            .take(len)
            .map(char::from)
            .collect()
    }

    fn get_abogus(query: &str, user_agent: &str) -> Result<String> {
        Ok(douyin_abogus_native::generate_a_bogus(query, user_agent))
    }

    fn with_abogus(url: &str, user_agent: &str) -> Result<String> {
        let ms_token = Self::generate_ms_token(107);
        let mut u = Url::parse(url)
            .map_err(|e| MoovieError::InvalidParameter(format!("url 解析失败: {}", e)))?;
        {
            let mut qp = u.query_pairs_mut();
            qp.append_pair("msToken", &ms_token);
        }
        let query = u.query().unwrap_or("").to_string();
        let a_bogus = Self::get_abogus(&query, user_agent)?;
        {
            let mut qp = u.query_pairs_mut();
            qp.append_pair("a_bogus", &a_bogus);
        }
        Ok(u.to_string())
    }

    async fn get_room_data_by_api(&self, web_rid: &str) -> Result<Value> {
        let base = "https://live.douyin.com/webcast/room/web/enter/";
        let url = Url::parse_with_params(
            base,
            &[
                ("aid", "6383"),
                ("app_name", "douyin_web"),
                ("live_id", "1"),
                ("device_platform", "web"),
                ("language", "zh-CN"),
                ("browser_language", "zh-CN"),
                ("browser_platform", "Win32"),
                ("browser_name", "Chrome"),
                ("browser_version", "125.0.0.0"),
                ("web_rid", web_rid),
                ("msToken", ""),
            ],
        )
        .map_err(|e| MoovieError::InvalidParameter(format!("url 解析失败: {}", e)))?;

        let signed = Self::with_abogus(url.as_str(), Self::default_user_agent())?;

        let mut headers = self.base_headers();
        headers.insert("referer", format!("https://live.douyin.com/{}", web_rid));

        let mut req = self.client.get(signed);
        for (k, v) in headers {
            req = req.header(k, v);
        }
        let json = req.send().await?.json::<Value>().await?;
        Ok(json["data"].clone())
    }

    fn parse_online(v: &Value) -> i64 {
        v.as_i64()
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
            .unwrap_or(0)
    }

    fn extract_stream_url(room_data: &Value) -> Value {
        room_data.get("stream_url").cloned().unwrap_or(Value::Null)
    }

    fn extract_pull_urls_from_stream(
        stream_url: &Value,
    ) -> Vec<(String, String, i32, Vec<String>)> {
        // returns vec of (id, name, sort, urls)
        let mut out = Vec::new();
        let live_core = &stream_url["live_core_sdk_data"];
        let pull_data = &live_core["pull_data"];
        let options = &pull_data["options"];
        let qualities = options["qualities"].as_array().cloned().unwrap_or_default();

        let stream_data_raw = pull_data["stream_data"]
            .as_str()
            .map(|s| s.to_string())
            .unwrap_or_else(|| pull_data["stream_data"].to_string());
        if stream_data_raw.trim_start().starts_with('{') {
            if let Ok(stream_json) = serde_json::from_str::<Value>(&stream_data_raw) {
                let data = &stream_json["data"];
                for q in qualities {
                    let name = q["name"].as_str().unwrap_or("未知清晰度").to_string();
                    let level = q["level"].as_i64().unwrap_or(0) as i32;
                    let sdk_key = q["sdk_key"].as_str().unwrap_or("").trim().to_string();
                    let id = if !sdk_key.is_empty() {
                        sdk_key.clone()
                    } else {
                        level.to_string()
                    };

                    let mut urls = Vec::new();
                    if let Some(flv) = data[&sdk_key]["main"]["flv"]
                        .as_str()
                        .filter(|s| !s.is_empty())
                    {
                        urls.push(flv.to_string());
                    }
                    if let Some(hls) = data[&sdk_key]["main"]["hls"]
                        .as_str()
                        .filter(|s| !s.is_empty())
                    {
                        urls.push(hls.to_string());
                    }
                    if !urls.is_empty() {
                        out.push((id, name, level, urls));
                    }
                }
            }
        } else {
            // fallback to flv_pull_url / hls_pull_url_map
            let flv_list: Vec<String> = stream_url["flv_pull_url"]
                .as_object()
                .map(|m| {
                    m.values()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            let hls_list: Vec<String> = stream_url["hls_pull_url_map"]
                .as_object()
                .map(|m| {
                    m.values()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            for q in qualities {
                let name = q["name"].as_str().unwrap_or("未知清晰度").to_string();
                let level = q["level"].as_i64().unwrap_or(0) as i32;
                let id = q["sdk_key"]
                    .as_str()
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or(&level.to_string())
                    .to_string();

                let mut urls = Vec::new();
                let flv_idx = (flv_list.len() as i32) - level;
                if flv_idx >= 0 && (flv_idx as usize) < flv_list.len() {
                    urls.push(flv_list[flv_idx as usize].clone());
                }
                let hls_idx = (hls_list.len() as i32) - level;
                if hls_idx >= 0 && (hls_idx as usize) < hls_list.len() {
                    urls.push(hls_list[hls_idx as usize].clone());
                }

                if !urls.is_empty() {
                    out.push((id, name, level, urls));
                }
            }
        }

        out.sort_by(|a, b| b.2.cmp(&a.2));
        out
    }
}

#[async_trait]
impl LiveProvider for DouyinProvider {
    fn id(&self) -> &'static str {
        "douyin"
    }

    fn name(&self) -> &'static str {
        "抖音"
    }

    async fn recommend_rooms(&self, page: i32) -> Result<Vec<LiveRoomItem>> {
        let page = if page <= 0 { 1 } else { page };
        let offset = (page - 1) * 15;

        let base = "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
        let url = Url::parse_with_params(
            base,
            &[
                ("aid", "6383"),
                ("app_name", "douyin_web"),
                ("live_id", "1"),
                ("device_platform", "web"),
                ("language", "zh-CN"),
                ("enter_from", "link_share"),
                ("cookie_enabled", "true"),
                ("screen_width", "1980"),
                ("screen_height", "1080"),
                ("browser_language", "zh-CN"),
                ("browser_platform", "Win32"),
                ("browser_name", "Edge"),
                ("browser_version", "125.0.0.0"),
                ("browser_online", "true"),
                ("count", "15"),
                ("offset", &offset.to_string()),
                ("partition", "720"),
                ("partition_type", "1"),
                ("req_from", "2"),
            ],
        )
        .map_err(|e| MoovieError::InvalidParameter(format!("url 解析失败: {}", e)))?;

        let signed = Self::with_abogus(url.as_str(), Self::default_user_agent())?;

        let mut req = self.client.get(signed);
        for (k, v) in self.base_headers() {
            req = req.header(k, v);
        }

        let json = req.send().await?.json::<Value>().await?;
        let list = json["data"]["data"].as_array().cloned().unwrap_or_default();

        let mut items = Vec::new();
        for item in list {
            let rid = item["web_rid"].as_str().unwrap_or("").to_string();
            if rid.trim().is_empty() {
                continue;
            }
            let room = &item["room"];
            let cover = room["cover"]["url_list"]
                .as_array()
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            items.push(LiveRoomItem {
                platform: self.id().to_string(),
                room_id: rid,
                title: room["title"].as_str().unwrap_or("").to_string(),
                cover,
                user_name: room["owner"]["nickname"].as_str().unwrap_or("").to_string(),
                online: Self::parse_online(&room["room_view_stats"]["display_value"]),
            });
        }

        Ok(items)
    }

    async fn search_rooms(&self, keyword: &str, page: i32) -> Result<Vec<LiveRoomItem>> {
        if keyword.trim().is_empty() {
            return Ok(Vec::new());
        }
        let page = if page <= 0 { 1 } else { page };
        let offset = (page - 1) * 10;

        // refresh cookies for search (ttwid + __ac_nonce)
        let head = self
            .client
            .head("https://live.douyin.com")
            .header("user-agent", Self::default_user_agent())
            .header("referer", "https://live.douyin.com")
            .send()
            .await?;
        let mut dy_cookie = String::new();
        for value in head.headers().get_all(reqwest::header::SET_COOKIE).iter() {
            if let Ok(s) = value.to_str() {
                let cookie = s.split(';').next().unwrap_or("").trim();
                if cookie.contains("ttwid") || cookie.contains("__ac_nonce") {
                    dy_cookie.push_str(cookie);
                    dy_cookie.push(';');
                }
            }
        }

        let url = Url::parse_with_params(
            "https://www.douyin.com/aweme/v1/web/live/search/",
            &[
                ("device_platform", "webapp"),
                ("aid", "6383"),
                ("channel", "channel_pc_web"),
                ("search_channel", "aweme_live"),
                ("keyword", keyword),
                ("search_source", "switch_tab"),
                ("query_correct_type", "1"),
                ("is_filter_search", "0"),
                ("from_group_id", ""),
                ("offset", &offset.to_string()),
                ("count", "10"),
                ("pc_client_type", "1"),
                ("version_code", "170400"),
                ("version_name", "17.4.0"),
                ("cookie_enabled", "true"),
                ("screen_width", "1980"),
                ("screen_height", "1080"),
                ("browser_language", "zh-CN"),
                ("browser_platform", "Win32"),
                ("browser_name", "Edge"),
                ("browser_version", "125.0.0.0"),
                ("browser_online", "true"),
                ("engine_name", "Blink"),
                ("engine_version", "125.0.0.0"),
                ("os_name", "Windows"),
                ("os_version", "10"),
                ("cpu_core_num", "12"),
                ("device_memory", "8"),
                ("platform", "PC"),
                ("downlink", "10"),
                ("effective_type", "4g"),
                ("round_trip_time", "100"),
            ],
        )
        .map_err(|e| MoovieError::InvalidParameter(format!("url 解析失败: {}", e)))?;

        let referer = format!(
            "https://www.douyin.com/search/{}?type=live",
            urlencoding::encode(keyword)
        );
        let json = self
            .client
            .get(url)
            .header("user-agent", Self::default_user_agent())
            .header("accept", "application/json, text/plain, */*")
            .header("referer", referer)
            .header("cookie", dy_cookie)
            .send()
            .await?
            .json::<Value>()
            .await?;

        let mut items = Vec::new();
        let list = json["data"].as_array().cloned().unwrap_or_default();
        for item in list {
            let raw = item["lives"]["rawdata"].as_str().unwrap_or("");
            if raw.trim().is_empty() {
                continue;
            }
            let Ok(obj) = serde_json::from_str::<Value>(raw) else {
                continue;
            };
            let rid = obj["owner"]["web_rid"].as_str().unwrap_or("").to_string();
            if rid.trim().is_empty() {
                continue;
            }
            let cover = obj["room"]["cover"]["url_list"]
                .as_array()
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            items.push(LiveRoomItem {
                platform: self.id().to_string(),
                room_id: rid,
                title: obj["room"]["title"].as_str().unwrap_or("").to_string(),
                cover,
                user_name: obj["owner"]["nickname"].as_str().unwrap_or("").to_string(),
                online: Self::parse_online(&obj["room"]["room_view_stats"]["display_value"]),
            });
        }

        Ok(items)
    }

    async fn room_detail(&self, room_id: &str) -> Result<LiveRoomDetail> {
        let web_rid = room_id.trim();
        if web_rid.is_empty() {
            return Err(MoovieError::InvalidParameter(
                "room_id 不能为空".to_string(),
            ));
        }

        let data = self.get_room_data_by_api(web_rid).await?;
        let room_data = data["data"]
            .as_array()
            .and_then(|a| a.first())
            .cloned()
            .unwrap_or(Value::Null);
        if room_data.is_null() {
            return Err(MoovieError::DetailError("抖音房间信息解析失败".to_string()));
        }

        let user_data = data.get("user").cloned().unwrap_or(Value::Null);
        let owner = room_data.get("owner").cloned().unwrap_or(Value::Null);
        let status = room_data["status"].as_i64().unwrap_or(0) == 2;

        let cover = room_data["cover"]["url_list"]
            .as_array()
            .and_then(|a| a.first())
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        let avatar_live = owner["avatar_thumb"]["url_list"]
            .as_array()
            .and_then(|a| a.first())
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let avatar_off = user_data["avatar_thumb"]["url_list"]
            .as_array()
            .and_then(|a| a.first())
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        Ok(LiveRoomDetail {
            platform: self.id().to_string(),
            room_id: web_rid.to_string(),
            title: room_data["title"].as_str().unwrap_or("").to_string(),
            cover: if status { cover } else { "".to_string() },
            user_name: if status {
                owner["nickname"].as_str().unwrap_or("").to_string()
            } else {
                user_data["nickname"].as_str().unwrap_or("").to_string()
            },
            user_avatar: if status { avatar_live } else { avatar_off },
            online: if status {
                Self::parse_online(&room_data["room_view_stats"]["display_value"])
            } else {
                0
            },
            introduction: owner
                .get("signature")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .filter(|s| !s.trim().is_empty()),
            notice: None,
            status,
            is_record: false,
            url: format!("https://live.douyin.com/{}", web_rid),
            show_time: None,
        })
    }

    async fn play_qualities(&self, room_id: &str) -> Result<Vec<LivePlayQuality>> {
        let data = self.get_room_data_by_api(room_id).await?;
        let room_data = data["data"]
            .as_array()
            .and_then(|a| a.first())
            .cloned()
            .unwrap_or(Value::Null);
        if room_data.is_null() {
            return Err(MoovieError::DetailError("抖音房间信息解析失败".to_string()));
        }
        let status = room_data["status"].as_i64().unwrap_or(0) == 2;
        if !status {
            return Err(MoovieError::InvalidParameter("直播间未开播".to_string()));
        }

        let stream_url = Self::extract_stream_url(&room_data);
        let qualities = Self::extract_pull_urls_from_stream(&stream_url);
        Ok(qualities
            .into_iter()
            .map(|(id, name, sort, _urls)| LivePlayQuality { id, name, sort })
            .collect())
    }

    async fn play_urls(&self, room_id: &str, quality_id: &str) -> Result<LivePlayUrl> {
        let data = self.get_room_data_by_api(room_id).await?;
        let room_data = data["data"]
            .as_array()
            .and_then(|a| a.first())
            .cloned()
            .unwrap_or(Value::Null);
        if room_data.is_null() {
            return Err(MoovieError::DetailError("抖音房间信息解析失败".to_string()));
        }
        let status = room_data["status"].as_i64().unwrap_or(0) == 2;
        if !status {
            return Err(MoovieError::InvalidParameter("直播间未开播".to_string()));
        }

        let stream_url = Self::extract_stream_url(&room_data);
        let qualities = Self::extract_pull_urls_from_stream(&stream_url);
        let urls = qualities
            .iter()
            .find(|(id, _name, _sort, _urls)| id == quality_id)
            .map(|(_id, _name, _sort, urls)| urls.clone())
            .or_else(|| qualities.first().map(|q| q.3.clone()))
            .unwrap_or_default();

        Ok(LivePlayUrl {
            urls,
            headers: None,
            url_type: Some("auto".to_string()),
            expires_at: None,
        })
    }
}
