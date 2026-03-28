use async_trait::async_trait;
use base64::Engine;
use md5::{Digest, Md5};
use regex::Regex;
use serde_json::Value;
use std::collections::HashMap;

use super::super::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail, LiveRoomItem};
use super::LiveProvider;
use crate::utils::error::{MoovieError, Result};

pub struct HuyaProvider {
    client: reqwest::Client,
}

#[derive(Debug, Clone)]
pub(crate) struct HuyaDanmakuArgs {
    pub ayyuid: i64,
    pub top_sid: i64,
    pub sub_sid: i64,
}

#[derive(Debug, Clone)]
struct HuyaStreamLine {
    base_url: String,
    stream_name: String,
    anticode: String,
    is_hls: bool,
}

impl HuyaProvider {
    pub fn new(client: reqwest::Client) -> Self {
        Self { client }
    }

    fn user_agent() -> &'static str {
        // mimic a mobile UA similar to sample project
        "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36"
    }

    fn play_user_agent() -> &'static str {
        // from dart_simple_live (HuyaSite.HYSDK_UA)
        "HYSDK(Windows, 30000002)_APP(pc_exe&7060000&official)_SDK(trans&2.32.3.5646)"
    }

    fn gen_numeric_uid(len: usize) -> String {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        (0..len)
            .map(|_| char::from(b'0' + (rng.gen_range(0..10) as u8)))
            .collect()
    }

    fn gen_uuid() -> String {
        // from dart_simple_live (HuyaSite.getUUid)
        use rand::Rng;
        let current_time = chrono::Utc::now().timestamp_millis() as u64;
        let random_value: u64 = rand::thread_rng().gen_range(0..=0xffffffff);
        let result = ((current_time % 10_000_000_000) * 1000 + random_value) % 0xffffffff;
        result.to_string()
    }

    fn normalize_line_url(url: &str) -> String {
        let u = url.trim();
        if u.starts_with("//") {
            return format!("https:{}", u);
        }
        if u.starts_with("http://") || u.starts_with("https://") {
            return u.to_string();
        }
        // best-effort
        format!("https://{}", u.trim_start_matches('/'))
    }

    fn md5_hex(input: &str) -> String {
        let mut hasher = Md5::new();
        hasher.update(input.as_bytes());
        format!("{:x}", hasher.finalize())
    }

    fn current_millis() -> i64 {
        chrono::Utc::now().timestamp_millis()
    }

    fn process_anticode(anticode: &str, streamname: &str) -> Result<String> {
        // Generate "web" anti-code params (ported from DTV-main). Hardcoded/outdated
        // sv/sdk_sid often results in 403 for stream playlists.
        let sanitized = anticode.replace("&amp;", "&");
        let trimmed = sanitized.trim_start_matches(|c| c == '?' || c == '&');
        let params: HashMap<String, String> = url::form_urlencoded::parse(trimmed.as_bytes())
            .into_owned()
            .collect();

        let fm_raw = params.get("fm").cloned().unwrap_or_default();
        let ctype = params
            .get("ctype")
            .cloned()
            .unwrap_or_else(|| "tars_mobile".to_string());
        let fs = params.get("fs").cloned().unwrap_or_default();
        if fm_raw.trim().is_empty() || fs.trim().is_empty() {
            return Err(MoovieError::DetailError(
                "虎牙 anticode 缺少 fm/fs".to_string(),
            ));
        }

        // Some decoders turn '+' into space; restore it for base64.
        let fm_b64 = fm_raw.replace(' ', "+");
        let fm_bytes = base64::engine::general_purpose::STANDARD
            .decode(fm_b64.as_bytes())
            .map_err(|e| MoovieError::DetailError(format!("虎牙 fm base64 解码失败: {}", e)))?;
        let fm_text = String::from_utf8_lossy(&fm_bytes);
        let ws_secret_prefix = fm_text.split('_').next().unwrap_or("").to_string();
        if ws_secret_prefix.trim().is_empty() {
            return Err(MoovieError::DetailError(
                "虎牙 wsSecretPrefix 为空".to_string(),
            ));
        }

        use rand::Rng;

        let t = 100_i64;
        let sv = 2403051612_i64;
        let t13 = Self::current_millis();
        let sdk_sid = t13;

        let mut rng = rand::thread_rng();
        let u = rng.gen_range(1_400_000_000_000_i64..=1_400_009_999_999_i64);
        let seq_id = u + sdk_sid;

        let ws_time = format!("{:x}", (t13 + 110_624) / 1000);

        let uuid_seed = (t13 % 10_000_000_000_i64) * 1000 + rng.gen_range(0_i64..1_000_i64);
        let uuid = uuid_seed % 4_294_967_295_i64;

        let ws_secret_hash = Self::md5_hex(&format!("{}|{}|{}", seq_id, ctype, t));
        let ws_secret = Self::md5_hex(&format!(
            "{}_{}_{}_{}_{}",
            ws_secret_prefix, u, streamname, ws_secret_hash, ws_time
        ));

        let pairs = [
            ("wsSecret", ws_secret),
            ("wsTime", ws_time),
            ("seqid", seq_id.to_string()),
            ("ctype", ctype),
            ("ver", "1".to_string()),
            ("fs", fs),
            ("uuid", uuid.to_string()),
            ("u", u.to_string()),
            ("t", t.to_string()),
            ("sv", sv.to_string()),
            ("sdk_sid", sdk_sid.to_string()),
            ("codec", "264".to_string()),
        ];

        Ok(pairs
            .iter()
            .map(|(k, v)| format!("{}={}", k, urlencoding::encode(v)))
            .collect::<Vec<_>>()
            .join("&"))
    }

    async fn get_room_info_raw(&self, room_id: &str) -> Result<(Value, i64, i64)> {
        let html = self
            .client
            .get(format!("https://m.huya.com/{}", room_id))
            .header("user-agent", Self::user_agent())
            .send()
            .await?
            .text()
            .await?;

        let idx = html
            .find("window.HNF_GLOBAL_INIT")
            .ok_or_else(|| MoovieError::DetailError("虎牙房间页面解析失败".to_string()))?;
        let after = &html[idx..];
        let brace_idx = after
            .find('{')
            .ok_or_else(|| MoovieError::DetailError("虎牙房间页面解析失败".to_string()))?;
        let json_start = idx + brace_idx;
        let end_tag = html[json_start..]
            .find("</script>")
            .ok_or_else(|| MoovieError::DetailError("虎牙房间页面解析失败".to_string()))?;
        let json_end = json_start + end_tag;
        let mut json_text = html[json_start..json_end].trim().to_string();
        if json_text.ends_with(';') {
            json_text.pop();
        }

        // remove function bodies that break JSON parsing
        let func_re = Regex::new(r"function.*?\(.*?\).*?\{[\s\S]*?\}")
            .map_err(|e| MoovieError::ConfigError(e.to_string()))?;
        json_text = func_re.replace_all(&json_text, "\"\"").to_string();

        let obj: Value = serde_json::from_str(&json_text)
            .map_err(|e| MoovieError::DetailError(format!("虎牙房间 JSON 解析失败: {}", e)))?;

        let top_re = Regex::new(r#"lChannelId":([0-9]+)"#)
            .map_err(|e| MoovieError::ConfigError(e.to_string()))?;
        let sub_re = Regex::new(r#"lSubChannelId":([0-9]+)"#)
            .map_err(|e| MoovieError::ConfigError(e.to_string()))?;
        let top_sid = top_re
            .captures(&html)
            .and_then(|c| c.get(1))
            .and_then(|m| m.as_str().parse::<i64>().ok())
            .unwrap_or(0);
        let sub_sid = sub_re
            .captures(&html)
            .and_then(|c| c.get(1))
            .and_then(|m| m.as_str().parse::<i64>().ok())
            .unwrap_or(0);

        Ok((obj, top_sid, sub_sid))
    }

    pub(crate) async fn get_danmaku_args(&self, room_id: &str) -> Result<HuyaDanmakuArgs> {
        let (obj, top_sid, sub_sid) = self.get_room_info_raw(room_id).await?;
        let ayyuid = obj["roomInfo"]["tLiveInfo"]["lYyid"]
            .as_i64()
            .or_else(|| obj["roomInfo"]["tProfileInfo"]["lYyid"].as_i64())
            .unwrap_or(0);

        Ok(HuyaDanmakuArgs {
            ayyuid,
            top_sid,
            sub_sid,
        })
    }

    fn parse_stream_lines(obj: &Value) -> Vec<HuyaStreamLine> {
        let mut out = Vec::new();
        let lines = obj["roomInfo"]["tLiveInfo"]["tLiveStreamInfo"]["vStreamInfo"]["value"]
            .as_array()
            .cloned()
            .unwrap_or_default();

        for item in lines {
            let stream_name = item["sStreamName"]
                .as_str()
                .unwrap_or("")
                .trim()
                .to_string();
            if stream_name.is_empty() {
                continue;
            }

            // Prefer HLS if present
            let hls_url = item["sHlsUrl"].as_str().unwrap_or("").trim().to_string();
            let hls_code = item["sHlsAntiCode"]
                .as_str()
                .unwrap_or("")
                .trim()
                .to_string();
            if !hls_url.is_empty() && !hls_code.is_empty() {
                out.push(HuyaStreamLine {
                    base_url: hls_url,
                    stream_name: stream_name.clone(),
                    anticode: hls_code,
                    is_hls: true,
                });
            }

            let flv_url = item["sFlvUrl"].as_str().unwrap_or("").trim().to_string();
            let flv_code = item["sFlvAntiCode"]
                .as_str()
                .unwrap_or("")
                .trim()
                .to_string();
            if !flv_url.is_empty() && !flv_code.is_empty() {
                out.push(HuyaStreamLine {
                    base_url: flv_url,
                    stream_name: stream_name.clone(),
                    anticode: flv_code,
                    is_hls: false,
                });
            }
        }

        out
    }
}

#[async_trait]
impl LiveProvider for HuyaProvider {
    fn id(&self) -> &'static str {
        "huya"
    }

    fn name(&self) -> &'static str {
        "虎牙"
    }

    async fn recommend_rooms(&self, page: i32) -> Result<Vec<LiveRoomItem>> {
        let page = if page <= 0 { 1 } else { page };
        let text = self
            .client
            .get("https://www.huya.com/cache.php")
            .query(&[
                ("m", "LiveList"),
                ("do", "getLiveListByPage"),
                ("tagAll", "0"),
                ("page", &page.to_string()),
            ])
            .header("user-agent", Self::user_agent())
            .send()
            .await?
            .text()
            .await?;

        let json: Value = serde_json::from_str(&text)
            .map_err(|e| MoovieError::SourceSearchError(format!("虎牙推荐解析失败: {}", e)))?;

        let mut items = Vec::new();
        let list = json["data"]["datas"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        for item in list {
            let mut cover = item["screenshot"].as_str().unwrap_or("").to_string();
            if !cover.contains('?') {
                cover.push_str("?x-oss-process=style/w338_h190&");
            }
            let mut title = item["introduction"].as_str().unwrap_or("").to_string();
            if title.trim().is_empty() {
                title = item["roomName"].as_str().unwrap_or("").to_string();
            }

            let profile_room = item["profileRoom"]
                .as_i64()
                .or_else(|| item["profileRoom"].as_str().and_then(|s| s.parse().ok()))
                .filter(|&id| id > 0)
                .map(|id| id.to_string())
                .or_else(|| {
                    item["privateHost"]
                        .as_str()
                        .map(|s| s.to_string())
                        .filter(|s| !s.is_empty())
                });

            if let Some(room_id) = profile_room {
                items.push(LiveRoomItem {
                    platform: self.id().to_string(),
                    room_id,
                    title,
                    cover,
                    user_name: item["nick"].as_str().unwrap_or("").to_string(),
                    online: item["totalCount"]
                        .as_i64()
                        .or_else(|| item["totalCount"].as_str().and_then(|s| s.parse().ok()))
                        .unwrap_or(0),
                });
            }
        }

        Ok(items)
    }

    async fn search_rooms(&self, keyword: &str, page: i32) -> Result<Vec<LiveRoomItem>> {
        if keyword.trim().is_empty() {
            return Ok(Vec::new());
        }
        let page = if page <= 0 { 1 } else { page };
        let start = (page - 1) * 20;

        let text = self
            .client
            .get("https://search.cdn.huya.com/")
            .query(&[
                ("m", "Search"),
                ("do", "getSearchContent"),
                ("q", keyword),
                ("uid", "0"),
                ("v", "4"),
                ("typ", "-5"),
                ("livestate", "0"),
                ("rows", "20"),
                ("start", &start.to_string()),
            ])
            .header("user-agent", Self::user_agent())
            .send()
            .await?
            .text()
            .await?;

        let json: Value = serde_json::from_str(&text)
            .map_err(|e| MoovieError::SourceSearchError(format!("虎牙搜索解析失败: {}", e)))?;

        let mut items = Vec::new();
        let docs = json["response"]["3"]["docs"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        for item in docs {
            let mut cover = item["game_screenshot"].as_str().unwrap_or("").to_string();
            if !cover.contains('?') {
                cover.push_str("?x-oss-process=style/w338_h190&");
            }
            let mut title = item["game_introduction"].as_str().unwrap_or("").to_string();
            if title.trim().is_empty() {
                title = item["game_roomName"].as_str().unwrap_or("").to_string();
            }

            let room_id = item["room_id"]
                .as_i64()
                .or_else(|| item["room_id"].as_str().and_then(|s| s.parse().ok()))
                .filter(|&id| id > 0)
                .map(|id| id.to_string());

            if let Some(room_id) = room_id {
                items.push(LiveRoomItem {
                    platform: self.id().to_string(),
                    room_id,
                    title,
                    cover,
                    user_name: item["game_nick"].as_str().unwrap_or("").to_string(),
                    online: item["game_total_count"]
                        .as_i64()
                        .or_else(|| {
                            item["game_total_count"]
                                .as_str()
                                .and_then(|s| s.parse().ok())
                        })
                        .unwrap_or(0),
                });
            }
        }

        Ok(items)
    }

    async fn room_detail(&self, room_id: &str) -> Result<LiveRoomDetail> {
        let (obj, _top_sid, _sub_sid) = self.get_room_info_raw(room_id).await?;

        let t_live = &obj["roomInfo"]["tLiveInfo"];
        let t_profile = &obj["roomInfo"]["tProfileInfo"];

        let mut title = t_live["sIntroduction"].as_str().unwrap_or("").to_string();
        if title.trim().is_empty() {
            title = t_live["sRoomName"].as_str().unwrap_or("").to_string();
        }

        let cover = t_live["sScreenshot"].as_str().unwrap_or("").to_string();
        let online = t_live["lTotalCount"]
            .as_i64()
            .or_else(|| t_live["lTotalCount"].as_str().and_then(|s| s.parse().ok()))
            .unwrap_or(0);

        let profile_room = t_live["lProfileRoom"]
            .as_i64()
            .or_else(|| t_live["lProfileRoom"].as_str().and_then(|s| s.parse().ok()))
            .filter(|&id| id > 0)
            .map(|id| id.to_string())
            .unwrap_or_else(|| room_id.to_string());

        let user_name = t_profile["sNick"].as_str().unwrap_or("").to_string();
        let user_avatar = t_profile["sAvatar180"].as_str().unwrap_or("").to_string();
        let notice = obj["welcomeText"]
            .as_str()
            .map(|s| s.to_string())
            .filter(|s| !s.trim().is_empty());
        let introduction = t_live["sIntroduction"]
            .as_str()
            .map(|s| s.to_string())
            .filter(|s| !s.trim().is_empty());
        let status = obj["roomInfo"]["eLiveStatus"].as_i64().unwrap_or(0) == 2;

        Ok(LiveRoomDetail {
            platform: self.id().to_string(),
            room_id: profile_room.clone(),
            title,
            cover,
            user_name,
            user_avatar,
            online,
            introduction,
            notice,
            status,
            is_record: false,
            url: format!("https://www.huya.com/{}", room_id),
            show_time: None,
        })
    }

    async fn play_qualities(&self, _room_id: &str) -> Result<Vec<LivePlayQuality>> {
        let (obj, _top_sid, _sub_sid) = self.get_room_info_raw(_room_id).await?;
        let mut qualities = Vec::new();

        let list = obj["roomInfo"]["tLiveInfo"]["tLiveStreamInfo"]["vBitRateInfo"]["value"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        for item in list {
            let name = item["sDisplayName"].as_str().unwrap_or("").to_string();
            if name.contains("HDR") {
                continue;
            }
            let bit_rate = item["iBitRate"]
                .as_i64()
                .or_else(|| item["iBitRate"].as_str().and_then(|s| s.parse().ok()))
                .unwrap_or(0);
            qualities.push(LivePlayQuality {
                id: bit_rate.to_string(),
                name: if name.trim().is_empty() {
                    "原画".to_string()
                } else {
                    name
                },
                sort: bit_rate as i32,
            });
        }

        if qualities.is_empty() {
            qualities.push(LivePlayQuality {
                id: "0".to_string(),
                name: "原画".to_string(),
                sort: 0,
            });
            qualities.push(LivePlayQuality {
                id: "2000".to_string(),
                name: "高清".to_string(),
                sort: 2000,
            });
        }

        qualities.sort_by(|a, b| b.sort.cmp(&a.sort));
        Ok(qualities)
    }

    async fn play_urls(&self, _room_id: &str, _quality_id: &str) -> Result<LivePlayUrl> {
        let (obj, _top_sid, _sub_sid) = self.get_room_info_raw(_room_id).await?;

        let ratio = _quality_id.parse::<i32>().unwrap_or(0);

        let mut urls = Vec::new();
        let lines = Self::parse_stream_lines(&obj);
        for line in lines {
            let anti = Self::process_anticode(&line.anticode, &line.stream_name)?;
            let base = Self::normalize_line_url(&line.base_url);
            let ext = if line.is_hls { "m3u8" } else { "flv" };
            let mut url = format!(
                "{}/{}.{}?{}",
                base.trim_end_matches('/'),
                line.stream_name,
                ext,
                anti
            );
            if ratio > 0 {
                url.push_str(&format!("&ratio={}", ratio));
            }
            urls.push(url);
        }

        if urls.is_empty() {
            return Err(MoovieError::DetailError("虎牙未获取到播放地址".to_string()));
        }

        urls.sort_by(|a, b| {
            let a_is_m3u8 = a.contains(".m3u8");
            let b_is_m3u8 = b.contains(".m3u8");
            b_is_m3u8.cmp(&a_is_m3u8).then_with(|| a.cmp(b))
        });
        urls.dedup();

        Ok(LivePlayUrl {
            urls,
            headers: Some(HashMap::from([(
                "user-agent".to_string(),
                Self::play_user_agent().to_string(),
            )])),
            url_type: Some("auto".to_string()),
            expires_at: None,
        })
    }
}
