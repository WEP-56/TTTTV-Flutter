use axum::extract::ws::{Message as AxumMessage, WebSocket};
use flate2::read::GzDecoder;
use futures::{SinkExt, StreamExt};
use md5::{Digest, Md5};
use prost::Message as ProstMessage;
use rquickjs::{Context, Runtime};
use std::collections::HashMap;
use std::io::Read;
use std::time::Duration;
use tokio::sync::{mpsc, watch};
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::{client::IntoClientRequest, Message as WsMessage};
use url::Url;

use crate::live::models::{LiveMessage, LiveMessageColor, LiveMessageType};
use crate::live::providers::douyin::DouyinProvider;
use crate::utils::error::MoovieError;

#[path = "douyin/generated.rs"]
mod generated;

use generated::{ChatMessage, PushFrame, Response};

const SIGN_JS: &str = include_str!("douyin/sign.js");

pub async fn bridge(
    http_client: reqwest::Client,
    cookie: String,
    web_rid: String,
    socket: WebSocket,
) -> Result<(), MoovieError> {
    let merged_cookie = collect_cookies(&http_client, &cookie).await?;
    let provider = DouyinProvider::new(http_client.clone(), merged_cookie.clone());
    let room_data = provider.get_room_data_by_api(&web_rid).await?;
    let room = room_data["data"]
        .as_array()
        .and_then(|arr| arr.first())
        .cloned()
        .ok_or_else(|| MoovieError::DetailError("抖音房间信息解析失败".to_string()))?;
    let actual_room_id = room["id_str"]
        .as_str()
        .or_else(|| room["id"].as_str())
        .map(|value| value.to_string())
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| MoovieError::DetailError("抖音房间号为空".to_string()))?;

    let user_unique_id = extract_cookie_value(&merged_cookie, "s_v_web_id")
        .or_else(|| extract_cookie_value(&merged_cookie, "ttwid"))
        .unwrap_or_else(|| chrono::Utc::now().timestamp_millis().to_string());

    let current_timestamp_ms = chrono::Utc::now().timestamp_millis();
    let first_req_ms = current_timestamp_ms - 100;
    let cursor = format!(
        "d-1_u-1_fh-7392091211001140287_t-{}_r-1",
        current_timestamp_ms
    );
    let internal_ext = format!(
        "internal_src:dim|wss_push_room_id:{}|wss_push_did:{}|first_req_ms:{}|fetch_time:{}|seq:1|wss_info:0-{}-0-0|wrds_v:7392094459690748497",
        actual_room_id, user_unique_id, first_req_ms, current_timestamp_ms, current_timestamp_ms
    );

    let unsigned_wss_url = format!(
        "wss://webcast5-ws-web-hl.douyin.com/webcast/im/push/v2/?app_name=douyin_web&version_code=180800&webcast_sdk_version=1.0.14-beta.0&update_version_code=1.0.14-beta.0&compress=gzip&device_platform=web&cookie_enabled=true&screen_width=1536&screen_height=864&browser_language=zh-CN&browser_platform=Win32&browser_name=Mozilla&browser_version={}&browser_online=true&tz_name=Asia/Shanghai&cursor={}&internal_ext={}&host=https://live.douyin.com&aid=6383&live_id=1&did_rule=3&endpoint=live_pc&support_wrds=1&user_unique_id={}&im_path=/webcast/im/fetch/&identity=audience&need_persist_msg_count=15&insert_task_id=&live_reason=&room_id={}&heartbeatDuration=0",
        urlencoding::encode(DouyinProvider::default_user_agent()),
        cursor,
        urlencoding::encode(&internal_ext),
        user_unique_id,
        actual_room_id
    );
    let signature = generate_signature(&unsigned_wss_url)?;
    let ws_url = format!("{}&signature={}", unsigned_wss_url, signature);

    let mut request = ws_url.into_client_request().map_err(|e| {
        MoovieError::InvalidParameter(format!("抖音弹幕 ws url 解析失败: {}", e))
    })?;
    let headers = request.headers_mut();
    headers.insert(
        "accept",
        "application/json, text/plain, */*"
            .parse()
            .map_err(|_| MoovieError::InvalidParameter("accept header 无效".to_string()))?,
    );
    headers.insert(
        "accept-language",
        "zh-CN,zh;q=0.9,en;q=0.8"
            .parse()
            .map_err(|_| MoovieError::InvalidParameter("accept-language header 无效".to_string()))?,
    );
    headers.insert(
        "cache-control",
        "no-cache"
            .parse()
            .map_err(|_| MoovieError::InvalidParameter("cache-control header 无效".to_string()))?,
    );
    headers.insert(
        "pragma",
        "no-cache"
            .parse()
            .map_err(|_| MoovieError::InvalidParameter("pragma header 无效".to_string()))?,
    );
    headers.insert(
        "sec-websocket-extensions",
        "permessage-deflate; client_max_window_bits"
            .parse()
            .map_err(|_| MoovieError::InvalidParameter("sec-websocket-extensions header 无效".to_string()))?,
    );
    headers.insert(
        "user-agent",
        DouyinProvider::default_user_agent()
            .parse()
            .map_err(|_| MoovieError::InvalidParameter("user-agent header 无效".to_string()))?,
    );
    headers.insert(
        "cookie",
        merged_cookie
            .parse()
            .map_err(|_| MoovieError::InvalidParameter("cookie header 无效".to_string()))?,
    );

    let (upstream, _resp) = connect_async(request)
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;
    let (mut upstream_write, mut upstream_read) = upstream.split();
    let (mut client_tx, mut client_rx) = socket.split();

    let (ack_tx, mut ack_rx) = mpsc::channel::<WsMessage>(16);
    let (shutdown_tx, mut shutdown_rx) = watch::channel(false);

    let heartbeat_msg = {
        let frame = PushFrame {
            payload_type: "hb".to_string(),
            log_id: 0,
            payload: vec![],
            ..Default::default()
        };
        let mut buf = Vec::new();
        frame.encode(&mut buf)
            .map_err(|e| MoovieError::Unknown(e.to_string()))?;
        WsMessage::Ping(buf)
    };

    let write_task = tokio::spawn(async move {
        let mut ticker = tokio::time::interval(Duration::from_secs(5));
        loop {
            tokio::select! {
                _ = shutdown_rx.changed() => {
                    if *shutdown_rx.borrow() {
                        break;
                    }
                }
                _ = ticker.tick() => {
                    if upstream_write.send(heartbeat_msg.clone()).await.is_err() {
                        break;
                    }
                }
                msg = ack_rx.recv() => {
                    let Some(msg) = msg else { break; };
                    if upstream_write.send(msg).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    loop {
        tokio::select! {
            upstream_msg = upstream_read.next() => {
                let Some(upstream_msg) = upstream_msg else { break; };
                let upstream_msg = match upstream_msg {
                    Ok(msg) => msg,
                    Err(_) => break,
                };

                match upstream_msg {
                    WsMessage::Binary(data) => {
                        for live_msg in decode_push_frame(&data, &ack_tx).await {
                            let text = match serde_json::to_string(&live_msg) {
                                Ok(text) => text,
                                Err(_) => continue,
                            };
                            if client_tx.send(AxumMessage::Text(text)).await.is_err() {
                                let _ = shutdown_tx.send(true);
                                let _ = write_task.await;
                                return Ok(());
                            }
                        }
                    }
                    WsMessage::Ping(payload) => {
                        let _ = ack_tx.send(WsMessage::Pong(payload)).await;
                    }
                    WsMessage::Close(_) => break,
                    _ => {}
                }
            }
            client_msg = client_rx.next() => {
                if client_msg.is_none() {
                    break;
                }
            }
        }
    }

    let _ = shutdown_tx.send(true);
    let _ = write_task.await;
    Ok(())
}

async fn decode_push_frame(
    data: &[u8],
    ack_tx: &mpsc::Sender<WsMessage>,
) -> Vec<LiveMessage> {
    let mut out = Vec::new();
    let Ok(push_frame) = PushFrame::decode(data) else {
        return out;
    };

    if push_frame.payload_type != "msg" || push_frame.payload.is_empty() {
        return out;
    }

    let mut decoder = GzDecoder::new(push_frame.payload.as_slice());
    let mut decompressed = Vec::new();
    if decoder.read_to_end(&mut decompressed).is_err() {
        return out;
    }

    let Ok(response) = Response::decode(decompressed.as_slice()) else {
        return out;
    };

    if response.need_ack {
        let ack = PushFrame {
            log_id: push_frame.log_id,
            payload_type: "ack".to_string(),
            payload: response.internal_ext.as_bytes().to_vec(),
            ..Default::default()
        };
        let mut ack_buf = Vec::new();
        if ack.encode(&mut ack_buf).is_ok() {
            let _ = ack_tx.send(WsMessage::Binary(ack_buf)).await;
        }
    }

    for message in response.messages_list {
        if message.method != "WebcastChatMessage" {
            continue;
        }
        let Ok(chat_message) = ChatMessage::decode(message.payload.as_slice()) else {
            continue;
        };
        let user_name = chat_message
            .user
            .as_ref()
            .map(|user| user.nick_name.clone())
            .unwrap_or_else(|| "抖音用户".to_string());
        let message = chat_message.content.trim().to_string();
        if message.is_empty() {
            continue;
        }

        out.push(LiveMessage {
            kind: LiveMessageType::Chat,
            user_name,
            message,
            color: LiveMessageColor { r: 255, g: 255, b: 255 },
            data: None,
        });
    }

    out
}

async fn collect_cookies(
    http_client: &reqwest::Client,
    stored_cookie: &str,
) -> Result<String, MoovieError> {
    let mut cookie_map = parse_cookie_map(stored_cookie);

    for method in ["HEAD", "GET"] {
        let mut req = match method {
            "HEAD" => http_client.head("https://live.douyin.com"),
            _ => http_client.get("https://live.douyin.com"),
        };
        req = req
            .header("user-agent", DouyinProvider::default_user_agent())
            .header("referer", "https://live.douyin.com");

        if !stored_cookie.trim().is_empty() {
            req = req.header("cookie", stored_cookie.trim());
        }

        let resp = req.send().await?;
        for value in resp.headers().get_all(reqwest::header::SET_COOKIE).iter() {
            let Ok(value) = value.to_str() else { continue; };
            let pair = value.split(';').next().unwrap_or("").trim();
            let mut segments = pair.splitn(2, '=');
            let Some(name) = segments.next().map(|value| value.trim()) else { continue; };
            let Some(val) = segments.next().map(|value| value.trim()) else { continue; };
            if matches!(name, "ttwid" | "__ac_nonce" | "msToken" | "s_v_web_id" | "tt_scid") {
                cookie_map.insert(name.to_string(), val.to_string());
            }
        }
    }

    if cookie_map.is_empty() {
        return Err(MoovieError::DetailError("抖音 Cookie 获取失败".to_string()));
    }

    Ok(cookie_map
        .into_iter()
        .map(|(key, value)| format!("{}={}", key, value))
        .collect::<Vec<_>>()
        .join("; "))
}

fn parse_cookie_map(cookie: &str) -> HashMap<String, String> {
    cookie
        .split(';')
        .filter_map(|part| {
            let part = part.trim();
            let mut segments = part.splitn(2, '=');
            let key = segments.next()?.trim();
            let value = segments.next()?.trim();
            if key.is_empty() || value.is_empty() {
                return None;
            }
            Some((key.to_string(), value.to_string()))
        })
        .collect()
}

fn extract_cookie_value(cookie: &str, name: &str) -> Option<String> {
    parse_cookie_map(cookie).remove(name)
}

fn generate_signature(wss_url: &str) -> Result<String, MoovieError> {
    let parsed_url = Url::parse(wss_url)
        .map_err(|e| MoovieError::InvalidParameter(format!("抖音 ws url 解析失败: {}", e)))?;
    let params_to_sign_keys = [
        "live_id",
        "aid",
        "version_code",
        "webcast_sdk_version",
        "room_id",
        "sub_room_id",
        "sub_channel_id",
        "did_rule",
        "user_unique_id",
        "device_platform",
        "device_type",
        "ac",
        "identity",
    ];

    let query_map: HashMap<String, String> = parsed_url
        .query_pairs()
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect();
    let to_sign = params_to_sign_keys
        .iter()
        .map(|key| format!("{}={}", key, query_map.get(*key).cloned().unwrap_or_default()))
        .collect::<Vec<_>>()
        .join(",");

    let mut hasher = Md5::new();
    hasher.update(to_sign.as_bytes());
    let md5_hex = format!("{:x}", hasher.finalize());

    let runtime = Runtime::new().map_err(|e| MoovieError::Unknown(e.to_string()))?;
    let context = Context::full(&runtime).map_err(|e| MoovieError::Unknown(e.to_string()))?;
    context.with(|ctx| {
        ctx.eval::<(), _>(
            r#"
            globalThis.window = globalThis;
            globalThis.self = globalThis;
            globalThis.document = {};
            globalThis.navigator = {
              userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
            };
            "#,
        )
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;
        ctx.eval::<(), _>(SIGN_JS)
            .map_err(|e| MoovieError::Unknown(e.to_string()))?;
        ctx.globals()
            .set("__codex_md5_input", md5_hex.clone())
            .map_err(|e| MoovieError::Unknown(e.to_string()))?;
        let signature: String = ctx
            .eval("get_sign(__codex_md5_input)")
            .map_err(|e| MoovieError::Unknown(e.to_string()))?;
        Ok(signature)
    })
}
