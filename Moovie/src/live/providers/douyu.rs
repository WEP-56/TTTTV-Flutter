use async_trait::async_trait;
use md5::{Digest, Md5};
use rquickjs::function::Func;
use rquickjs::{Context, Runtime};
use serde_json::Value;

use super::super::models::{LivePlayQuality, LivePlayUrl, LiveRoomDetail, LiveRoomItem};
use super::LiveProvider;
use crate::utils::error::{MoovieError, Result};

pub struct DouyuProvider {
    client: reqwest::Client,
}

impl DouyuProvider {
    pub fn new(client: reqwest::Client) -> Self {
        Self { client }
    }

    fn user_agent() -> &'static str {
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    }

    fn parse_hot_num(s: &str) -> i64 {
        let s = s.trim();
        if s.is_empty() {
            return 0;
        }
        let is_wan = s.contains('万');
        let num_str = s.replace('万', "");
        if let Ok(mut num) = num_str.parse::<f64>() {
            if is_wan {
                num *= 10000.0;
            }
            return num.round() as i64;
        }
        s.parse::<i64>().unwrap_or(0)
    }

    fn random_hex(len: usize) -> String {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        (0..len)
            .map(|_| format!("{:x}", rng.gen_range(0..16)))
            .collect()
    }

    fn html_unescape(input: &str) -> String {
        input
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
    }

    async fn get_home_h5_enc(&self, room_id: &str) -> Result<String> {
        let json = self
            .client
            .get("https://www.douyu.com/swf_api/homeH5Enc")
            .query(&[("rids", room_id)])
            .header("user-agent", Self::user_agent())
            .header("referer", format!("https://www.douyu.com/{}", room_id))
            .send()
            .await?
            .json::<Value>()
            .await?;

        if json["error"].as_i64().unwrap_or(0) != 0 {
            return Err(MoovieError::DetailError(
                json["msg"]
                    .as_str()
                    .unwrap_or("斗鱼签名脚本获取失败")
                    .to_string(),
            ));
        }

        let key = format!("room{}", room_id);
        let enc = json["data"][key].as_str().unwrap_or("").to_string();
        if enc.trim().is_empty() {
            return Err(MoovieError::DetailError("斗鱼签名脚本为空".to_string()));
        }
        Ok(enc)
    }

    fn compute_sign(&self, enc_js: &str, room_id: &str) -> Result<String> {
        let rt = Runtime::new().map_err(|e| MoovieError::Unknown(e.to_string()))?;
        let ctx = Context::full(&rt).map_err(|e| MoovieError::Unknown(e.to_string()))?;

        let did = "10000000000000000000000000001501";
        let tt = chrono::Utc::now().timestamp();

        ctx.with(|ctx| {
            let globals = ctx.globals();
            globals
                .set(
                    "__moovie_md5",
                    Func::from(|input: String| {
                        let mut hasher = Md5::new();
                        hasher.update(input.as_bytes());
                        format!("{:x}", hasher.finalize())
                    }),
                )
                .map_err(|e| MoovieError::Unknown(e.to_string()))?;

            // Some enc scripts used to depend on CryptoJS.MD5. Provide a minimal stub.
            ctx.eval::<(), _>(
                r#"
                var CryptoJS = {
                  MD5: function(s){
                    return { toString: function(){ return __moovie_md5(String(s)); } };
                  }
                };
                "#,
            )
            .map_err(|e| MoovieError::Unknown(e.to_string()))?;

            ctx.eval::<(), _>(enc_js)
                .map_err(|e| MoovieError::Unknown(format!("斗鱼签名脚本执行失败: {}", e)))?;

            let expr = format!("ub98484234('{}','{}','{}')", room_id, did, tt);
            let sign: String = ctx
                .eval::<String, _>(expr)
                .map_err(|e| MoovieError::Unknown(format!("斗鱼签名计算失败: {}", e)))?;

            if sign.trim().is_empty() {
                return Err(MoovieError::DetailError("斗鱼签名为空".to_string()));
            }
            Ok(sign)
        })
    }

    async fn post_h5_play(&self, room_id: &str, args: &str) -> Result<Value> {
        let json = self
            .client
            .post(format!(
                "https://www.douyu.com/lapi/live/getH5Play/{}",
                room_id
            ))
            .header("user-agent", Self::user_agent())
            .header("referer", format!("https://www.douyu.com/{}", room_id))
            .header("content-type", "application/x-www-form-urlencoded")
            .body(args.to_string())
            .send()
            .await?
            .json::<Value>()
            .await?;

        if json["error"].as_i64().unwrap_or(0) != 0 {
            return Err(MoovieError::DetailError(
                json["msg"]
                    .as_str()
                    .unwrap_or("斗鱼播放地址获取失败")
                    .to_string(),
            ));
        }
        Ok(json)
    }

    fn parse_cdns(json: &Value) -> Vec<String> {
        let mut cdns = Vec::new();
        if let Some(arr) = json["data"]["cdnsWithName"].as_array() {
            for item in arr {
                let cdn = item["cdn"].as_str().unwrap_or("").trim().to_string();
                if !cdn.is_empty() {
                    cdns.push(cdn);
                }
            }
        }

        // put scdn at the end
        cdns.sort_by(|a, b| {
            let a_s = a.starts_with("scdn");
            let b_s = b.starts_with("scdn");
            a_s.cmp(&b_s)
        });

        cdns.dedup();
        cdns
    }

    fn collect_play_urls(json: &Value) -> Vec<String> {
        let mut out = Vec::new();
        let data = &json["data"];

        // Prefer the explicit HLS fields if present.
        let hls_url = data["hls_url"].as_str().unwrap_or("").trim();
        let hls_live = data["hls_live"].as_str().unwrap_or("").trim();
        if !hls_url.is_empty() && !hls_live.is_empty() {
            let live = Self::html_unescape(hls_live);
            let base_url = if hls_url.ends_with('/') {
                format!("{}{}", hls_url, live)
            } else {
                format!("{}/{}", hls_url, live)
            };
            out.push(base_url);
        }

        let rtmp_url = data["rtmp_url"].as_str().unwrap_or("").trim();
        let rtmp_live = data["rtmp_live"].as_str().unwrap_or("").trim();

        if !rtmp_url.is_empty() && !rtmp_live.is_empty() {
            let live = Self::html_unescape(rtmp_live);
            let base_url = if rtmp_url.ends_with('/') {
                format!("{}{}", rtmp_url, live)
            } else {
                format!("{}/{}", rtmp_url, live)
            };

            // Douyu H5 API typically returns HTTP-FLV; keep it and let the frontend player handle FLV via MSE.

            // 只添加原始 URL，不生成变体
            out.push(base_url);
        }

        out.dedup();
        out
    }
}

#[async_trait]
impl LiveProvider for DouyuProvider {
    fn id(&self) -> &'static str {
        "douyu"
    }

    fn name(&self) -> &'static str {
        "斗鱼"
    }

    async fn recommend_rooms(&self, page: i32) -> Result<Vec<LiveRoomItem>> {
        let page = if page <= 0 { 1 } else { page };
        let url = format!(
            "https://www.douyu.com/japi/weblist/apinc/allpage/6/{}",
            page
        );
        let json = self
            .client
            .get(url)
            .header("user-agent", Self::user_agent())
            .header("referer", "https://www.douyu.com/")
            .send()
            .await?
            .json::<Value>()
            .await?;

        if json["error"].as_i64().unwrap_or(0) != 0 {
            return Err(MoovieError::SourceSearchError(
                json["msg"]
                    .as_str()
                    .unwrap_or("斗鱼推荐获取失败")
                    .to_string(),
            ));
        }

        let mut items = Vec::new();
        let list = json["data"]["rl"].as_array().cloned().unwrap_or_default();
        for item in list {
            if item["type"].as_i64().unwrap_or(1) != 1 {
                continue;
            }
            items.push(LiveRoomItem {
                platform: self.id().to_string(),
                room_id: item["rid"].as_i64().unwrap_or(0).to_string(),
                title: item["rn"].as_str().unwrap_or("").to_string(),
                cover: item["rs16"].as_str().unwrap_or("").to_string(),
                user_name: item["nn"].as_str().unwrap_or("").to_string(),
                online: item["ol"].as_i64().unwrap_or(0),
            });
        }

        Ok(items)
    }

    async fn search_rooms(&self, keyword: &str, page: i32) -> Result<Vec<LiveRoomItem>> {
        if keyword.trim().is_empty() {
            return Ok(Vec::new());
        }
        let page = if page <= 0 { 1 } else { page };

        let did = Self::random_hex(32);
        let json = self
            .client
            .get("https://www.douyu.com/japi/search/api/searchShow")
            .query(&[
                ("kw", keyword),
                ("page", &page.to_string()),
                ("pageSize", "20"),
            ])
            .header("user-agent", Self::user_agent())
            .header("referer", "https://www.douyu.com/search/")
            .header("cookie", format!("dy_did={};acf_did={}", did, did))
            .send()
            .await?
            .json::<Value>()
            .await?;

        if json["error"].as_i64().unwrap_or(0) != 0 {
            return Err(MoovieError::SourceSearchError(
                json["msg"].as_str().unwrap_or("斗鱼搜索失败").to_string(),
            ));
        }

        let mut items = Vec::new();
        let list = json["data"]["relateShow"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        for item in list {
            items.push(LiveRoomItem {
                platform: self.id().to_string(),
                room_id: item["rid"].as_i64().unwrap_or(0).to_string(),
                title: item["roomName"].as_str().unwrap_or("").to_string(),
                cover: item["roomSrc"].as_str().unwrap_or("").to_string(),
                user_name: item["nickName"].as_str().unwrap_or("").to_string(),
                online: Self::parse_hot_num(item["hot"].as_str().unwrap_or("0")),
            });
        }

        Ok(items)
    }

    async fn room_detail(&self, room_id: &str) -> Result<LiveRoomDetail> {
        let room_id = room_id.trim();
        if room_id.is_empty() {
            return Err(MoovieError::InvalidParameter(
                "room_id 不能为空".to_string(),
            ));
        }

        let room_text = self
            .client
            .get(format!("https://www.douyu.com/betard/{}", room_id))
            .header("user-agent", Self::user_agent())
            .header("referer", format!("https://www.douyu.com/{}", room_id))
            .send()
            .await?
            .text()
            .await?;

        let parsed: Value = serde_json::from_str(&room_text)
            .map_err(|e| MoovieError::DetailError(format!("斗鱼房间信息解析失败: {}", e)))?;

        let room_obj = if parsed.is_object() {
            parsed.get("room").cloned().unwrap_or(Value::Null)
        } else if let Some(inner) = parsed.as_str() {
            let parsed2: Value = serde_json::from_str(inner)
                .map_err(|e| MoovieError::DetailError(format!("斗鱼房间信息解析失败: {}", e)))?;
            parsed2.get("room").cloned().unwrap_or(Value::Null)
        } else {
            Value::Null
        };

        if room_obj.is_null() {
            return Err(MoovieError::DetailError("斗鱼房间信息解析失败".to_string()));
        }

        let h5_json = self
            .client
            .get(format!("https://www.douyu.com/swf_api/h5room/{}", room_id))
            .header("user-agent", Self::user_agent())
            .header("referer", format!("https://www.douyu.com/{}", room_id))
            .send()
            .await?
            .json::<Value>()
            .await?;
        let show_time = h5_json["data"]["show_time"]
            .as_str()
            .map(|s| s.to_string())
            .filter(|s| !s.trim().is_empty());

        let room_real_id = room_obj["room_id"]
            .as_str()
            .map(|s| s.to_string())
            .unwrap_or_else(|| room_id.to_string());

        let online = room_obj["room_biz_all"]["hot"]
            .as_i64()
            .or_else(|| {
                room_obj["room_biz_all"]["hot"]
                    .as_str()
                    .map(|s| Self::parse_hot_num(s))
            })
            .unwrap_or(0);

        let show_status = room_obj["show_status"].as_i64().unwrap_or(0) == 1;
        let is_record = room_obj["videoLoop"].as_i64().unwrap_or(0) == 1;
        let status = show_status && !is_record;

        Ok(LiveRoomDetail {
            platform: self.id().to_string(),
            room_id: room_real_id.clone(),
            title: room_obj["room_name"].as_str().unwrap_or("").to_string(),
            cover: room_obj["room_pic"].as_str().unwrap_or("").to_string(),
            user_name: room_obj["owner_name"].as_str().unwrap_or("").to_string(),
            user_avatar: room_obj["owner_avatar"].as_str().unwrap_or("").to_string(),
            online,
            introduction: room_obj["show_details"]
                .as_str()
                .map(|s| s.to_string())
                .filter(|s| !s.trim().is_empty()),
            notice: None,
            status,
            is_record,
            url: format!("https://www.douyu.com/{}", room_real_id),
            show_time,
        })
    }

    async fn play_qualities(&self, room_id: &str) -> Result<Vec<LivePlayQuality>> {
        let detail = self.room_detail(room_id).await?;
        if !detail.status {
            return Err(MoovieError::InvalidParameter("直播间未开播".to_string()));
        }

        let enc_js = self.get_home_h5_enc(&detail.room_id).await?;
        let sign = self.compute_sign(&enc_js, &detail.room_id)?;

        let args = format!(
            "{}&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0",
            sign
        );
        let json = self.post_h5_play(&detail.room_id, &args).await?;

        let mut qualities = Vec::new();
        if let Some(arr) = json["data"]["multirates"].as_array() {
            for item in arr {
                let rate = item["rate"]
                    .as_i64()
                    .or_else(|| item["rate"].as_str().and_then(|s| s.parse().ok()))
                    .unwrap_or(-1);
                if rate < 0 {
                    continue;
                }
                let name = item["name"].as_str().unwrap_or("未知清晰度").to_string();
                qualities.push(LivePlayQuality {
                    id: rate.to_string(),
                    name,
                    // Douyu uses rate=0 to represent the highest/original quality.
                    sort: if rate == 0 { i32::MAX } else { rate as i32 },
                });
            }
        }

        qualities.sort_by(|a, b| b.sort.cmp(&a.sort));
        Ok(qualities)
    }

    async fn play_urls(&self, room_id: &str, quality_id: &str) -> Result<LivePlayUrl> {
        let detail = self.room_detail(room_id).await?;
        if !detail.status {
            return Err(MoovieError::InvalidParameter("直播间未开播".to_string()));
        }

        let enc_js = self.get_home_h5_enc(&detail.room_id).await?;
        let sign = self.compute_sign(&enc_js, &detail.room_id)?;

        // First request: get available cdns
        let meta_args = format!(
            "{}&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0",
            sign
        );
        let meta = self.post_h5_play(&detail.room_id, &meta_args).await?;
        let mut cdns = Self::parse_cdns(&meta);
        // Some rooms return only one CDN. Probe a few common CDNs to offer fallback lines.
        for cdn in ["ws-h5", "tct-h5", "ali-h5", "hs-h5"] {
            if !cdns.iter().any(|c| c == cdn) {
                cdns.push(cdn.to_string());
            }
        }

        let mut urls = Vec::new();
        for cdn in cdns {
            let args = format!(
                "{}&cdn={}&rate={}&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0",
                sign, cdn, quality_id
            );
            match self.post_h5_play(&detail.room_id, &args).await {
                Ok(json) => urls.extend(Self::collect_play_urls(&json)),
                Err(_) => continue,
            }
        }

        if urls.is_empty() {
            return Err(MoovieError::DetailError("斗鱼未获取到播放地址".to_string()));
        }

        urls.sort();
        urls.dedup();

        Ok(LivePlayUrl {
            urls,
            headers: None,
            url_type: Some("auto".to_string()),
            expires_at: None,
        })
    }
}
