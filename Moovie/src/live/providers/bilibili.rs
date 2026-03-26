use async_trait::async_trait;
use md5::{Digest, Md5};
use once_cell::sync::Lazy;
use serde_json::Value;
use tokio::sync::Mutex;
use url::Url;

use std::collections::HashMap;

use crate::utils::error::{MoovieError, Result};
use super::super::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail, LiveRoomItem};
use super::LiveProvider;

static WBI_CACHE: Lazy<Mutex<WbiCache>> = Lazy::new(|| Mutex::new(WbiCache::default()));

#[derive(Debug, Default, Clone)]
struct WbiCache {
    img_key: String,
    sub_key: String,
    mixin_key: String,
    buvid3: String,
    buvid4: String,
}

pub struct BiliBiliProvider {
    client: reqwest::Client,
    cookie: String,
}

#[derive(Debug, Clone)]
pub(crate) struct BiliBiliDanmakuInfo {
    pub room_id: i64,
    pub token: String,
    pub server_host: String,
    pub buvid: String,
    pub cookie: String,
    pub uid: i64,
}

impl BiliBiliProvider {
    pub fn new(client: reqwest::Client, cookie: String) -> Self {
        Self {
            client,
            cookie,
        }
    }

    fn default_user_agent() -> &'static str {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    }

    pub(crate) async fn ensure_buvid(&self) -> Result<(String, String)> {
        let cache = WBI_CACHE.lock().await;
        if !cache.buvid3.is_empty() && !cache.buvid4.is_empty() {
            return Ok((cache.buvid3.clone(), cache.buvid4.clone()));
        }
        drop(cache);

        let resp = self
            .client
            .get("https://api.bilibili.com/x/frontend/finger/spi")
            .header("user-agent", Self::default_user_agent())
            .header("referer", "https://live.bilibili.com/")
            .send()
            .await?
            .json::<Value>()
            .await?;

        let buvid3 = resp["data"]["b_3"].as_str().unwrap_or("").to_string();
        let buvid4 = resp["data"]["b_4"].as_str().unwrap_or("").to_string();

        let mut cache = WBI_CACHE.lock().await;
        cache.buvid3 = buvid3.clone();
        cache.buvid4 = buvid4.clone();
        Ok((buvid3, buvid4))
    }

    pub(crate) async fn header_map(&self) -> Result<HashMap<String, String>> {
        let (buvid3, buvid4) = self.ensure_buvid().await?;
        let cookie = if self.cookie.is_empty() {
            format!("buvid3={};buvid4={};", buvid3, buvid4)
        } else if self.cookie.contains("buvid3=") {
            self.cookie.clone()
        } else {
            format!("{};buvid3={};buvid4={};", self.cookie, buvid3, buvid4)
        };

        Ok(HashMap::from([
            ("user-agent".to_string(), Self::default_user_agent().to_string()),
            ("referer".to_string(), "https://live.bilibili.com/".to_string()),
            ("cookie".to_string(), cookie),
        ]))
    }

    async fn ensure_wbi_keys(&self) -> Result<WbiCache> {
        let cache = WBI_CACHE.lock().await;
        if !cache.mixin_key.is_empty() {
            return Ok(cache.clone());
        }
        drop(cache);

        let headers = self.header_map().await?;
        let resp = self
            .client
            .get("https://api.bilibili.com/x/web-interface/nav")
            .header("user-agent", &headers["user-agent"])
            .header("referer", &headers["referer"])
            .header("cookie", &headers["cookie"])
            .send()
            .await?
            .json::<Value>()
            .await?;

        let img_url = resp["data"]["wbi_img"]["img_url"].as_str().unwrap_or("");
        let sub_url = resp["data"]["wbi_img"]["sub_url"].as_str().unwrap_or("");

        let img_key = img_url
            .rsplit('/')
            .next()
            .unwrap_or("")
            .split('.')
            .next()
            .unwrap_or("")
            .to_string();
        let sub_key = sub_url
            .rsplit('/')
            .next()
            .unwrap_or("")
            .split('.')
            .next()
            .unwrap_or("")
            .to_string();

        if img_key.is_empty() || sub_key.is_empty() {
            return Err(MoovieError::ConfigError(
                "Bilibili wbi key 获取失败".to_string(),
            ));
        }

        let mixin = get_mixin_key(&(img_key.clone() + &sub_key));

        let mut cache = WBI_CACHE.lock().await;
        cache.img_key = img_key;
        cache.sub_key = sub_key;
        cache.mixin_key = mixin;
        Ok(cache.clone())
    }

    pub(crate) async fn wbi_sign_params(&self, url: &str) -> Result<HashMap<String, String>> {
        let cache = self.ensure_wbi_keys().await?;

        let parsed = Url::parse(url)
            .map_err(|e| MoovieError::InvalidParameter(format!("url 解析失败: {}", e)))?;

        let mut params: HashMap<String, String> = parsed
            .query_pairs()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();

        let now = chrono::Utc::now().timestamp();
        params.insert("wts".to_string(), now.to_string());

        // sort keys and filter special characters in values for signing
        let mut kvs: Vec<(String, String)> = params
            .iter()
            .map(|(k, v)| (k.clone(), filter_wbi_value(v)))
            .collect();
        kvs.sort_by(|a, b| a.0.cmp(&b.0));

        let query = kvs
            .iter()
            .map(|(k, v)| format!("{}={}", k, urlencoding::encode(v)))
            .collect::<Vec<_>>()
            .join("&");

        let mut hasher = Md5::new();
        hasher.update(query.as_bytes());
        hasher.update(cache.mixin_key.as_bytes());
        let w_rid = format!("{:x}", hasher.finalize());

        params.insert("w_rid".to_string(), w_rid);
        Ok(params)
    }

    pub(crate) async fn get_json(&self, url: &str, params: HashMap<String, String>) -> Result<Value> {
        let headers = self.header_map().await?;

        let resp = self
            .client
            .get(url)
            .query(&params)
            .header("user-agent", &headers["user-agent"])
            .header("referer", &headers["referer"])
            .header("cookie", &headers["cookie"])
            .send()
            .await?
            .json::<Value>()
            .await?;

        Ok(resp)
    }

    pub(crate) async fn get_danmaku_info(&self, room_id: &str) -> Result<BiliBiliDanmakuInfo> {
        // 1) resolve real room id
        let info_base = "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom";
        let info_url = format!("{}?room_id={}", info_base, room_id);
        let info_params = self.wbi_sign_params(&info_url).await?;
        let info_json = self.get_json(info_base, info_params).await?;
        let real_room_id = info_json["data"]["room_info"]["room_id"]
            .as_i64()
            .unwrap_or_else(|| room_id.parse().unwrap_or(0));

        // 2) danmaku server + token
        let danmu_base = "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo";
        let danmu_url = format!("{}?id={}", danmu_base, real_room_id);
        let danmu_params = self.wbi_sign_params(&danmu_url).await?;
        let danmu_json = self.get_json(danmu_base, danmu_params).await?;
        let token = danmu_json["data"]["token"].as_str().unwrap_or("").to_string();
        let server_host = danmu_json["data"]["host_list"]
            .as_array()
            .and_then(|arr| arr.first())
            .and_then(|v| v.get("host"))
            .and_then(|v| v.as_str())
            .unwrap_or("broadcastlv.chat.bilibili.com")
            .to_string();

        let (buvid3, _buvid4) = self.ensure_buvid().await?;
        let headers = self.header_map().await?;

        Ok(BiliBiliDanmakuInfo {
            room_id: real_room_id,
            token,
            server_host,
            buvid: buvid3,
            cookie: headers.get("cookie").cloned().unwrap_or_default(),
            uid: 0,
        })
    }
}

#[async_trait]
impl LiveProvider for BiliBiliProvider {
    fn id(&self) -> &'static str {
        "bilibili"
    }

    fn name(&self) -> &'static str {
        "Bilibili"
    }

    async fn recommend_rooms(&self, page: i32) -> Result<Vec<LiveRoomItem>> {
        let page = if page <= 0 { 1 } else { page };
        let base = "https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea";
        let full_url = format!(
            "{}?platform=web&sort=online&page_size=30&page={}",
            base, page
        );
        let params = self.wbi_sign_params(&full_url).await?;
        let json = self.get_json(base, params).await?;

        let mut items = Vec::new();
        let list = json["data"]["list"].as_array().cloned().unwrap_or_default();
        for item in list {
            let room_id = item["roomid"].as_i64().unwrap_or(0).to_string();
            if room_id == "0" {
                continue;
            }
            items.push(LiveRoomItem {
                platform: self.id().to_string(),
                room_id,
                title: item["title"].as_str().unwrap_or("").to_string(),
                cover: item["cover"].as_str().unwrap_or("").to_string(),
                user_name: item["uname"].as_str().unwrap_or("").to_string(),
                online: item["online"]
                    .as_i64()
                    .or_else(|| item["online"].as_str().and_then(|s| s.parse().ok()))
                    .unwrap_or(0),
            });
        }

        Ok(items)
    }

    async fn search_rooms(&self, keyword: &str, page: i32) -> Result<Vec<LiveRoomItem>> {
        if keyword.trim().is_empty() {
            return Ok(Vec::new());
        }

        let page = if page <= 0 { 1 } else { page };
        let url = "https://api.bilibili.com/x/web-interface/search/type";

        let headers = self.header_map().await?;
        let params: Vec<(&str, String)> = vec![
            ("context", "".to_string()),
            ("search_type", "live".to_string()),
            ("cover_type", "user_cover".to_string()),
            ("order", "".to_string()),
            ("keyword", keyword.to_string()),
            ("category_id", "".to_string()),
            ("highlight", "0".to_string()),
            ("single_column", "0".to_string()),
            ("page", page.to_string()),
        ];
        let json = self
            .client
            .get(url)
            .query(&params)
            .header("user-agent", &headers["user-agent"])
            .header("referer", &headers["referer"])
            .header("cookie", &headers["cookie"])
            .send()
            .await?
            .json::<Value>()
            .await?;

        let mut items = Vec::new();
        let rooms = json["data"]["result"]["live_room"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        for item in rooms {
            let mut title = item["title"].as_str().unwrap_or("").to_string();
            // remove <em>...</em>
            title = title.replace("<em class=\"keyword\">", "").replace("</em>", "");

            let cover = item["cover"].as_str().unwrap_or("");
            let cover = if cover.starts_with("//") {
                format!("https:{}@400w.jpg", cover)
            } else if cover.starts_with("http") {
                format!("{}@400w.jpg", cover)
            } else {
                format!("https:{}@400w.jpg", cover)
            };

            items.push(LiveRoomItem {
                platform: self.id().to_string(),
                room_id: item["roomid"].as_i64().unwrap_or(0).to_string(),
                title,
                cover,
                user_name: item["uname"].as_str().unwrap_or("").to_string(),
                online: item["online"]
                    .as_i64()
                    .or_else(|| item["online"].as_str().and_then(|s| s.parse().ok()))
                    .unwrap_or(0),
            });
        }

        Ok(items)
    }

    async fn room_detail(&self, room_id: &str) -> Result<LiveRoomDetail> {
        let room_info_base =
            "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom";
        let room_info_url = format!("{}?room_id={}", room_info_base, room_id);
        let room_info_params = self.wbi_sign_params(&room_info_url).await?;
        let room_info_json = self.get_json(room_info_base, room_info_params).await?;
        let data = &room_info_json["data"];

        let real_room_id = data["room_info"]["room_id"]
            .as_i64()
            .unwrap_or_else(|| room_id.parse().unwrap_or(0))
            .to_string();

        let title = data["room_info"]["title"].as_str().unwrap_or("").to_string();
        let cover = data["room_info"]["cover"].as_str().unwrap_or("").to_string();
        let online = data["room_info"]["online"].as_i64().unwrap_or(0);
        let live_status = data["room_info"]["live_status"].as_i64().unwrap_or(0) == 1;
        let live_start_time = data["room_info"]["live_start_time"]
            .as_i64()
            .unwrap_or(0);
        let show_time = if live_start_time > 0 {
            Some(live_start_time.to_string())
        } else {
            None
        };

        let user_name = data["anchor_info"]["base_info"]["uname"]
            .as_str()
            .unwrap_or("")
            .to_string();
        let user_avatar = data["anchor_info"]["base_info"]["face"]
            .as_str()
            .unwrap_or("")
            .to_string();

        Ok(LiveRoomDetail {
            platform: self.id().to_string(),
            room_id: real_room_id.clone(),
            title,
            cover,
            user_name,
            user_avatar,
            online,
            introduction: data["room_info"]["description"]
                .as_str()
                .map(|s| s.to_string())
                .filter(|s| !s.trim().is_empty()),
            notice: None,
            status: live_status,
            is_record: false,
            url: format!("https://live.bilibili.com/{}", real_room_id),
            show_time,
        })
    }

    async fn play_qualities(&self, room_id: &str) -> Result<Vec<LivePlayQuality>> {
        let detail = self.room_detail(room_id).await?;
        let url = "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo";

        let params = HashMap::from([
            ("room_id".to_string(), detail.room_id.clone()),
            ("protocol".to_string(), "0,1".to_string()),
            ("format".to_string(), "0,1,2".to_string()),
            ("codec".to_string(), "0,1".to_string()),
            ("platform".to_string(), "web".to_string()),
        ]);

        let json = self.get_json(url, params).await?;

        let mut qn_desc: HashMap<i64, String> = HashMap::new();
        if let Some(arr) = json["data"]["playurl_info"]["playurl"]["g_qn_desc"].as_array() {
            for item in arr {
                let qn = item["qn"].as_i64().unwrap_or(0);
                let desc = item["desc"].as_str().unwrap_or("").to_string();
                if qn > 0 {
                    qn_desc.insert(qn, desc);
                }
            }
        }

        let mut qualities = Vec::new();
        if let Some(arr) = json["data"]["playurl_info"]["playurl"]["stream"]
            .get(0)
            .and_then(|v| v.get("format"))
            .and_then(|v| v.get(0))
            .and_then(|v| v.get("codec"))
            .and_then(|v| v.get(0))
            .and_then(|v| v.get("accept_qn"))
            .and_then(|v| v.as_array())
        {
            for qn in arr {
                let qn = qn.as_i64().unwrap_or(0);
                if qn <= 0 {
                    continue;
                }
                qualities.push(LivePlayQuality {
                    id: qn.to_string(),
                    name: qn_desc.get(&qn).cloned().unwrap_or_else(|| "未知清晰度".to_string()),
                    sort: qn as i32,
                });
            }
        }

        qualities.sort_by(|a, b| b.sort.cmp(&a.sort));
        Ok(qualities)
    }

    async fn play_urls(&self, room_id: &str, quality_id: &str) -> Result<LivePlayUrl> {
        let detail = self.room_detail(room_id).await?;
        let url = "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo";

        let params = HashMap::from([
            ("room_id".to_string(), detail.room_id.clone()),
            ("protocol".to_string(), "0,1".to_string()),
            ("format".to_string(), "0,2".to_string()),
            ("codec".to_string(), "0".to_string()),
            ("platform".to_string(), "web".to_string()),
            ("qn".to_string(), quality_id.to_string()),
        ]);

        let json = self.get_json(url, params).await?;

        let mut urls: Vec<String> = Vec::new();
        if let Some(streams) = json["data"]["playurl_info"]["playurl"]["stream"].as_array() {
            for stream in streams {
                if let Some(formats) = stream["format"].as_array() {
                    for format in formats {
                        if let Some(codecs) = format["codec"].as_array() {
                            for codec in codecs {
                                let base_url = codec["base_url"].as_str().unwrap_or("");
                                if let Some(url_infos) = codec["url_info"].as_array() {
                                    for info in url_infos {
                                        let host = info["host"].as_str().unwrap_or("");
                                        let extra = info["extra"].as_str().unwrap_or("");
                                        if !host.is_empty() && !base_url.is_empty() {
                                            urls.push(format!("{}{}{}", host, base_url, extra));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // prefer m3u8 first (browser-friendly)
        urls.sort_by(|a, b| {
            let a_is_m3u8 = a.contains(".m3u8");
            let b_is_m3u8 = b.contains(".m3u8");
            b_is_m3u8.cmp(&a_is_m3u8).then_with(|| a.contains("mcdn").cmp(&b.contains("mcdn")))
        });

        Ok(LivePlayUrl {
            urls,
            headers: Some(HashMap::from([
                ("referer".to_string(), "https://live.bilibili.com/".to_string()),
                ("user-agent".to_string(), Self::default_user_agent().to_string()),
            ])),
            url_type: Some("auto".to_string()),
            expires_at: None,
        })
    }
}

fn filter_wbi_value(value: &str) -> String {
    value
        .chars()
        .filter(|c| !matches!(*c, '!' | '\'' | '(' | ')' | '*'))
        .collect()
}

fn get_mixin_key(origin: &str) -> String {
    const TAB: [usize; 64] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43,
        5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16,
        24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59,
        6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ];

    let bytes = origin.as_bytes();
    let mut out = String::with_capacity(32);
    for idx in TAB {
        if idx < bytes.len() {
            out.push(bytes[idx] as char);
        }
    }
    out.chars().take(32).collect()
}
