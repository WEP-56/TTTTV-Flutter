use axum::extract::ws::{Message as AxumMessage, WebSocket};
use bytes::Bytes;
use futures::{SinkExt, StreamExt};
use jcers::{Jce, JceMut, JceStruct, JceValue};
use std::time::Duration;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::{Message as WsMessage, client::IntoClientRequest};

use crate::live::models::{LiveMessage, LiveMessageColor, LiveMessageType};
use crate::live::providers::huya::HuyaDanmakuArgs;
use crate::utils::error::MoovieError;

const HEARTBEAT: [u8; 9] = [0, 20, 29, 0, 12, 44, 54, 0, 76]; // base64("ABQdAAwsNgBM")

pub async fn bridge(args: HuyaDanmakuArgs, socket: WebSocket) -> Result<(), MoovieError> {
    if args.ayyuid <= 0 || args.top_sid <= 0 {
        return Err(MoovieError::InvalidParameter(
            "虎牙弹幕参数无效".to_string(),
        ));
    }

    let ws_url = "wss://cdnws.api.huya.com";
    let request = ws_url
        .into_client_request()
        .map_err(|e| MoovieError::InvalidParameter(format!("ws url 解析失败: {}", e)))?;
    let (upstream, _resp) = connect_async(request)
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;
    let (mut up_tx, mut up_rx) = upstream.split();

    let (mut client_tx, mut client_rx) = socket.split();

    // join room (ported from dart_simple_live: tid=sid=topSid)
    let join = build_join_packet(args.ayyuid, args.top_sid, args.top_sid);
    up_tx
        .send(WsMessage::Binary(join))
        .await
        .map_err(|e| MoovieError::Unknown(e.to_string()))?;

    let mut heartbeat = tokio::time::interval(Duration::from_secs(60));

    loop {
        tokio::select! {
            _ = heartbeat.tick() => {
                if up_tx.send(WsMessage::Binary(HEARTBEAT.to_vec())).await.is_err() {
                    break;
                }
            }
            msg = up_rx.next() => {
                let Some(msg) = msg else { break; };
                let msg = match msg {
                    Ok(m) => m,
                    Err(_) => break,
                };
                if let WsMessage::Binary(data) = msg {
                    for live_msg in decode_huya_message(&data) {
                        let text = match serde_json::to_string(&live_msg) {
                            Ok(t) => t,
                            Err(_) => continue,
                        };
                        if client_tx.send(AxumMessage::Text(text)).await.is_err() {
                            return Ok(());
                        }
                    }
                }
            }
            client = client_rx.next() => {
                if client.is_none() {
                    break;
                }
            }
        }
    }

    Ok(())
}

fn build_join_packet(ayyuid: i64, tid: i64, sid: i64) -> Vec<u8> {
    // Inner payload
    let mut inner = JceMut::new();
    inner.put_i64(ayyuid, 0);
    inner.put_bool(true, 1);
    inner.put_string(String::new(), 2);
    inner.put_string(String::new(), 3);
    inner.put_i64(tid, 4);
    inner.put_i64(sid, 5);
    inner.put_i32(0, 6);
    inner.put_i32(0, 7);
    let inner_bytes = inner.freeze();

    // Outer command
    let mut outer = JceMut::new();
    outer.put_i32(1, 0);
    outer.put_bytes(inner_bytes, 1);
    outer.freeze().to_vec()
}

fn decode_huya_message(data: &[u8]) -> Vec<LiveMessage> {
    let mut out = Vec::new();
    let msg_type = get_tag_i32(data, 0).unwrap_or(0);
    if msg_type != 7 {
        return out;
    }

    let Some(payload) = get_tag_bytes(data, 1) else {
        return out;
    };
    let uri = get_tag_i32(payload.as_ref(), 1).unwrap_or(0);
    let Some(msg_bytes) = get_tag_bytes(payload.as_ref(), 2) else {
        return out;
    };

    match uri {
        1400 => {
            // chat
            let content = get_tag_string(msg_bytes.as_ref(), 3).unwrap_or_default();
            let user_name = {
                let user = get_tag_struct(msg_bytes.as_ref(), 0);
                user.and_then(|s| match s.get(&2) {
                    Some(JceValue::String(v)) => Some(v.clone()),
                    _ => None,
                })
                .unwrap_or_default()
            };
            let font_color = {
                let fmt = get_tag_struct(msg_bytes.as_ref(), 6);
                fmt.and_then(|s| match s.get(&0) {
                    Some(JceValue::I32(v)) => Some(*v as i64),
                    Some(JceValue::I64(v)) => Some(*v),
                    Some(JceValue::U8(v)) => Some(*v as i64),
                    _ => None,
                })
                .unwrap_or(0)
            };

            out.push(LiveMessage {
                kind: LiveMessageType::Chat,
                user_name,
                message: content,
                color: color_number_to_rgb(font_color),
                data: None,
            });
        }
        8006 => {
            // online count
            let online = get_tag_i64(msg_bytes.as_ref(), 0).unwrap_or(0);
            out.push(LiveMessage {
                kind: LiveMessageType::Online,
                user_name: "".to_string(),
                message: "".to_string(),
                color: LiveMessageColor {
                    r: 255,
                    g: 255,
                    b: 255,
                },
                data: Some(serde_json::json!(online)),
            });
        }
        _ => {}
    }

    out
}

fn get_tag_i32(data: &[u8], tag: u8) -> Option<i32> {
    let mut buf = Bytes::copy_from_slice(data);
    let mut jce = Jce::new(&mut buf);
    jce.get_by_tag::<i32>(tag).ok()
}

fn get_tag_i64(data: &[u8], tag: u8) -> Option<i64> {
    let mut buf = Bytes::copy_from_slice(data);
    let mut jce = Jce::new(&mut buf);
    jce.get_by_tag::<i64>(tag).ok()
}

fn get_tag_string(data: &[u8], tag: u8) -> Option<String> {
    let mut buf = Bytes::copy_from_slice(data);
    let mut jce = Jce::new(&mut buf);
    jce.get_by_tag::<String>(tag).ok()
}

fn get_tag_bytes(data: &[u8], tag: u8) -> Option<Bytes> {
    let mut buf = Bytes::copy_from_slice(data);
    let mut jce = Jce::new(&mut buf);
    jce.get_by_tag::<Bytes>(tag).ok()
}

fn get_tag_struct(data: &[u8], tag: u8) -> Option<JceStruct> {
    let mut buf = Bytes::copy_from_slice(data);
    let mut jce = Jce::new(&mut buf);
    jce.get_by_tag::<JceStruct>(tag).ok()
}

fn color_number_to_rgb(color: i64) -> LiveMessageColor {
    if color <= 0 {
        return LiveMessageColor {
            r: 255,
            g: 255,
            b: 255,
        };
    }
    let mut hex = format!("{:x}", color as u64);
    if hex.len() == 4 {
        hex = format!("00{}", hex);
    }
    if hex.len() == 8 {
        hex = hex.chars().skip(2).collect();
    }
    if hex.len() != 6 {
        return LiveMessageColor {
            r: 255,
            g: 255,
            b: 255,
        };
    }
    let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(255);
    let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(255);
    let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(255);
    LiveMessageColor { r, g, b }
}
